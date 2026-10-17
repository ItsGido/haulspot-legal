--!strict
-- Client side of crews: caches the latest Crew_Update summary and shows crew invite popups.
--   CrewController.GetSummary() -> summary? (nil = no crew)
--   CrewController.Changed:Connect(function(summary?) ... end)
--   CrewController.Action(action, args?) -> ok, resultOrMessage   (wraps the Crew_Action remote)
--   CrewController.GetTurfState() -> latest Turf_Update payload?  · CrewController.TurfChanged (Signal)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage.Shared.Config.UITheme)
local Net = require(ReplicatedStorage.Shared.Util.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Kit = require(script.Parent.Parent.UI.Kit)

local CrewController = {}
CrewController.Priority = 40

CrewController.Changed = Signal.new() -- (summary?)
CrewController.TurfChanged = Signal.new() -- (turfState)

local POPUP_SECONDS = 30

type InviteData = { CrewId: string, CrewName: string, FromName: string, Color: string?, Emblem: string?, Expires: number }

local Controllers: any
local summary: any? = nil
local turfState: any? = nil
local queue: { InviteData } = {}
local showing = false
local popupGui: ScreenGui? = nil

local function notify(text: string, kind: string)
	local toast = Controllers and Controllers.ToastController
	if toast and toast.Show then
		toast.Show(text, kind)
	end
end

function CrewController.GetSummary(): any?
	return summary
end

function CrewController.GetTurfState(): any?
	return turfState
end

function CrewController.Action(action: string, args: any?): (boolean, any)
	local ok, success, result = pcall(function()
		return Net.Function("Crew_Action"):InvokeServer(action, args)
	end)
	if not ok then
		return false, "Connection problem. Try again."
	end
	return success == true, result
end

local function getPopupGui(): ScreenGui
	local existing = popupGui
	if existing and existing.Parent then
		return existing
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "CrewInvite"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 30
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	popupGui = gui
	return gui
end

local showNext: () -> ()

local function showInvite(invite: InviteData)
	showing = true
	local gui = getPopupGui()
	local panel = Kit.Panel("InvitePanel", gui, UDim2.fromScale(0.5, 0.2), UDim2.fromScale(0.36, 0.2), Vector2.new(0.5, 0))
	Kit.Aspect(panel, 2.6)
	local stroke = panel:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Color3.fromHex(UITheme.Sakura)
	end
	local emblem = Kit.Label("Emblem", panel, invite.Emblem or "", UDim2.fromScale(0.04, 0.08), UDim2.fromScale(0.16, 0.44), "BodyBold", invite.Color or UITheme.Sakura, 64)
	Kit.TextStroke(emblem, 2)
	Kit.Label("Title", panel, "CREW INVITE", UDim2.fromScale(0.22, 0.06), UDim2.fromScale(0.74, 0.2), "Title", UITheme.Sakura, 36, Enum.TextXAlignment.Left)
	Kit.Label(
		"Text",
		panel,
		string.format("<b>%s</b> invited you to join <b>%s</b>", invite.FromName, invite.CrewName),
		UDim2.fromScale(0.22, 0.27),
		UDim2.fromScale(0.74, 0.26),
		"Body",
		UITheme.Paper,
		22,
		Enum.TextXAlignment.Left
	)
	local bar = Kit.Bar("Timer", panel, UDim2.fromScale(0.04, 0.58), UDim2.fromScale(0.92, 0.06), UITheme.Ink, UITheme.Sakura, 1)
	local accept = Kit.Button(panel, "ACCEPT", "Success", UDim2.fromScale(0.04, 0.7), UDim2.fromScale(0.44, 0.24))
	local decline = Kit.Button(panel, "DECLINE", "Ghost", UDim2.fromScale(0.52, 0.7), UDim2.fromScale(0.44, 0.24))

	local done = false
	local function finish(answer: boolean?)
		if done then
			return
		end
		done = true
		panel:Destroy()
		if answer ~= nil then
			task.spawn(function()
				local ok, message = CrewController.Action("RespondInvite", { CrewId = invite.CrewId, Accept = answer })
				if type(message) == "string" then
					notify(message, if ok then "crew" else "bad")
				end
			end)
		end
		showing = false
		showNext()
	end
	accept.Activated:Connect(function()
		finish(true)
	end)
	decline.Activated:Connect(function()
		finish(false)
	end)
	task.spawn(function()
		while not done do
			local remaining = invite.Expires - os.clock()
			if remaining <= 0 then
				finish(nil)
				break
			end
			Kit.SetBar(bar, remaining / POPUP_SECONDS)
			task.wait(0.1)
		end
	end)
end

function showNext()
	if showing then
		return
	end
	while #queue > 0 do
		local invite = table.remove(queue, 1) :: InviteData
		if invite.Expires > os.clock() and summary == nil then
			showInvite(invite)
			return
		end
	end
end

function CrewController.Init(controllers: any)
	Controllers = controllers
	Net.Event("Crew_Update").OnClientEvent:Connect(function(data: any)
		summary = if type(data) == "table" then data else nil
		CrewController.Changed:Fire(summary)
	end)
	Net.Event("Crew_Invite").OnClientEvent:Connect(function(data: any)
		if type(data) ~= "table" or type(data.CrewId) ~= "string" then
			return
		end
		local timeout = if type(data.ExpiresIn) == "number" then math.min(data.ExpiresIn, POPUP_SECONDS) else POPUP_SECONDS
		for _, queued in queue do
			if queued.CrewId == data.CrewId then
				return
			end
		end
		table.insert(queue, {
			CrewId = data.CrewId,
			CrewName = tostring(data.CrewName or "a crew"),
			FromName = tostring(data.FromName or "Someone"),
			Color = if type(data.Color) == "string" then data.Color else nil,
			Emblem = if type(data.Emblem) == "string" then data.Emblem else nil,
			Expires = os.clock() + timeout,
		})
		showNext()
	end)
	Net.Event("Turf_Update").OnClientEvent:Connect(function(data: any)
		if type(data) == "table" then
			turfState = data
			CrewController.TurfChanged:Fire(data)
		end
	end)
end

function CrewController.Start()
	local ok, result = CrewController.Action("Info")
	if ok and summary == nil and type(result) == "table" then
		summary = result
		CrewController.Changed:Fire(summary)
	end
end

return CrewController
