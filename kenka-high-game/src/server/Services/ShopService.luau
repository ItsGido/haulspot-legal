--!strict
-- Shotengai shops, food buffs, the courtyard fountain, the sento and YenPay gifting
-- (blueprint sections 3 Z11, 6.4 and 6.5).
--
--   ShopService.GetBuffValue(player, "MaxHP") -> number   (sum of active buffs with that Stat, 0 if none)
--   ShopService.ApplyBuff(player, { Stat, Amount, Duration, Group })   (replaces the same Group)
--   ShopService.ClearBuffs(player)
--
-- Player attributes: Buff_<Group> = server time (workspace:GetServerTimeNow()) when the buff expires.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local DayCycleMath = require(ReplicatedStorage.Shared.Logic.DayCycleMath)
local Net = require(ReplicatedStorage.Shared.Util.Net)
local RateLimiter = require(ReplicatedStorage.Shared.Util.RateLimiter)
local Notify = require(script.Parent.Parent.Systems.Notify)
local EconomyUtil = require(script.Parent.Parent.Systems.EconomyUtil)

local ShopService = {}
ShopService.Priority = 40

type Buff = { Stat: string, Amount: number, Duration: number, Group: string }
type ActiveBuff = { Stat: string, Amount: number, Expires: number, Group: string }

local Services: any

local SHOP_RANGE = 20 -- studs from the shop's interactable to buy
local MAX_ID_LENGTH = 40
local YENPAY_MAX_USERID = 2 ^ 53

local FORTUNES = {
	"Great blessing! Today's fights go your way.",
	"Small blessing. Eat a good lunch.",
	"Blessing. A new friend is close by.",
	"Uncertain luck. Keep your guard up.",
	"Future blessing. Patience pays off.",
	"Curse! ...Just kidding. Go win something.",
}

local buffs: { [Player]: { [string]: ActiveBuff } } = {}
local fountainCooldown: { [Player]: number } = {}
local buyLimiter = RateLimiter.new(6, 2)
local payLimiter = RateLimiter.new(3, 5)
local uiOpen = Net.Event("UI_Open")

-- Helpers ------------------------------------------------------------------------

local function isMorning(): boolean
	return Services.DayCycleService ~= nil and Services.DayCycleService.GetPeriod().Id == "Morning"
end

-- The price the server charges right now (Morning food discount).
local function priceOf(item: Economy.ShopItem): number
	if item.Category == "Food" and isMorning() then
		return math.floor(item.Price * (1 - Economy.MorningFoodDiscount) + 0.5)
	end
	return item.Price
end

local function shopInteractableId(shopId: string): string?
	for _, entry in MapData.Interactables do
		if entry.Kind == "Shop" and entry.Shop == shopId then
			return entry.Id
		end
	end
	return nil
end

local function refreshStats(player: Player)
	if Services.CombatService then
		Services.CombatService.RefreshStats(player)
	end
end

local function removeBuff(player: Player, group: string)
	local list = buffs[player]
	if list and list[group] then
		list[group] = nil
		player:SetAttribute("Buff_" .. group, nil)
	end
end

-- Public API -----------------------------------------------------------------------

function ShopService.ApplyBuff(player: Player, buff: Buff)
	if player.Parent ~= Players then
		return
	end
	local list = buffs[player]
	if not list then
		local created = {}
		buffs[player] = created
		list = created
	end
	local expires = EconomyUtil.ServerNow() + buff.Duration
	local entry: ActiveBuff = { Stat = buff.Stat, Amount = buff.Amount, Expires = expires, Group = buff.Group };
	(list :: { [string]: ActiveBuff })[buff.Group] = entry
	player:SetAttribute("Buff_" .. buff.Group, expires)
	refreshStats(player)
	task.delay(buff.Duration, function()
		local current = buffs[player]
		if current and current[buff.Group] == entry then
			removeBuff(player, buff.Group)
			refreshStats(player)
		end
	end)
end

function ShopService.GetBuffValue(player: Player, stat: string): number
	local list = buffs[player]
	if not list then
		return 0
	end
	local now = EconomyUtil.ServerNow()
	local total = 0
	for _, entry in list do
		if entry.Stat == stat and entry.Expires > now then
			total += entry.Amount
		end
	end
	return total
end

function ShopService.ClearBuffs(player: Player)
	local list = buffs[player]
	if not list then
		return
	end
	for group in list do
		player:SetAttribute("Buff_" .. group, nil)
	end
	buffs[player] = nil
	refreshStats(player)
end

-- Remotes -----------------------------------------------------------------------------

local function onBuy(player: Player, shopId: any, itemId: any): (boolean, string)
	if not buyLimiter:Allow(player) then
		return false, "Slow down."
	end
	if not EconomyUtil.IsShortString(shopId, MAX_ID_LENGTH) or not EconomyUtil.IsShortString(itemId, MAX_ID_LENGTH) then
		return false, "Invalid item."
	end
	local item = Economy.Items[itemId]
	if not item or item.Shop ~= shopId then
		return false, "This shop doesn't sell that."
	end
	local profile = Services.DataService.GetProfile(player)
	if not profile then
		return false, "Your data is still loading."
	end
	local interactableId = shopInteractableId(shopId)
	local position = interactableId and EconomyUtil.InteractablePosition(interactableId)
	local root = EconomyUtil.GetRoot(player)
	if not position or not root or (root.Position - position).Magnitude > SHOP_RANGE then
		return false, "You're too far from the shop."
	end
	if EconomyUtil.IsDowned(Services, player) then
		return false, "You can't shop right now."
	end
	local minRank = item.MinRank or 1
	if (profile.Rank or 1) < minRank then
		return false, "Requires Rank " .. minRank .. "."
	end

	-- Category checks before taking any yen.
	if item.Category == "Medical" then
		if EconomyUtil.InCombat(Services, player) then
			return false, "Bandages only work out of combat."
		end
		local humanoid = EconomyUtil.GetHumanoid(player)
		if not humanoid or humanoid.Health <= 0 then
			return false, "You can't use that now."
		end
	elseif item.Category == "Vehicle" then
		if not item.Vehicle or not (Economy.Vehicles :: any)[item.Vehicle] then
			return false, "That vehicle isn't available."
		end
		if profile.Vehicles[item.Vehicle] then
			return false, "You already own a " .. item.Name .. "."
		end
	elseif item.Category == "Uniform" then
		if profile.OwnedUniforms[item.Id] then
			return false, "You already own that. Equip it instead."
		end
	elseif item.Category == "Food" then
		if not item.Buff then
			return false, "That item is unavailable."
		end
	else
		return false, "That item is unavailable."
	end

	local price = priceOf(item)
	if not Services.DataService.SpendYen(player, price) then
		return false, "Not enough yen (" .. Format.Yen(price) .. ")."
	end

	if item.Category == "Food" then
		ShopService.ApplyBuff(player, item.Buff :: Buff)
		if Services.QuestService then
			Services.QuestService.Progress(player, "BuyFood", 1)
		end
		return true, item.Name .. ": " .. item.Description
	elseif item.Category == "Medical" then
		local healed = Services.CombatService ~= nil and Services.CombatService.Heal(player, item.Heal or 0) == true
		if not healed then
			-- Refund directly (not AddYen: refunds are not earnings).
			Services.DataService.Update(player, { "Yen" }, function(p: any)
				p.Yen += price
			end)
			return false, "Couldn't heal right now. Refunded."
		end
		return true, "Patched up (+" .. tostring(item.Heal or 0) .. " HP)."
	elseif item.Category == "Vehicle" then
		Services.DataService.Update(player, { "Vehicles" }, function(p: any)
			p.Vehicles[item.Vehicle :: string] = true
		end)
		return true, "You bought a " .. item.Name .. "! Press B to ride."
	else -- Uniform
		Services.DataService.Update(player, { "OwnedUniforms" }, function(p: any)
			p.OwnedUniforms[item.Id] = true
		end)
		return true, "Bought " .. item.Name .. ". Equip it from this shop."
	end
end

local function onEquipUniform(player: Player, itemId: any): (boolean, string)
	if not buyLimiter:Allow(player) then
		return false, "Slow down."
	end
	if not EconomyUtil.IsShortString(itemId, MAX_ID_LENGTH) then
		return false, "Invalid uniform."
	end
	local item = Economy.Items[itemId]
	if not item or item.Category ~= "Uniform" then
		return false, "That's not a uniform."
	end
	local profile = Services.DataService.GetProfile(player)
	if not profile then
		return false, "Your data is still loading."
	end
	if not profile.OwnedUniforms[itemId] then
		return false, "You don't own that uniform."
	end
	if profile.Uniform == itemId then
		return true, "Already wearing it."
	end
	Services.DataService.Update(player, { "Uniform" }, function(p: any)
		p.Uniform = itemId
	end)
	if Services.CosmeticsService then
		task.spawn(Services.CosmeticsService.Apply, player)
	end
	return true, "Now wearing: " .. item.Name
end

local function onYenPay(player: Player, targetUserId: any, amount: any): (boolean, string)
	if not payLimiter:Allow(player) then
		return false, "Slow down."
	end
	if not EconomyUtil.IsInt(targetUserId, 1, YENPAY_MAX_USERID) or not EconomyUtil.IsInt(amount, 1, Economy.YenPayDailyLimit) then
		return false, "Invalid payment."
	end
	if targetUserId == player.UserId then
		return false, "You can't pay yourself."
	end
	local profile = Services.DataService.GetProfile(player)
	if not profile then
		return false, "Your data is still loading."
	end
	if (profile.Rank or 1) < Economy.YenPayMinRank then
		return false, "YenPay unlocks at Rank " .. Economy.YenPayMinRank .. "."
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	local targetProfile = target and Services.DataService.GetProfile(target)
	if not target or not targetProfile then
		return false, "That player isn't in this server."
	end
	local today = DayCycleMath.UtcDay(os.time())
	if profile.YenPay.Day ~= today then
		profile.YenPay.Day = today
		profile.YenPay.Sent = 0
	end
	local remaining = Economy.YenPayDailyLimit - profile.YenPay.Sent
	if remaining <= 0 then
		return false, "You've hit today's YenPay limit."
	end
	if amount > remaining then
		return false, "You can send " .. Format.Yen(remaining) .. " more today."
	end
	if not Services.DataService.SpendYen(player, amount) then
		return false, "Not enough yen."
	end
	profile.YenPay.Sent += amount
	Services.DataService.Replicate(player, "YenPay")
	-- Direct add: gifts are not "earned" yen (no pass bonus, no EarnYen quest credit, no alt farming).
	Services.DataService.Update(target, { "Yen" }, function(p: any)
		p.Yen += amount
	end)
	Notify.Send(player, "Sent " .. Format.Yen(amount) .. " to " .. target.DisplayName .. ".", "good")
	Notify.Send(target, player.DisplayName .. " sent you " .. Format.Yen(amount) .. " via YenPay!", "gold")
	print(string.format("[YenPay] %s (%d) -> %s (%d): %d yen (sent today %d)", player.Name, player.UserId, target.Name, target.UserId, amount, profile.YenPay.Sent))
	return true, "Sent!"
end

-- Interactables ------------------------------------------------------------------------

local function sparkle(part: BasePart)
	local emitter = part:FindFirstChild("EconomySparkle")
	if not emitter then
		local created = Instance.new("ParticleEmitter")
		created.Name = "EconomySparkle"
		created.Enabled = false
		created.Color = ColorSequence.new(Color3.fromHex("#FFE066"), Color3.fromHex("#FFFFFF"))
		created.LightEmission = 1
		created.Lifetime = NumberRange.new(0.6, 1.2)
		created.Speed = NumberRange.new(4, 9)
		created.SpreadAngle = Vector2.new(40, 40)
		created.Acceleration = Vector3.new(0, -12, 0)
		created.Size = NumberSequence.new(0.35, 0)
		created.EmissionDirection = Enum.NormalId.Top
		created.Parent = part
		emitter = created
	end
	if emitter and emitter:IsA("ParticleEmitter") then
		emitter:Emit(24)
	end
end

local function onFountain(player: Player, _interactable: any, part: BasePart)
	local now = os.clock()
	local readyAt = fountainCooldown[player] or 0
	if now < readyAt then
		Notify.Send(player, string.format("The fountain needs a moment (%ds).", math.ceil(readyAt - now)), "info")
		return
	end
	if not Services.DataService.SpendYen(player, Economy.FountainCoinCost) then
		Notify.Send(player, "You need " .. Format.Yen(Economy.FountainCoinCost) .. " to toss a coin.", "bad")
		return
	end
	fountainCooldown[player] = now + Economy.FountainCooldown
	sparkle(part)
	Notify.Send(player, "🪙 " .. FORTUNES[math.random(1, #FORTUNES)], "gold", 5)
end

local function onBathhouse(player: Player)
	ShopService.ApplyBuff(player, Economy.BathhouseBuff :: Buff)
	Notify.Send(player, string.format("♨ Refreshed! Posture regen +%d%% for %d min.", math.floor(Economy.BathhouseBuff.Amount * 100 + 0.5), Economy.BathhouseBuff.Duration // 60), "good", 5)
end

-- Lifecycle -----------------------------------------------------------------------------

function ShopService.Init(services: any)
	Services = services
	Net.Function("Shop_Buy").OnServerInvoke = onBuy
	Net.Function("Shop_EquipUniform").OnServerInvoke = onEquipUniform
	Net.Function("YenPay_Send").OnServerInvoke = onYenPay
	Services.InteractionService.Register("Shop", function(player: Player, interactable: any)
		uiOpen:FireClient(player, "Shop", { ShopId = interactable.Shop, Name = interactable.Object })
	end)
	Services.InteractionService.Register("Fountain", onFountain)
	Services.InteractionService.Register("Bathhouse", onBathhouse)
end

function ShopService.Start()
	Players.PlayerRemoving:Connect(function(player)
		buffs[player] = nil
		fountainCooldown[player] = nil
		buyLimiter:Remove(player)
		payLimiter:Remove(player)
	end)
	-- Buffs last through respawns (they are timed meals), but re-apply stats on the new character.
	local function hook(player: Player)
		player.CharacterAdded:Connect(function()
			if buffs[player] and next(buffs[player]) ~= nil then
				task.defer(refreshStats, player)
			end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end
end

return ShopService
