--!strict
-- Fighting styles and mastery (blueprint section 6.6).
--   StyleService.GetEquippedStyle(player) -> Style config
--   StyleService.GetMasteryLevel(player, styleId?) -> number
--   StyleService.HasTechnique(player, "Tech1"|"Tech2"|"Heat") -> boolean
--   StyleService.AddMasteryXP(player, xp)  (equipped style)
--   StyleService.GrantStyle(player, styleId) -> boolean (true if newly granted)
--   StyleService.EquipStyle(player, styleId) -> boolean (no range check; used by the tutorial)
-- Remotes: Style_Equip (RF, near the Sensei), Style_Unlock (RF, "Scrolls" | "Robux").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StylesConfig = require(ReplicatedStorage.Shared.Config.Styles)
local CombatMath = require(ReplicatedStorage.Shared.Logic.CombatMath)
local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local Net = require(ReplicatedStorage.Shared.Util.Net)
local RateLimiter = require(ReplicatedStorage.Shared.Util.RateLimiter)
local Notify = require(script.Parent.Parent.Systems.Notify)
local Util = require(script.Parent.Parent.Systems.ProgressionUtil)

local StyleService = {}
StyleService.Priority = 45

local Services: any

local MIN_MASTERY = 1
local TICKET_POLL = 1 -- seconds between checks for a landed Style Ticket purchase
local REMOTE_RATE, REMOTE_PER = 4, 1

local SLOT_MASTERY: { [string]: number } = {
	Tech1 = StylesConfig.Tech1Mastery,
	Tech2 = StylesConfig.Tech2Mastery,
	Heat = StylesConfig.HeatMastery,
}

local limiter = RateLimiter.new(REMOTE_RATE, REMOTE_PER)
local pendingTicket: { [Player]: string } = {} -- styleId waiting for a StyleTicket purchase

local senseiPosition: Vector3 = Vector3.zero
do
	for _, item in MapData.Interactables do
		if item.Kind == "Dojo" then
			senseiPosition = Vector3.new(item.X, item.Y, item.Z)
			break
		end
	end
end

local function getStyle(styleId: any): StylesConfig.Style?
	if type(styleId) ~= "string" then
		return nil
	end
	return StylesConfig.Styles[styleId]
end

local function owns(profile: any, styleId: string): boolean
	return table.find(profile.Styles.Owned, styleId) ~= nil
end

local function masteryEntry(profile: any, styleId: string): any
	local mastery = profile.Styles.Mastery
	local entry = mastery[styleId]
	if type(entry) ~= "table" then
		local created = { Level = MIN_MASTERY, XP = 0 }
		mastery[styleId] = created
		return created
	end
	return entry
end

-- Public API -----------------------------------------------------------------

function StyleService.GetEquippedStyle(player: Player): StylesConfig.Style
	local profile = Services.DataService.GetProfile(player)
	local id = if profile then profile.Styles.Equipped else player:GetAttribute("Style")
	return getStyle(id) or StylesConfig.Styles[StylesConfig.DefaultStyle]
end

function StyleService.GetMasteryLevel(player: Player, styleId: string?): number
	local profile = Services.DataService.GetProfile(player)
	if not profile then
		return MIN_MASTERY
	end
	local id = styleId or profile.Styles.Equipped
	local entry = profile.Styles.Mastery[id]
	if type(entry) == "table" and type(entry.Level) == "number" then
		return entry.Level
	end
	return MIN_MASTERY
end

function StyleService.HasTechnique(player: Player, slot: string): boolean
	local needed = SLOT_MASTERY[slot]
	if not needed then
		return false
	end
	return StyleService.GetMasteryLevel(player) >= needed
end

function StyleService.AddMasteryXP(player: Player, xp: number)
	local profile = Services.DataService.GetProfile(player)
	if not profile or type(xp) ~= "number" or xp <= 0 or xp ~= xp then
		return
	end
	local styleId = profile.Styles.Equipped
	local style = getStyle(styleId)
	if not style then
		return
	end
	local entry = masteryEntry(profile, styleId)
	local oldLevel = entry.Level
	local level, newXP = CombatMath.AddMasteryXP(
		entry.Level,
		entry.XP,
		math.floor(xp),
		StylesConfig.MasteryXPPerLevel,
		StylesConfig.MaxMastery
	)
	entry.Level = level
	entry.XP = newXP
	Services.DataService.Replicate(player, "Styles")
	if level > oldLevel then
		Notify.Send(player, string.format("%s Mastery %d!", style.DisplayName, level), "gold")
		for slot, needed in SLOT_MASTERY do
			if oldLevel < needed and level >= needed then
				local technique = (style :: any)[slot]
				Notify.Send(player, string.format("New technique unlocked: %s", technique.Name), "gold", 5)
			end
		end
	end
end

function StyleService.GrantStyle(player: Player, styleId: string): boolean
	local profile = Services.DataService.GetProfile(player)
	if not profile or not getStyle(styleId) or owns(profile, styleId) then
		return false
	end
	table.insert(profile.Styles.Owned, styleId)
	masteryEntry(profile, styleId)
	Services.DataService.Replicate(player, "Styles")
	return true
end

function StyleService.EquipStyle(player: Player, styleId: string): boolean
	local profile = Services.DataService.GetProfile(player)
	if not profile or not getStyle(styleId) or not owns(profile, styleId) then
		return false
	end
	profile.Styles.Equipped = styleId
	masteryEntry(profile, styleId)
	player:SetAttribute("Style", styleId)
	Services.DataService.Replicate(player, "Styles")
	if Services.CombatService then
		Services.CombatService.RefreshStats(player)
	end
	return true
end

-- Remotes ----------------------------------------------------------------------

local function nearSensei(player: Player): boolean
	local root = Util.GetRoot(player)
	return root ~= nil and (root.Position - senseiPosition).Magnitude <= StylesConfig.DojoRange
end

local function onEquip(player: Player, styleId: any): (boolean, string)
	if not limiter:Allow(player) then
		return false, "Slow down."
	end
	local style = getStyle(styleId)
	if not style then
		return false, "Unknown style."
	end
	local profile = Services.DataService.GetProfile(player)
	if not profile then
		return false, "Still loading."
	end
	if not owns(profile, style.Id) then
		return false, "You don't own that style yet."
	end
	if profile.Styles.Equipped == style.Id then
		return true, style.DisplayName .. " is already equipped."
	end
	if not nearSensei(player) then
		return false, "Switch styles with the Sensei at the Dojo."
	end
	if Services.CombatService and Services.CombatService.IsInCombat(player) then
		return false, "You can't switch styles mid-fight."
	end
	if Services.ChallengeService and Services.ChallengeService.IsInDuel(player) then
		return false, "You can't switch styles during a duel."
	end
	StyleService.EquipStyle(player, style.Id)
	return true, style.DisplayName .. " equipped."
end

local function grantAndAnnounce(player: Player, style: StylesConfig.Style)
	StyleService.GrantStyle(player, style.Id)
	Notify.Send(player, string.format("You learned %s!", style.DisplayName), "gold", 4)
end

local function onUnlock(player: Player, styleId: any, method: any): (boolean, string)
	if not limiter:Allow(player) then
		return false, "Slow down."
	end
	local style = getStyle(styleId)
	if not style then
		return false, "Unknown style."
	end
	if method ~= "Scrolls" and method ~= "Robux" then
		return false, "Unknown payment method."
	end
	local profile = Services.DataService.GetProfile(player)
	if not profile then
		return false, "Still loading."
	end
	if owns(profile, style.Id) then
		return false, "You already own " .. style.DisplayName .. "."
	end
	if style.Starter then
		return false, "Starter styles are picked in the tutorial."
	end
	if method == "Scrolls" then
		if profile.Scrolls < style.ScrollCost then
			return false, string.format("Need %d more scrolls.", style.ScrollCost - profile.Scrolls)
		end
		Services.DataService.AddScrolls(player, -style.ScrollCost)
		grantAndAnnounce(player, style)
		return true, style.DisplayName .. " unlocked."
	end
	-- Robux: redeem a stored Style Ticket, otherwise prompt the product and grant when it lands.
	if (profile.StyleTickets or 0) > 0 then
		profile.StyleTickets -= 1
		Services.DataService.Replicate(player, "StyleTickets")
		grantAndAnnounce(player, style)
		return true, style.DisplayName .. " unlocked with a Style Ticket."
	end
	if not Services.MonetizationService then
		return false, "The store is unavailable right now."
	end
	pendingTicket[player] = style.Id
	Services.MonetizationService.PromptProduct(player, "StyleTicket")
	return true, "Complete the purchase to unlock " .. style.DisplayName .. "."
end

-- Grants pending styles once MonetizationService has added the purchased ticket.
local function checkPendingTickets()
	for player, styleId in pendingTicket do
		local profile = Services.DataService.GetProfile(player)
		if not profile then
			if not Util.IsOnline(player) then
				pendingTicket[player] = nil
			end
		elseif owns(profile, styleId) then
			pendingTicket[player] = nil
		elseif (profile.StyleTickets or 0) > 0 then
			pendingTicket[player] = nil
			profile.StyleTickets -= 1
			Services.DataService.Replicate(player, "StyleTickets")
			local style = getStyle(styleId)
			if style then
				grantAndAnnounce(player, style)
			end
		end
	end
end

-- Lifecycle --------------------------------------------------------------------

function StyleService.Init(services: any)
	Services = services
	Net.Function("Style_Equip").OnServerInvoke = onEquip
	Net.Function("Style_Unlock").OnServerInvoke = onUnlock
end

function StyleService.Start()
	Services.InteractionService.Register("Dojo", function(player: Player)
		Net.Event("UI_Open"):FireClient(player, "Style", { AtDojo = true })
		Util.Quest(Services, player, "VisitDojo", 1)
	end)
	Players.PlayerRemoving:Connect(function(player)
		pendingTicket[player] = nil
		limiter:Remove(player)
	end)
	while true do
		task.wait(TICKET_POLL)
		if next(pendingTicket) ~= nil then
			checkPendingTickets()
		end
	end
end

return StyleService
