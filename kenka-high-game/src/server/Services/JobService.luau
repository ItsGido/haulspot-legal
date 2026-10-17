--!strict
-- Part-time jobs in town (blueprint section 6.4). Every job is an active minigame; the server checks
-- positions, timing and score sanity, and pays through DataService.AddYen(player, pay, "Job").
--
-- One job at a time (player attribute ActiveJob = job id) with a cooldown per job.
-- Job_Update payloads (S->C):
--   Started  RamenDelivery   { Drops = { Vector3 }, Index = 1, EndsAt }
--            KonbiniShift    { Notes, Seconds, MinDuration, EndsAt }
--            ArcadeAttendant { Tokens = { Vector3 }, Collected = 0, Total, EndsAt }
--   Progress RamenDelivery   { Drops, Index }               (Index = the next drop to reach)
--            ArcadeAttendant { Tokens = { Vector3 } (remaining), Collected, Total }
--   Finished { Pay, Gold }
--   Cancelled { Reason }
-- EndsAt is server time (workspace:GetServerTimeNow()).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Net = require(ReplicatedStorage.Shared.Util.Net)
local RateLimiter = require(ReplicatedStorage.Shared.Util.RateLimiter)
local Cleaner = require(ReplicatedStorage.Shared.Util.Cleaner)
local Notify = require(script.Parent.Parent.Systems.Notify)
local EconomyUtil = require(script.Parent.Parent.Systems.EconomyUtil)

local JobService = {}
JobService.Priority = 50

local Services: any

local TICK = 0.25 -- seconds between server checks (drops, tokens, cancel conditions)
local TIMEOUT_FACTOR = 1.5 -- a job fails after Duration x this
local DROP_Y = 3 -- ramen drop marker height (ground top is Y = 0)
local TOKEN_Y = 2.5
local TOKEN_BUILDING_MARGIN = 4 -- keep arcade tokens this far from building walls
local TOKEN_SPAWN_TRIES = 40
local KONBINI_NOTES = 40
local KONBINI_SECONDS = 60
local KONBINI_PASS = 0.6
local KONBINI_GOLD = 0.9
local KONBINI_LEAVE_RANGE = 40 -- studs from the konbini job counter before the shift is abandoned
local SUBMIT_DURATION_SLACK = 3 -- client-reported duration may exceed the server's by this much (latency)

type Active = {
	JobId: string,
	Job: Economy.Job,
	StartedAt: number, -- os.clock()
	Deadline: number, -- os.clock()
	EndsAt: number, -- server time, for the client timer
	Cleaner: any, -- Cleaner.Cleaner (typed as any: metatable types trip the solver in loops)
	Drops: { Vector3 }?,
	Index: number,
	Tokens: { BasePart }?,
	Total: number,
	Collected: number,
	Anchor: Vector3?,
}

local active: { [Player]: Active } = {}
local cooldowns: { [Player]: { [string]: number } } = {}
local limiter = RateLimiter.new(4, 2)
local jobUpdate = Net.Event("Job_Update")
local tokenFolder: Folder? = nil

local function send(player: Player, jobId: string, state: string, data: any?)
	if player.Parent == Players then
		jobUpdate:FireClient(player, { JobId = jobId, State = state, Data = data })
	end
end

local function horizontalDistance(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

local function isMorning(): boolean
	return Services.DayCycleService ~= nil and Services.DayCycleService.GetPeriod().Id == "Morning"
end

local function clearJob(player: Player): Active?
	local job = active[player]
	if not job then
		return nil
	end
	active[player] = nil
	job.Cleaner:Clean()
	if player.Parent == Players then
		player:SetAttribute("ActiveJob", nil)
		local list = cooldowns[player]
		if not list then
			local created = {}
			cooldowns[player] = created
			list = created
		end
		(list :: { [string]: number })[job.JobId] = os.clock() + job.Job.Cooldown
	end
	return job
end

local function cancel(player: Player, reason: string)
	local job = clearJob(player)
	if not job then
		return
	end
	send(player, job.JobId, "Cancelled", { Reason = reason })
	if player.Parent == Players then
		Notify.Send(player, job.Job.Name .. " cancelled: " .. reason, "bad")
	end
end

local function finish(player: Player, basePay: number, gold: boolean)
	local job = active[player]
	if not job then
		return
	end
	local elapsed = os.clock() - job.StartedAt
	if elapsed < job.Job.MinDuration then
		cancel(player, "That was impossibly fast.")
		return
	end
	clearJob(player)
	local pay = basePay + (if gold then job.Job.GoldBonus else 0)
	if isMorning() then
		pay = math.floor(pay * (1 + Economy.MorningJobBonus) + 0.5)
	end
	local added = Services.DataService.AddYen(player, pay, "Job")
	if Services.QuestService then
		Services.QuestService.Progress(player, "FinishJob", 1)
	end
	send(player, job.JobId, "Finished", { Pay = added, Gold = gold })
	Notify.Send(player, string.format("%s done! +%s%s", job.Job.Name, Format.Yen(added), if gold then " (GOLD!)" else ""), "gold", 5)
end

-- Job setup ---------------------------------------------------------------------------

local function insideBuilding(x: number, z: number): boolean
	for _, b in MapData.Buildings do
		if b.BaseY < DROP_Y and math.abs(x - b.X) <= b.SizeX / 2 + TOKEN_BUILDING_MARGIN and math.abs(z - b.Z) <= b.SizeZ / 2 + TOKEN_BUILDING_MARGIN then
			return true
		end
	end
	return false
end

local function startRamen(player: Player, job: Active)
	local points = EconomyUtil.Shuffled(Economy.RamenDropPoints, Random.new())
	local drops = {}
	for i = 1, math.min(Economy.RamenDropsPerRun, #points) do
		table.insert(drops, Vector3.new(points[i][1], DROP_Y, points[i][2]))
	end
	job.Drops = drops
	job.Index = 1
	send(player, job.JobId, "Started", { Drops = drops, Index = 1, EndsAt = job.EndsAt })
end

local function startKonbini(player: Player, job: Active)
	local interactable = MapData.GetInteractable(job.Job.Interactable)
	job.Anchor = EconomyUtil.InteractablePosition(job.Job.Interactable)
		or (if interactable then Vector3.new(interactable.X, interactable.Y, interactable.Z) else nil)
	send(player, job.JobId, "Started", { Notes = KONBINI_NOTES, Seconds = KONBINI_SECONDS, MinDuration = job.Job.MinDuration, EndsAt = job.EndsAt })
end

local function makeToken(owner: Player, position: Vector3): Part
	local token = Instance.new("Part")
	token.Name = "ArcadeToken"
	token.Shape = Enum.PartType.Cylinder
	token.Size = Vector3.new(0.3, 1.8, 1.8)
	token.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, 0)
	token.Color = Color3.fromHex("#FFD23F")
	token.Material = Enum.Material.Neon
	token.Anchored = true
	token.CanCollide = false
	token.CanQuery = false
	token.CanTouch = false
	token:SetAttribute("OwnerUserId", owner.UserId)
	local light = Instance.new("PointLight")
	light.Color = token.Color
	light.Range = 8
	light.Brightness = 1.5
	light.Parent = token
	token.Parent = tokenFolder
	return token
end

local function startArcade(player: Player, job: Active)
	local area = Economy.ArcadeTokenArea
	local cx, cz, halfX, halfZ = area[1], area[2], area[3], area[4]
	local rng = Random.new()
	local tokens: { BasePart } = {}
	local positions: { Vector3 } = {}
	local tries = 0
	while #tokens < Economy.ArcadeTokensPerRun and tries < TOKEN_SPAWN_TRIES * Economy.ArcadeTokensPerRun do
		tries += 1
		local x = cx + rng:NextNumber(-halfX, halfX)
		local z = cz + rng:NextNumber(-halfZ, halfZ)
		if not insideBuilding(x, z) then
			local position = Vector3.new(x, TOKEN_Y, z)
			local token = makeToken(player, position)
			job.Cleaner:Add(token)
			table.insert(tokens, token)
			table.insert(positions, position)
		end
	end
	job.Tokens = tokens
	job.Total = #tokens
	job.Collected = 0
	send(player, job.JobId, "Started", { Tokens = positions, Collected = 0, Total = #tokens, EndsAt = job.EndsAt })
end

local function startJob(player: Player, jobId: string)
	local config = (Economy.Jobs :: any)[jobId] :: Economy.Job?
	if not config then
		Notify.Send(player, "That job isn't hiring.", "bad")
		return
	end
	if active[player] then
		Notify.Send(player, "Finish your current job first.", "bad")
		return
	end
	if not Services.DataService.GetProfile(player) then
		return
	end
	if EconomyUtil.InTutorial(Services, player) then
		Notify.Send(player, "Finish the tutorial first.", "info")
		return
	end
	if EconomyUtil.InCombat(Services, player) or EconomyUtil.IsDowned(Services, player) or not EconomyUtil.IsAlive(player) then
		return
	end
	local readyAt = cooldowns[player] and cooldowns[player][jobId] or 0
	if os.clock() < readyAt then
		Notify.Send(player, string.format("The manager says come back in %ds.", math.ceil(readyAt - os.clock())), "info")
		return
	end

	local now = os.clock()
	local timeout = config.Duration * TIMEOUT_FACTOR
	local job: Active = {
		JobId = jobId,
		Job = config,
		StartedAt = now,
		Deadline = now + timeout,
		EndsAt = EconomyUtil.ServerNow() + timeout,
		Cleaner = Cleaner.new(),
		Index = 1,
		Total = 0,
		Collected = 0,
	}
	active[player] = job
	player:SetAttribute("ActiveJob", jobId)
	if jobId == "RamenDelivery" then
		startRamen(player, job)
	elseif jobId == "KonbiniShift" then
		startKonbini(player, job)
	elseif jobId == "ArcadeAttendant" then
		startArcade(player, job)
	else
		clearJob(player)
		Notify.Send(player, "That job isn't hiring.", "bad")
		return
	end
	Notify.Send(player, config.Name .. ": " .. config.Description, "info", 5)
	local humanoid = EconomyUtil.GetHumanoid(player)
	if humanoid then
		job.Cleaner:Add(humanoid.Died:Connect(function()
			if active[player] == job then
				cancel(player, "You went down.")
			end
		end))
	end
end

-- Per-tick checks -----------------------------------------------------------------------

local function tickRamen(player: Player, job: Active, root: BasePart)
	local drops = job.Drops
	if not drops then
		return
	end
	local target = drops[job.Index]
	if target and horizontalDistance(root.Position, target) <= Economy.RamenDropRadius then
		job.Index += 1
		if job.Index > #drops then
			local elapsed = os.clock() - job.StartedAt
			finish(player, job.Job.Pay, job.Job.GoldTime ~= nil and elapsed <= (job.Job.GoldTime :: number))
		else
			Notify.Send(player, string.format("🍜 Delivered! %d to go.", #drops - job.Index + 1), "good", 2)
			send(player, job.JobId, "Progress", { Drops = drops, Index = job.Index })
		end
	end
end

local function tickArcade(player: Player, job: Active, root: BasePart)
	local tokens = job.Tokens
	if not tokens then
		return
	end
	local collectedAny = false
	for i = #tokens, 1, -1 do
		local token = tokens[i]
		if token.Parent and token:GetAttribute("OwnerUserId") == player.UserId and (token.Position - root.Position).Magnitude <= Economy.ArcadeTokenRadius then
			table.remove(tokens, i)
			token:Destroy()
			job.Collected += 1
			collectedAny = true
		end
	end
	if not collectedAny then
		return
	end
	if #tokens == 0 then
		local elapsed = os.clock() - job.StartedAt
		finish(player, job.Job.Pay, job.Job.GoldTime ~= nil and elapsed <= (job.Job.GoldTime :: number))
	else
		local positions = {}
		for _, token in tokens do
			table.insert(positions, token.Position)
		end
		send(player, job.JobId, "Progress", { Tokens = positions, Collected = job.Collected, Total = job.Total })
	end
end

local function tick()
	for player, job in active do
		if player.Parent ~= Players then
			clearJob(player)
			continue
		end
		local root = EconomyUtil.GetRoot(player)
		if not root or not EconomyUtil.IsAlive(player) then
			cancel(player, "You went down.")
		elseif EconomyUtil.IsDowned(Services, player) then
			cancel(player, "You got knocked down.")
		elseif EconomyUtil.InCombat(Services, player) then
			cancel(player, "You got into a fight.")
		elseif os.clock() > job.Deadline then
			cancel(player, if job.JobId == "RamenDelivery" then "Too slow. The ramen went cold." else "Out of time.")
		elseif job.JobId == "RamenDelivery" then
			tickRamen(player, job, root)
		elseif job.JobId == "ArcadeAttendant" then
			tickArcade(player, job, root)
		elseif job.JobId == "KonbiniShift" and job.Anchor and (root.Position - (job.Anchor :: Vector3)).Magnitude > KONBINI_LEAVE_RANGE then
			cancel(player, "You walked out on your shift.")
		end
	end
end

-- Remotes --------------------------------------------------------------------------------

local function onSubmit(player: Player, jobId: any, data: any)
	if not limiter:Allow(player) then
		return
	end
	local job = active[player]
	if not job or jobId ~= job.JobId or job.JobId ~= "KonbiniShift" or type(data) ~= "table" then
		return
	end
	local hits, misses, duration = data.Hits, data.Misses, data.Duration
	if not EconomyUtil.IsInt(hits, 0, KONBINI_NOTES) or not EconomyUtil.IsInt(misses, 0, KONBINI_NOTES) or not EconomyUtil.IsNumber(duration) then
		cancel(player, "The register jammed.")
		return
	end
	local serverElapsed = os.clock() - job.StartedAt
	if hits + misses ~= KONBINI_NOTES or duration < job.Job.MinDuration or serverElapsed < job.Job.MinDuration or duration > serverElapsed + SUBMIT_DURATION_SLACK then
		cancel(player, "The manager didn't buy that.")
		return
	end
	local accuracy = hits / KONBINI_NOTES
	if accuracy < KONBINI_PASS then
		cancel(player, string.format("Too many missed customers (%d%%).", math.floor(accuracy * 100)))
		return
	end
	finish(player, math.floor(job.Job.Pay * accuracy + 0.5), accuracy >= KONBINI_GOLD)
end

-- Lifecycle --------------------------------------------------------------------------------

function JobService.Init(services: any)
	Services = services
	Services.InteractionService.Register("Job", function(player: Player, interactable: any)
		if type(interactable.Job) == "string" then
			startJob(player, interactable.Job)
		end
	end)
	Net.Event("Job_Submit").OnServerEvent:Connect(onSubmit)
	Net.Event("Job_Cancel").OnServerEvent:Connect(function(player: Player)
		if limiter:Allow(player) and active[player] then
			cancel(player, "You quit.")
		end
	end)
end

function JobService.Start()
	local folder = Instance.new("Folder")
	folder.Name = "EconomyJobTokens"
	folder.Parent = workspace
	tokenFolder = folder

	Players.PlayerRemoving:Connect(function(player)
		clearJob(player)
		cooldowns[player] = nil
		limiter:Remove(player)
	end)
	while true do
		task.wait(TICK)
		tick()
	end
end

return JobService
