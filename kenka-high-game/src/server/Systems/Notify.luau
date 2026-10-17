--!strict
-- Toast messages to players. Kind controls the color on the client:
--   "info" (default), "good" (green), "bad" (red), "zone" (zone color), "gold" (rewards), "crew" (sakura)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Util.Net)

local notifyEvent = Net.Event("Notify")

local Notify = {}

function Notify.Send(player: Player, text: string, kind: string?, duration: number?)
	notifyEvent:FireClient(player, { Text = text, Kind = kind or "info", Duration = duration })
end

function Notify.All(text: string, kind: string?, duration: number?)
	notifyEvent:FireAllClients({ Text = text, Kind = kind or "info", Duration = duration })
end

function Notify.Many(players: { Player }, text: string, kind: string?, duration: number?)
	for _, player in players do
		if player.Parent == Players then
			Notify.Send(player, text, kind, duration)
		end
	end
end

return Notify
