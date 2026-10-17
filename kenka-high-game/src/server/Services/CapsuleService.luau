--!strict
-- Capsule Corner: cosmetic gacha with visible odds and saved pity (blueprint sections 5.9 and 6.7).
-- Yen rolls are single only; Token rolls (Robux capsule tokens, login rewards) can be x1 or x10.
-- Duplicates convert to Capsule Points, which buy any non-Mythic cosmetic.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Capsules = require(ReplicatedStorage.Shared.Config.Capsules)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local CapsuleRoll = require(ReplicatedStorage.Shared.Logic.CapsuleRoll)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Net = require(ReplicatedStorage.Shared.Util.Net)
local RateLimiter = require(ReplicatedStorage.Shared.Util.RateLimiter)
local Notify = require(script.Parent.Parent.Systems.Notify)
local EconomyUtil = require(script.Parent.Parent.Systems.EconomyUtil)

local CapsuleService = {}
CapsuleService.Priority = 45

local Services: any

local VALID_SLOTS = { Aura = true, Title = true, Armband = true, KOStamp = true, Trail = true }
local ANNOUNCE_RARITY = "Mythic" -- server-wide shout-out for this rarity

local rollLimiter = RateLimiter.new(3, 2)
local equipLimiter = RateLimiter.new(8, 2)
local busy: { [Player]: boolean } = {}
local uiOpen = Net.Event("UI_Open")

local rarityPoints: { [string]: number } = {}
for _, rarity in Capsules.Rarities do
	rarityPoints[rarity.Id] = rarity.Points
end

local function applyCosmetics(player: Player)
	if Services.CosmeticsService then
		task.spawn(Services.CosmeticsService.Apply, player)
	end
end

local function doRolls(profile: any, count: number): { any }
	local capsule = profile.Capsule
	local owned = profile.Cosmetics.Owned
	local results = {}
	for _ = 1, count do
		local pity: CapsuleRoll.PityState = { PityEpic = capsule.PityEpic, PityLegendary = capsule.PityLegendary }
		local roll = CapsuleRoll.Roll(Capsules, pity, math.random)
		capsule.PityEpic = roll.PityEpic
		capsule.PityLegendary = roll.PityLegendary
		local duplicate = owned[roll.ItemId] == true
		local points = 0
		if duplicate then
			points = rarityPoints[roll.Rarity] or 0
			capsule.Points += points
		else
			owned[roll.ItemId] = true
		end
		table.insert(results, { ItemId = roll.ItemId, Rarity = roll.Rarity, Duplicate = duplicate, Points = points })
	end
	return results
end

local function onRoll(player: Player, count: any, currency: any): (boolean, any)
	if not rollLimiter:Allow(player) then
		return false, "Slow down."
	end
	if (count ~= 1 and count ~= 10) or (currency ~= "Yen" and currency ~= "Token") then
		return false, "Invalid roll."
	end
	if currency == "Yen" and count ~= 1 then
		return false, "Yen rolls are one at a time."
	end
	if busy[player] then
		return false, "Still rolling..."
	end
	local profile = Services.DataService.GetProfile(player)
	if not profile then
		return false, "Your data is still loading."
	end
	busy[player] = true
	local ok, success, payload = pcall(function(): (boolean, any)
		if currency == "Yen" then
			if not Services.DataService.SpendYen(player, Economy.CapsuleYenCost) then
				return false, "A capsule costs " .. Format.Yen(Economy.CapsuleYenCost) .. "."
			end
		else
			if profile.Capsule.Tokens < count then
				return false, "Not enough capsule tokens."
			end
			profile.Capsule.Tokens -= count
		end
		local results = doRolls(profile, count)
		Services.DataService.Replicate(player, "Capsule", "Cosmetics")
		for _, entry in results do
			if entry.Rarity == ANNOUNCE_RARITY and not entry.Duplicate then
				local item = Capsules.ById(entry.ItemId)
				Notify.All(string.format("✨ %s pulled a MYTHIC: %s!", player.DisplayName, if item then item.Name else entry.ItemId), "gold", 6)
			end
		end
		return true, results
	end)
	busy[player] = nil
	if not ok then
		warn("[CapsuleService] Roll failed: " .. tostring(success))
		return false, "Something went wrong."
	end
	return success, payload
end

local function onEquip(player: Player, slot: any, itemId: any): (boolean, string)
	if not equipLimiter:Allow(player) then
		return false, "Slow down."
	end
	if type(slot) ~= "string" or not VALID_SLOTS[slot] then
		return false, "Invalid slot."
	end
	local profile = Services.DataService.GetProfile(player)
	if not profile then
		return false, "Your data is still loading."
	end
	if itemId == nil then
		profile.Cosmetics.Equipped[slot] = nil
		Services.DataService.Replicate(player, "Cosmetics")
		applyCosmetics(player)
		return true, "Unequipped."
	end
	if not EconomyUtil.IsShortString(itemId, 40) then
		return false, "Invalid item."
	end
	local item = Capsules.ById(itemId)
	if not item or item.Slot ~= slot then
		return false, "That doesn't go in this slot."
	end
	if not profile.Cosmetics.Owned[itemId] then
		return false, "You don't own that."
	end
	profile.Cosmetics.Equipped[slot] = itemId
	Services.DataService.Replicate(player, "Cosmetics")
	applyCosmetics(player)
	return true, "Equipped " .. item.Name .. "."
end

local function onBuyWithPoints(player: Player, itemId: any): (boolean, string)
	if not equipLimiter:Allow(player) then
		return false, "Slow down."
	end
	if not EconomyUtil.IsShortString(itemId, 40) then
		return false, "Invalid item."
	end
	local item = Capsules.ById(itemId)
	if not item then
		return false, "Unknown item."
	end
	local price = (Capsules.PointShopPrices :: any)[item.Rarity]
	if item.Rarity == "Mythic" or type(price) ~= "number" then
		return false, "Mythic items can only come from capsules."
	end
	local profile = Services.DataService.GetProfile(player)
	if not profile then
		return false, "Your data is still loading."
	end
	if profile.Cosmetics.Owned[itemId] then
		return false, "You already own that."
	end
	if profile.Capsule.Points < price then
		return false, string.format("Needs %d points.", price)
	end
	profile.Capsule.Points -= price
	profile.Cosmetics.Owned[itemId] = true
	Services.DataService.Replicate(player, "Capsule", "Cosmetics")
	return true, "Got " .. item.Name .. "!"
end

function CapsuleService.Init(services: any)
	Services = services
	Net.Function("Capsule_Roll").OnServerInvoke = onRoll
	Net.Function("Capsule_Equip").OnServerInvoke = onEquip
	Net.Function("Capsule_BuyWithPoints").OnServerInvoke = onBuyWithPoints
	Services.InteractionService.Register("Capsule", function(player: Player)
		uiOpen:FireClient(player, "Capsule")
	end)
end

function CapsuleService.Start()
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
		rollLimiter:Remove(player)
		equipLimiter:Remove(player)
	end)
end

return CapsuleService
