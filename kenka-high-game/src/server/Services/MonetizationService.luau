--!strict
-- Robux game passes and developer products (blueprint section 9).
--
--   MonetizationService.OwnsPass(player, "VIP") -> bool      (cached per player)
--   MonetizationService.GetOwnedPasses(player) -> { VIP = true, ... }
--   MonetizationService.RegisterProduct("StyleTicket", function(player) ... return true end)
--   MonetizationService.PromptProduct(player, "CapsuleToken1")
--   MonetizationService.PromptPass(player, "VIP")
--
-- ProcessReceipt is idempotent (DataService.HasPurchase / RecordPurchase) and saves the profile
-- before returning PurchaseGranted. A product or pass whose Id is 0 is disabled.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Net = require(ReplicatedStorage.Shared.Util.Net)
local Notify = require(script.Parent.Parent.Systems.Notify)

local MonetizationService = {}
MonetizationService.Priority = 15

type Handler = (player: Player) -> boolean

local Services: any
local passCache: { [Player]: { [string]: boolean } } = {}
local handlers: { [string]: Handler } = {}
local productKeyById: { [number]: string } = {}
local passKeyById: { [number]: string } = {}
local dataUpdate = Net.Event("Data_Update")

for key, product in Monetization.DeveloperProducts do
	if product.Id ~= 0 then
		productKeyById[product.Id] = key
	end
end
for key, pass in Monetization.GamePasses do
	if pass.Id ~= 0 then
		passKeyById[pass.Id] = key
	end
end

local function studioGrantAll(): boolean
	return RunService:IsStudio() and Monetization.StudioGrantAllPasses == true
end

-- Public API -----------------------------------------------------------------

function MonetizationService.OwnsPass(player: Player, key: string): boolean
	local pass = Monetization.GamePasses[key]
	if not pass then
		return false
	end
	if studioGrantAll() then
		return true
	end
	if pass.Id == 0 then
		return false
	end
	local cache = passCache[player]
	if cache and cache[key] ~= nil then
		return cache[key]
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id)
	end)
	if not ok then
		warn("[MonetizationService] UserOwnsGamePassAsync failed: " .. tostring(owns))
		return false -- not cached, so the next call retries
	end
	if player.Parent == Players then
		local entry = passCache[player]
		if not entry then
			local created = {}
			passCache[player] = created
			entry = created
		end
		(entry :: { [string]: boolean })[key] = owns == true
	end
	return owns == true
end

function MonetizationService.GetOwnedPasses(player: Player): { [string]: boolean }
	local owned = {}
	for key in Monetization.GamePasses do
		if MonetizationService.OwnsPass(player, key) then
			owned[key] = true
		end
	end
	return owned
end

-- Handlers return true when the product was granted. A later registration replaces an earlier one.
function MonetizationService.RegisterProduct(key: string, handler: Handler)
	handlers[key] = handler
end

local function starterPackEligible(player: Player): (boolean, string?)
	local profile = Services.DataService.GetProfile(player)
	if not profile then
		return false, "Your data is still loading."
	end
	local pack = profile.StarterPack
	if pack.Bought then
		return false, "You already own the Starter Pack."
	end
	if os.time() - pack.FirstJoin > Monetization.StarterPackWindowHours * 3600 then
		return false, "The Starter Pack offer has expired."
	end
	return true, nil
end

function MonetizationService.PromptProduct(player: Player, key: string)
	local product = Monetization.DeveloperProducts[key]
	if not product or product.Id == 0 then
		Notify.Send(player, "This item isn't on sale yet. Coming soon!", "info")
		return
	end
	if key == "StarterPack" then
		local ok, message = starterPackEligible(player)
		if not ok then
			Notify.Send(player, message or "Not available.", "bad")
			return
		end
	end
	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, product.Id)
	end)
	if not ok then
		warn("[MonetizationService] PromptProductPurchase failed: " .. tostring(err))
	end
end

function MonetizationService.PromptPass(player: Player, key: string)
	local pass = Monetization.GamePasses[key]
	if not pass or pass.Id == 0 then
		Notify.Send(player, "This pass isn't on sale yet. Coming soon!", "info")
		return
	end
	if MonetizationService.OwnsPass(player, key) then
		Notify.Send(player, "You already own " .. pass.Name .. ".", "info")
		return
	end
	local ok, err = pcall(function()
		MarketplaceService:PromptGamePassPurchase(player, pass.Id)
	end)
	if not ok then
		warn("[MonetizationService] PromptGamePassPurchase failed: " .. tostring(err))
	end
end

local function pushDerived(player: Player)
	if player.Parent ~= Players then
		return
	end
	dataUpdate:FireClient(player, {
		Derived = {
			Passes = MonetizationService.GetOwnedPasses(player),
			Memory = Services.DataService.IsMemoryProfile(player),
		},
	})
end

-- Receipts -------------------------------------------------------------------

local RECEIPT_PROFILE_WAIT = 20 -- seconds to wait for a joining player's profile

local function processReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- A pending receipt is often delivered right as the player joins: wait for the profile
	-- (ProcessReceipt may yield) instead of deferring it to their next session.
	local profile = Services.DataService.GetProfile(player)
	local deadline = os.clock() + RECEIPT_PROFILE_WAIT
	while not profile and player.Parent == Players and os.clock() < deadline do
		task.wait(0.5)
		profile = Services.DataService.GetProfile(player)
	end
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local receiptId = tostring(receiptInfo.PurchaseId)
	if Services.DataService.HasPurchase(player, receiptId) then
		-- Already granted earlier; make sure that grant reached the DataStore.
		if Services.DataService.SaveNow(player) then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local key = productKeyById[receiptInfo.ProductId]
	local handler = key and handlers[key]
	if not key or not handler then
		warn("[MonetizationService] No handler for product " .. tostring(receiptInfo.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, granted = pcall(handler, player)
	if not ok then
		warn("[MonetizationService] Handler " .. key .. " errored: " .. tostring(granted))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if granted ~= true then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	Services.DataService.RecordPurchase(player, receiptId)
	if not Services.DataService.SaveNow(player) then
		-- The grant is recorded in the session; Roblox retries and the HasPurchase branch saves again.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	print(string.format("[MonetizationService] Granted %s to %s (receipt %s)", key, player.Name, receiptId))
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Built-in product handlers ----------------------------------------------------

local function addTokens(amount: number): Handler
	return function(player: Player): boolean
		local profile = Services.DataService.GetProfile(player)
		if not profile then
			return false
		end
		profile.Capsule.Tokens += amount
		Services.DataService.Replicate(player, "Capsule")
		Notify.Send(player, string.format("+%d capsule token%s!", amount, if amount == 1 then "" else "s"), "gold")
		return true
	end
end

local function registerBuiltIns()
	MonetizationService.RegisterProduct("CapsuleToken1", addTokens(1))
	MonetizationService.RegisterProduct("CapsuleToken10", addTokens(10))

	MonetizationService.RegisterProduct("StarterPack", function(player: Player): boolean
		local profile = Services.DataService.GetProfile(player)
		if not profile then
			return false
		end
		local pack = Monetization.StarterPack
		if not starterPackEligible(player) then
			-- The window closed (or a second purchase raced the first) between the prompt and the receipt.
			-- Never leave paid Robux ungranted: give the pack's yen value instead.
			profile.Yen += pack.Yen
			Services.DataService.Replicate(player, "Yen")
			Notify.Send(player, string.format("The Starter Pack offer had ended, so you got ¥%d instead.", pack.Yen), "gold", 6)
			return true
		end
		profile.StarterPack.Bought = true
		profile.Yen += pack.Yen -- direct: purchased yen gets no pass bonus and no quest credit
		profile.Scrolls += pack.Scrolls
		profile.Capsule.Tokens += pack.CapsuleTokens
		if pack.Cosmetic then
			profile.Cosmetics.Owned[pack.Cosmetic] = true
		end
		Services.DataService.Replicate(player, "Yen", "Scrolls", "Capsule", "Cosmetics", "StarterPack")
		Notify.Send(player, "Starter Pack unlocked! Welcome to Kenka High.", "gold", 6)
		return true
	end)

	MonetizationService.RegisterProduct("YenPack", function(player: Player): boolean
		local profile = Services.DataService.GetProfile(player)
		if not profile then
			return false
		end
		profile.Yen += Monetization.YenPackAmount
		Services.DataService.Replicate(player, "Yen")
		Notify.Send(player, string.format("+¥%d added!", Monetization.YenPackAmount), "gold")
		return true
	end)

	MonetizationService.RegisterProduct("StyleTicket", function(player: Player): boolean
		local profile = Services.DataService.GetProfile(player)
		if not profile then
			return false
		end
		profile.StyleTickets = (profile.StyleTickets or 0) + 1
		Services.DataService.Replicate(player, "StyleTickets")
		Notify.Send(player, "Style Ticket added! Unlock any style at the Dojo.", "gold")
		return true
	end)

	MonetizationService.RegisterProduct("TermPass", function(player: Player): boolean
		local profile = Services.DataService.GetProfile(player)
		if not profile then
			return false
		end
		profile.Term.PassOwned = true
		Services.DataService.Replicate(player, "Term")
		Notify.Send(player, "Term Pass unlocked!", "gold")
		return true
	end)

	-- NameChange is intentionally not sold yet: it needs a filtered rename remote first (see docs/ARCHITECTURE.md).
end

-- Lifecycle --------------------------------------------------------------------

function MonetizationService.Init(services: any)
	Services = services
	registerBuiltIns()
end

function MonetizationService.Start()
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		if not purchased then
			return
		end
		local key = passKeyById[passId]
		if not key or player.Parent ~= Players then
			return
		end
		local entry = passCache[player]
		if not entry then
			local created = {}
			passCache[player] = created
			entry = created
		end
		(entry :: { [string]: boolean })[key] = true
		local pass = Monetization.GamePasses[key]
		Notify.Send(player, "Thanks! " .. pass.Name .. " is now active.", "gold", 5)
		pushDerived(player)
		if Services.CosmeticsService then
			task.spawn(Services.CosmeticsService.Apply, player)
		end
	end)

	-- Warm the pass cache so the first AddYen doesn't wait on the web call.
	local function warm(player: Player)
		task.spawn(function()
			MonetizationService.GetOwnedPasses(player)
		end)
	end
	Players.PlayerAdded:Connect(warm)
	for _, player in Players:GetPlayers() do
		warm(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		passCache[player] = nil
	end)
end

return MonetizationService
