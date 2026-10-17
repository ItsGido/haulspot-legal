--!strict
-- Loads, saves and replicates player profiles (blueprint section 7.1 DataService, 7.2 schema).
--
-- Saving model:
--   DataStore key "u_<userId>" holds { Data = profile, Lock = { JobId, Time } | nil }.
--   Loading takes the session lock with UpdateAsync. If another live server holds it, we retry, then
--   steal it once it is older than Game.SessionLockTimeout. Saves only write while we still own the lock.
--   A profile that fails to load is never replaced with defaults: the player is kicked instead.
--   In Studio with API access off, players get an unsaved in-memory profile (Game.Studio setting).
--
-- Other services should change profiles through DataService.Update / AddYen / SpendYen / AddScrolls,
-- then the changed top-level keys are replicated to the owning client with Data_Update.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Ranks = require(ReplicatedStorage.Shared.Config.Ranks)
local Styles = require(ReplicatedStorage.Shared.Config.Styles)
local HeightStats = require(ReplicatedStorage.Shared.Logic.HeightStats)
local RepMath = require(ReplicatedStorage.Shared.Logic.RepMath)
local Net = require(ReplicatedStorage.Shared.Util.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local DataService = {}
DataService.Priority = 10

DataService.ProfileLoaded = Signal.new() -- (player, profile)
DataService.ProfileReleasing = Signal.new() -- (player, profile) fired before the final save

local Services: any

local DEFAULT_PROFILE = {
	Version = 1,
	Yen = Economy.StartingYen,
	Rep = 0,
	Rank = 1,
	Scrolls = 0,
	HeightCm = HeightStats.DefaultCm,
	Appearance = { Face = 1, Hair = 1, HairColor = 1 },
	Uniform = "UniformClassic",
	OwnedUniforms = { UniformClassic = true },
	Styles = { Owned = { Styles.DefaultStyle }, Equipped = Styles.DefaultStyle, Mastery = {} },
	Cosmetics = { Owned = {}, Equipped = {} }, -- Owned[itemId] = true, Equipped[slot] = itemId
	Capsule = { PityEpic = 0, PityLegendary = 0, Points = 0, Tokens = 0 },
	Quests = {
		Day = 0,
		Daily = {}, -- { { Id, Progress, Claimed } }
		RerollsUsed = 0,
		Week = 0,
		Weekly = {},
		Story = { Index = 1, Progress = 0 },
	},
	Login = { Streak = 0, LastDay = 0 },
	CrewId = "",
	Vehicles = {}, -- Vehicles[vehicleId] = true
	Settings = { Music = 0.6, SFX = 0.8, CameraShake = true, DamageNumbers = true, RookieOptOut = false, MobileLayout = {} },
	Stats = { Wins = 0, Losses = 0, DuelsWon = 0, TourneysWon = 0, TurfCaptures = 0, PlaytimeMin = 0, Parries = 0 },
	Term = { Id = 1, Rep = 0, PassOwned = false },
	StarterPack = { FirstJoin = 0, Offered = false, Bought = false },
	YenPay = { Day = 0, Sent = 0 },
	CustomName = "",
	StyleTickets = 0, -- unredeemed Style Ticket purchases
	Badges = {}, -- Badges[badgeId] = true
	LastHeightChange = 0,
	RookieOptOutAt = 0,
	TutorialDone = false,
	PurchaseHistory = {}, -- receipt ids, newest last, max 100 (server only, never replicated)
}

local PRIVATE_KEYS = { PurchaseHistory = true }

type Session = {
	Profile: any,
	Memory: boolean, -- true = unsaved Studio profile
	Released: boolean,
	LastSave: number,
}

local sessions: { [Player]: Session } = {}
local store: DataStore? = nil
local dataUpdate = Net.Event("Data_Update")

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

-- Fill missing keys from the defaults without touching existing values.
local function reconcile(target: any, template: any)
	for key, value in template do
		if target[key] == nil then
			target[key] = deepCopy(value)
		elseif type(value) == "table" and type(target[key]) == "table" and next(value) ~= nil then
			-- Only recurse into dictionaries with fixed keys (empty templates are free-form maps/lists).
			if #value == 0 then
				reconcile(target[key], value)
			end
		end
	end
end

local function keyFor(player: Player): string
	return "u_" .. player.UserId
end

local function now(): number
	return os.time()
end

local function getOrCreate(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = parent
	return created
end

local function setupLeaderstats(player: Player, profile: any)
	local folder = getOrCreate(player, "Folder", "leaderstats")
	local rank = getOrCreate(folder, "StringValue", "Rank") :: StringValue
	local rep = getOrCreate(folder, "IntValue", "Rep") :: IntValue
	local entry = Ranks.List[profile.Rank] or Ranks.List[1]
	rank.Value = entry.Title
	rep.Value = profile.Rep
end

local function syncAttributes(player: Player, profile: any)
	player:SetAttribute("Yen", profile.Yen)
	player:SetAttribute("Rep", profile.Rep)
	player:SetAttribute("Rank", profile.Rank)
	player:SetAttribute("RankTitle", (Ranks.List[profile.Rank] or Ranks.List[1]).Title)
	player:SetAttribute("Scrolls", profile.Scrolls)
	player:SetAttribute("Style", profile.Styles.Equipped)
	player:SetAttribute("HeightCm", profile.HeightCm)
	player:SetAttribute("CrewId", profile.CrewId)
	player:SetAttribute("TutorialDone", profile.TutorialDone)
	player:SetAttribute(
		"RookieProtected",
		profile.Rank <= Ranks.RookieMaxRank and not profile.Settings.RookieOptOut
	)
	setupLeaderstats(player, profile)
end

local function publicCopy(player: Player, profile: any): any
	local copy = {}
	for key, value in profile do
		if not PRIVATE_KEYS[key] then
			copy[key] = deepCopy(value)
		end
	end
	local passes = {}
	if Services and Services.MonetizationService and Services.MonetizationService.GetOwnedPasses then
		passes = Services.MonetizationService.GetOwnedPasses(player)
	end
	copy.Derived = { Passes = passes, Memory = sessions[player] and sessions[player].Memory or false }
	return copy
end

-- Session lock aware load. Returns profile, isMemory, or nil + reason.
local function loadProfile(player: Player): (any?, boolean, string?)
	if not store then
		if RunService:IsStudio() and GameConfig.Studio.UseMemoryDataWhenStoreUnavailable then
			return deepCopy(DEFAULT_PROFILE), true, nil
		end
		return nil, false, "DataStore unavailable"
	end
	local dataStore = store :: DataStore
	local key = keyFor(player)
	local attempts = 0
	while attempts < GameConfig.DataLoadRetries + 3 do
		attempts += 1
		local lockedByOther = false
		local ok, result = pcall(function()
			return dataStore:UpdateAsync(key, function(old: any)
				local record = old or {}
				local lock = record.Lock
				if lock and lock.JobId ~= game.JobId and now() - (lock.Time or 0) < GameConfig.SessionLockTimeout then
					lockedByOther = true
					return nil -- cancel the write
				end
				record.Lock = { JobId = game.JobId, Time = now() }
				record.Data = record.Data or deepCopy(DEFAULT_PROFILE)
				return record
			end)
		end)
		if ok and result and not lockedByOther then
			return (result :: any).Data, false, nil
		end
		if not ok then
			warn(string.format("[DataService] Load attempt %d failed for %s: %s", attempts, player.Name, tostring(result)))
			if RunService:IsStudio() and GameConfig.Studio.UseMemoryDataWhenStoreUnavailable and tostring(result):find("API") then
				return deepCopy(DEFAULT_PROFILE), true, nil
			end
		end
		if player.Parent ~= Players then
			return nil, false, "left"
		end
		task.wait(if lockedByOther then 6 else 2 ^ attempts)
	end
	return nil, false, "Your data is still saving on another server. Please rejoin in a minute."
end

local function saveProfile(player: Player, release: boolean): boolean
	local session = sessions[player]
	if not session or session.Memory or not store then
		return true
	end
	local dataStore = store :: DataStore
	local profile = session.Profile
	local ok, err = pcall(function()
		dataStore:UpdateAsync(keyFor(player), function(old: any)
			local record = old or {}
			if record.Lock and record.Lock.JobId ~= game.JobId then
				return nil -- another server took over; never overwrite its data
			end
			record.Data = profile
			record.Lock = if release then nil else { JobId = game.JobId, Time = now() }
			return record
		end)
	end)
	if ok then
		session.LastSave = os.clock()
	else
		warn(string.format("[DataService] Save failed for %s: %s", player.Name, tostring(err)))
	end
	return ok
end

local function onPlayerAdded(player: Player)
	local profile, memory, reason = loadProfile(player)
	if player.Parent ~= Players then
		if profile and not memory then
			-- They left while loading: release the lock we just took.
			sessions[player] = { Profile = profile, Memory = false, Released = false, LastSave = 0 }
			saveProfile(player, true)
			sessions[player] = nil
		end
		return
	end
	if not profile then
		player:Kick("Data failed to load: " .. tostring(reason) .. " Please rejoin.")
		return
	end

	reconcile(profile, DEFAULT_PROFILE)
	profile.Rank = RepMath.RankForRep(Ranks, profile.Rep)
	if profile.StarterPack.FirstJoin == 0 then
		profile.StarterPack.FirstJoin = now()
	end
	if RunService:IsStudio() and GameConfig.Studio.SkipTutorial then
		profile.TutorialDone = true
	end

	sessions[player] = { Profile = profile, Memory = memory, Released = false, LastSave = os.clock() }
	syncAttributes(player, profile)
	if memory then
		warn("[DataService] Using an UNSAVED in-memory profile for " .. player.Name .. " (Studio API access is off).")
	end
	DataService.ProfileLoaded:Fire(player, profile)
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if not session or session.Released then
		return
	end
	session.Released = true
	DataService.ProfileReleasing:Fire(player, session.Profile)
	task.wait() -- let ProfileReleasing handlers write session data first
	saveProfile(player, true)
	sessions[player] = nil
end

-- Public API -----------------------------------------------------------------

function DataService.GetProfile(player: Player): any?
	local session = sessions[player]
	return if session and not session.Released then session.Profile else nil
end

-- Yields until the profile is loaded (or the player leaves). Returns nil if they left.
function DataService.WaitForProfile(player: Player): any?
	while player.Parent == Players do
		local profile = DataService.GetProfile(player)
		if profile then
			return profile
		end
		task.wait(0.1)
	end
	return nil
end

function DataService.IsMemoryProfile(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.Memory
end

-- Sends the given top-level keys to the owning client and refreshes attributes.
function DataService.Replicate(player: Player, ...: string)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	local payload = {}
	for _, key in { ... } do
		if not PRIVATE_KEYS[key] then
			payload[key] = profile[key]
		end
	end
	syncAttributes(player, profile)
	dataUpdate:FireClient(player, payload)
end

-- Runs fn(profile) and replicates the listed keys. Returns whatever fn returns.
function DataService.Update(player: Player, keys: { string }, fn: (profile: any) -> ...any): ...any
	local profile = DataService.GetProfile(player)
	if not profile then
		return nil
	end
	local results = table.pack(fn(profile))
	DataService.Replicate(player, table.unpack(keys))
	return table.unpack(results, 1, results.n)
end

-- Adds yen. Sources "Job" and "Class" get the VIP (+10%) and 2x Yen pass bonuses.
-- Returns the amount actually added.
function DataService.AddYen(player: Player, amount: number, source: string?): number
	local profile = DataService.GetProfile(player)
	if not profile or amount <= 0 then
		return 0
	end
	local total = amount
	if (source == "Job" or source == "Class") and Services.MonetizationService then
		if Services.MonetizationService.OwnsPass(player, "DoubleYen") then
			total *= 2
		end
		if Services.MonetizationService.OwnsPass(player, "VIP") then
			total *= 1.1
		end
	end
	total = math.floor(total + 0.5)
	profile.Yen += total
	DataService.Replicate(player, "Yen")
	if Services.QuestService then
		Services.QuestService.Progress(player, "EarnYen", total)
	end
	return total
end

-- Spends yen if the player can afford it. Returns true on success.
function DataService.SpendYen(player: Player, amount: number): boolean
	local profile = DataService.GetProfile(player)
	if not profile or amount < 0 or profile.Yen < amount then
		return false
	end
	profile.Yen -= amount
	DataService.Replicate(player, "Yen")
	return true
end

function DataService.AddScrolls(player: Player, amount: number)
	local profile = DataService.GetProfile(player)
	if not profile or amount == 0 then
		return
	end
	profile.Scrolls = math.max(0, profile.Scrolls + amount)
	DataService.Replicate(player, "Scrolls")
end

function DataService.GetPublicProfile(player: Player): any?
	local profile = DataService.GetProfile(player)
	return if profile then publicCopy(player, profile) else nil
end

-- Save immediately (e.g. right after a Robux purchase). Returns true on success.
function DataService.SaveNow(player: Player): boolean
	return saveProfile(player, false)
end

function DataService.HasPurchase(player: Player, receiptId: string): boolean
	local profile = DataService.GetProfile(player)
	if not profile then
		return false
	end
	return table.find(profile.PurchaseHistory, receiptId) ~= nil
end

function DataService.RecordPurchase(player: Player, receiptId: string)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	table.insert(profile.PurchaseHistory, receiptId)
	while #profile.PurchaseHistory > 100 do
		table.remove(profile.PurchaseHistory, 1)
	end
end

-- Lifecycle --------------------------------------------------------------------

function DataService.Init(services: any)
	Services = services
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.ProfileStoreName)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStore unavailable: " .. tostring(result))
	end

	Net.Function("Data_Request").OnServerInvoke = function(player: Player)
		DataService.WaitForProfile(player)
		return DataService.GetPublicProfile(player)
	end

	Net.Event("Settings_Save").OnServerEvent:Connect(function(player: Player, settings: any)
		local profile = DataService.GetProfile(player)
		if not profile or type(settings) ~= "table" then
			return
		end
		local s = profile.Settings
		if type(settings.Music) == "number" then
			s.Music = math.clamp(settings.Music, 0, 1)
		end
		if type(settings.SFX) == "number" then
			s.SFX = math.clamp(settings.SFX, 0, 1)
		end
		if type(settings.CameraShake) == "boolean" then
			s.CameraShake = settings.CameraShake
		end
		if type(settings.DamageNumbers) == "boolean" then
			s.DamageNumbers = settings.DamageNumbers
		end
		if type(settings.MobileLayout) == "table" then
			s.MobileLayout = settings.MobileLayout
		end
		if type(settings.RookieOptOut) == "boolean" and settings.RookieOptOut ~= s.RookieOptOut then
			-- Turning protection back on is blocked for 10 minutes after opting out, and during fights.
			local inCombat = Services.CombatService and Services.CombatService.IsInCombat(player)
			if settings.RookieOptOut then
				s.RookieOptOut = true
				profile.RookieOptOutAt = now()
			elseif not inCombat and now() - profile.RookieOptOutAt >= Ranks.RookieReenableCooldown then
				s.RookieOptOut = false
			end
		end
		DataService.Replicate(player, "Settings")
	end)
end

function DataService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Autosave
	task.spawn(function()
		while true do
			task.wait(10)
			for player, session in sessions do
				if not session.Released and os.clock() - session.LastSave >= GameConfig.AutosaveInterval then
					task.spawn(saveProfile, player, false)
				end
			end
		end
	end)

	-- Playtime tracking
	task.spawn(function()
		while true do
			task.wait(60)
			for _, session in sessions do
				if not session.Released then
					session.Profile.Stats.PlaytimeMin += 1
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in sessions do
			pending += 1
			task.spawn(function()
				onPlayerRemoving(player)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.1)
		end
	end)
end

return DataService
