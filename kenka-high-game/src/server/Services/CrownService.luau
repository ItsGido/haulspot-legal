--!strict
-- The server Banchō crown (blueprint section 1.9, Config.Game.Crown).
--   Unclaimed at server start. Win Crown.StreakToClaim normal duels in a row against Rank >= MinOpponentRank
--   to claim it. Beating the holder in a duel takes it. The holder must accept duels from Rank
--   ForcedChallengeMinRank+ (with Crown.DuelCooldown between crown duels). Leaving drops it.
-- Public API: CrownService.IsCrownHolder(player) · CrownService.GetHolder() · CrownService.MustAccept(target, challenger)
-- ReplicatedStorage attributes CrownHolderId / CrownHolderName, player attribute Crown.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local Notify = require(script.Parent.Parent.Systems.Notify)
local Util = require(script.Parent.Parent.Systems.ProgressionUtil)

local Config = GameConfig.Crown

local CrownService = {}
CrownService.Priority = 55

local Services: any

local ANNOUNCE_SECONDS = 6

local holder: Player? = nil
local streaks: { [Player]: number } = {}
local lastCrownDuel = -math.huge -- os.clock when the last duel involving the holder ended

local function rankOf(player: Player): number
	if Services.RepService then
		return Services.RepService.GetRank(player)
	end
	local attr = player:GetAttribute("Rank")
	return if type(attr) == "number" then attr else 1
end

local function setHolder(newHolder: Player?, announcement: string?)
	local old = holder
	if old and Util.IsOnline(old) then
		old:SetAttribute("Crown", nil)
	end
	holder = newHolder
	if newHolder then
		newHolder:SetAttribute("Crown", true)
		ReplicatedStorage:SetAttribute("CrownHolderId", newHolder.UserId)
		ReplicatedStorage:SetAttribute("CrownHolderName", newHolder.DisplayName)
		streaks[newHolder] = 0
	else
		ReplicatedStorage:SetAttribute("CrownHolderId", 0)
		ReplicatedStorage:SetAttribute("CrownHolderName", "")
	end
	-- A fresh holder just finished a duel: the crown duel cooldown starts now.
	lastCrownDuel = if newHolder then os.clock() else -math.huge
	if announcement then
		Notify.All(announcement, "gold", ANNOUNCE_SECONDS)
	end
end

local function onDuelEnded(winner: Player?, loser: Player?, info: any)
	if type(info) ~= "table" or info.Kind ~= "Duel" or not winner or not loser then
		return
	end
	local current = holder
	if current and (winner == current or loser == current) then
		lastCrownDuel = os.clock()
	end
	streaks[loser] = 0
	if rankOf(loser) >= Config.MinOpponentRank then
		streaks[winner] = (streaks[winner] or 0) + 1
	end
	if not Util.IsOnline(winner) then
		return
	end
	if current and loser == current then
		setHolder(winner, string.format("👑 %s defeated %s and took the Banchō crown!", winner.DisplayName, loser.DisplayName))
	elseif current == nil and (streaks[winner] or 0) >= Config.StreakToClaim then
		setHolder(winner, string.format("👑 %s won %d duels in a row and claimed the Banchō crown!", winner.DisplayName, Config.StreakToClaim))
	end
end

-- Public API -----------------------------------------------------------------

function CrownService.IsCrownHolder(player: Player): boolean
	return holder ~= nil and holder == player
end

function CrownService.GetHolder(): Player?
	return holder
end

-- Must the target accept this challenger's duel immediately?
function CrownService.MustAccept(target: Player, challenger: Player): boolean
	if holder == nil or target ~= holder or challenger == target then
		return false
	end
	if rankOf(challenger) < Config.ForcedChallengeMinRank then
		return false
	end
	return os.clock() - lastCrownDuel >= Config.DuelCooldown
end

-- Lifecycle --------------------------------------------------------------------

function CrownService.Init(services: any)
	Services = services
	ReplicatedStorage:SetAttribute("CrownHolderId", 0)
	ReplicatedStorage:SetAttribute("CrownHolderName", "")
end

function CrownService.Start()
	if Services.ChallengeService then
		Services.ChallengeService.DuelEnded:Connect(onDuelEnded)
	end
	Players.PlayerRemoving:Connect(function(player)
		streaks[player] = nil
		if holder ~= player then
			return
		end
		-- Leaving mid-duel hands the crown to the opponent (a leaver loses the duel).
		local opponent: Player? = nil
		local kind: string? = nil
		if Services.ChallengeService then
			opponent, kind = Services.ChallengeService.GetOpponent(player)
		end
		if opponent and kind == "Duel" and Util.IsOnline(opponent) then
			setHolder(opponent, string.format("👑 %s left mid-duel. %s takes the Banchō crown!", player.DisplayName, opponent.DisplayName))
		else
			setHolder(nil, string.format("The Banchō %s left. The crown is unclaimed!", player.DisplayName))
		end
	end)
end

return CrownService
