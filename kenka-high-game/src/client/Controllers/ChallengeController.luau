--!strict
-- Client side of challenge duels.
--   * Hides the server-made "ChallengePrompt" on the local player's own character.
--   * Disables every challenge prompt while the local player (or the prompt's owner) is in a duel or tournament.
--   * ChallengeController.ChallengePlayer(targetPlayer) fires Challenge_Send (the player list uses it).
--   * ChallengeController.GetDuel() -> the last "Started" Challenge_Update payload while a duel is on, or nil.
--   * ChallengeController.DuelChanged (Signal: payload?) fires when a duel starts or ends.
-- The challenge popup itself lives in PopupController (UI workstream).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local ChallengeController = {}

ChallengeController.DuelChanged = Signal.new() -- (payload?)

local PROMPT_NAME = "ChallengePrompt"
local OWNER_RETRY = 0.5 -- seconds
local REFRESH_INTERVAL = 0.5 -- re-check downed state and zones
local SEND_COOLDOWN = 1 -- seconds between list challenges (the server also rate-limits)

local localPlayer = Players.LocalPlayer
local prompts: { [ProximityPrompt]: boolean } = {}
local currentDuel: any = nil
local lastSend = 0

local function ownerOf(prompt: ProximityPrompt): Player?
	local root = prompt.Parent
	local character = root and root.Parent
	if character and character:IsA("Model") then
		return Players:GetPlayerFromCharacter(character)
	end
	return nil
end

local function busy(player: Player?): boolean
	if not player then
		return false
	end
	return player:GetAttribute("InDuel") == true or player:GetAttribute("InTournament") == true
end

local function downed(player: Player): boolean
	local character = player.Character
	return character ~= nil and character:GetAttribute("Downed") == true
end

-- Hidden when it can't succeed, so it never steals the E key from Help Up or shop/job prompts:
-- on your own character, during duels/tournaments, on downed players, and while you stand in a Green zone.
local function refresh(prompt: ProximityPrompt)
	local owner = ownerOf(prompt)
	local enabled = owner ~= nil
		and owner ~= localPlayer
		and not busy(localPlayer)
		and not busy(owner)
		and not downed(owner)
		and localPlayer:GetAttribute("ZoneType") ~= "Green"
	if prompt.Enabled ~= enabled then
		prompt.Enabled = enabled
	end
end

local function refreshAll()
	for prompt in prompts do
		if prompt.Parent then
			refresh(prompt)
		else
			prompts[prompt] = nil
		end
	end
end

local function track(instance: Instance)
	if not instance:IsA("ProximityPrompt") or instance.Name ~= PROMPT_NAME then
		return
	end
	local prompt = instance :: ProximityPrompt
	if prompts[prompt] then
		return
	end
	prompts[prompt] = true
	refresh(prompt)
	-- The server may re-replicate Enabled; keep our local override.
	prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
		refresh(prompt)
	end)
	prompt.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			prompts[prompt] = nil
		end
	end)
end

local function watchPlayer(player: Player)
	player:GetAttributeChangedSignal("InDuel"):Connect(refreshAll)
	player:GetAttributeChangedSignal("InTournament"):Connect(refreshAll)
	-- A prompt can replicate before player.Character points at its model; re-check once it does.
	player.CharacterAdded:Connect(function()
		task.delay(OWNER_RETRY, refreshAll)
	end)
end

function ChallengeController.ChallengePlayer(targetPlayer: Player)
	if typeof(targetPlayer) ~= "Instance" or not targetPlayer:IsA("Player") or targetPlayer == localPlayer then
		return
	end
	if os.clock() - lastSend < SEND_COOLDOWN then
		return
	end
	lastSend = os.clock()
	Net.Event("Challenge_Send"):FireServer(targetPlayer)
end

function ChallengeController.GetDuel(): any
	return currentDuel
end

function ChallengeController.Init(_controllers: any)
	Net.Event("Challenge_Update").OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if payload.State == "Started" then
			currentDuel = payload
			ChallengeController.DuelChanged:Fire(payload)
		elseif payload.State == "Ended" and currentDuel then
			currentDuel = nil
			ChallengeController.DuelChanged:Fire(nil)
		end
	end)
end

function ChallengeController.Start()
	for _, descendant in workspace:GetDescendants() do
		track(descendant)
	end
	workspace.DescendantAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	-- Character swaps re-create prompts; DescendantAdded catches them, this catches ownership timing.
	localPlayer.CharacterAdded:Connect(function()
		task.defer(refreshAll)
	end)
	localPlayer:GetAttributeChangedSignal("ZoneType"):Connect(refreshAll)
	while true do
		task.wait(REFRESH_INTERVAL)
		refreshAll()
	end
end

return ChallengeController
