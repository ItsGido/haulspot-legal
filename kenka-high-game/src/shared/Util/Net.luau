--!strict
-- Every remote in the game is declared here, so a typo fails loudly instead of silently.
-- The server creates ReplicatedStorage.Remotes; the client waits for it.
-- Payload shapes are documented in docs/ARCHITECTURE.md ("Remotes").

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	-- Data and UI
	"Data_Update", -- S->C  partial profile: { [topLevelKey] = value }
	"Notify", -- S->C  { Text, Kind, Duration? }
	"UI_Open", -- S->C  screenName, data?
	"Settings_Save", -- C->S  settings table
	"Unstuck", -- C->S
	-- Combat
	"Combat_Request", -- C->S  action, data?
	"Combat_FX", -- S->All { Kind, Attacker, Target?, Action?, Damage?, Position?, ... }
	"Combat_Cooldown", -- S->C  action, duration
	"KO_Screen", -- S->C  { KillerName, Stamp, RespawnIn }
	-- Progression
	"RankUp", -- S->C  { Rank, Title, Scrolls, Yen }
	"Challenge_Send", -- C->S  targetPlayer
	"Challenge_Incoming", -- S->C  { From, FromRank, FromTitle, Wager, ExpiresAt }
	"Challenge_Respond", -- C->S  fromPlayer, accept
	"Challenge_Update", -- S->C  { State, Opponent?, Center?, Radius?, Winner?, Wager? }
	"Tourney_Update", -- S->All { State, Players, Bracket, Match?, Message? }
	"Tutorial_Update", -- S->C  { Step, Text, Done? }
	"Tutorial_Skip", -- C->S
	-- Economy
	"Job_Update", -- S->C  { JobId, State, Data? }
	"Job_Submit", -- C->S  jobId, data
	"Job_Cancel", -- C->S
	"Vehicle_Toggle", -- C->S  vehicleId? (nil = dismount)
	"LoginReward", -- S->C  { Day, Reward }
	-- Social
	"Crew_Update", -- S->C  crewSummary or nil
	"Crew_Invite", -- S->C  { CrewId, CrewName, FromName }
	"Turf_Update", -- S->All { [turfId] = turfState }
}

local FUNCTIONS = {
	"Style_Equip", -- (styleId) -> ok, message
	"Style_Unlock", -- (styleId, method "Scrolls"|"Robux") -> ok, message
	"Tutorial_PickStyle", -- (styleId) -> ok
	"Quest_Claim", -- (questId) -> ok, message
	"Quest_Reroll", -- (questId) -> ok, message
	"Class_Submit", -- (answers {number}) -> ok, result
	"Shop_Buy", -- (shopId, itemId) -> ok, message
	"Shop_EquipUniform", -- (itemId) -> ok, message
	"Capsule_Roll", -- (count, currency "Yen"|"Token") -> ok, results|message
	"Capsule_Equip", -- (slot, itemId?) -> ok, message
	"Capsule_BuyWithPoints", -- (itemId) -> ok, message
	"Creator_Save", -- (changes) -> ok, message
	"Crew_Action", -- (action, args) -> ok, resultOrMessage
	"YenPay_Send", -- (targetUserId, amount) -> ok, message
	"Data_Request", -- () -> full public profile (client calls once on start)
}

local Net = {}

local folder: Folder
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing then
		folder = existing :: Folder
	else
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	for _, name in EVENTS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	for _, name in FUNCTIONS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

local eventSet, functionSet = {}, {}
for _, name in EVENTS do
	eventSet[name] = true
end
for _, name in FUNCTIONS do
	functionSet[name] = true
end

function Net.Event(name: string): RemoteEvent
	assert(eventSet[name], "Unknown RemoteEvent: " .. name)
	return folder:WaitForChild(name) :: RemoteEvent
end

function Net.Function(name: string): RemoteFunction
	assert(functionSet[name], "Unknown RemoteFunction: " .. name)
	return folder:WaitForChild(name) :: RemoteFunction
end

return Net
