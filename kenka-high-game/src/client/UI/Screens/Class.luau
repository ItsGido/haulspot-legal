--!strict
-- Class minigame window (blueprint section 6.4). Opened by the server with
-- { Questions = { { Q, Choices = { 4 } } }, EndsAt }. One question at a time with 4 big answer
-- buttons, then a result card from Class_Submit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UITheme = require(ReplicatedStorage.Shared.Config.UITheme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Net = require(ReplicatedStorage.Shared.Util.Net)
local Kit = require(script.Parent.Parent.Kit)

local Class = {}
Class.Name = "Class"

local ANSWER_STYLES = { "Primary", "Secondary", "Sakura", "Success" }
local CHOICE_LABELS = { "A", "B", "C", "D" }
local NEXT_DELAY = 0.25

local window: Kit.Window? = nil
local progressLabel: TextLabel
local timerLabel: TextLabel
local questionLabel: TextLabel
local quizFrame: Frame
local answerButtons: { TextButton } = {}
local resultFrame: Frame
local resultTitle: TextLabel
local resultScore: TextLabel
local resultRewards: TextLabel

local questions: { any } = {}
local answers: { number } = {}
local index = 1
local endsAt = 0
local submitted = false
local locked = false
local timerConnection: RBXScriptConnection? = nil

local function showResult(title: string, score: string, rewards: string, color: string)
	quizFrame.Visible = false
	resultFrame.Visible = true
	resultTitle.Text = title
	resultTitle.TextColor3 = Kit.Hex(color)
	resultScore.Text = score
	resultRewards.Text = rewards
	local scale = resultFrame:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 0.8
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

local function submit()
	if submitted then
		return
	end
	submitted = true
	local payload = {}
	for i = 1, #questions do
		payload[i] = answers[i] or 0
	end
	showResult("GRADING...", "", "", UITheme.Paper)
	task.spawn(function()
		local ok, success, result = pcall(function()
			return Net.Function("Class_Submit"):InvokeServer(payload)
		end)
		if not ok then
			showResult("OOPS", "Connection problem.", "", UITheme.Buttons.Primary[1])
			return
		end
		if success ~= true or type(result) ~= "table" then
			showResult("NO GRADE", tostring(result or "Couldn't hand in."), "", UITheme.Buttons.Primary[1])
			return
		end
		local score = string.format("%d / %d correct", result.Correct or 0, result.Total or #questions)
		if result.Passed then
			local rewards = string.format("+%s  ·  +%d Rep", Format.Yen(result.Yen or 0), result.Rep or 0)
			showResult("PASSED!", score, rewards, UITheme.Buttons.Success[1])
			Kit.PlaySound("Purchase")
		else
			showResult("FAILED", score, "Study up and try next class.", UITheme.Buttons.Primary[1])
			Kit.PlaySound("Error")
		end
	end)
end

local function showQuestion()
	local question = questions[index]
	if not question then
		submit()
		return
	end
	locked = false
	progressLabel.Text = string.format("QUESTION %d / %d", index, #questions)
	questionLabel.Text = tostring(question.Q or "")
	for i, button in answerButtons do
		local choice = if type(question.Choices) == "table" then question.Choices[i] else nil
		button.Visible = choice ~= nil
		button.Text = CHOICE_LABELS[i] .. ".  " .. tostring(choice or "")
		Kit.SetButtonStyle(button, ANSWER_STYLES[i])
	end
end

local function choose(choice: number)
	if locked or submitted then
		return
	end
	locked = true
	answers[index] = choice
	for i, button in answerButtons do
		if i ~= choice then
			Kit.SetButtonStyle(button, "Disabled")
		end
	end
	task.delay(NEXT_DELAY, function()
		if submitted then
			return
		end
		index += 1
		showQuestion()
	end)
end

function Class.Build(playerGui: Instance, _controllers: any): Kit.Window
	local w = Kit.Window(playerGui, "Class", "CLASS IN SESSION", UDim2.fromScale(0.62, 0.72))
	window = w
	Kit.Aspect(w.Root, 1.35)

	quizFrame = Kit.Frame("Quiz", w.Body, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))
	progressLabel = Kit.Label("Progress", quizFrame, "QUESTION 1 / 5", UDim2.fromScale(0, 0), UDim2.fromScale(0.6, 0.08), "Title", UITheme.Paper, 32, Enum.TextXAlignment.Left)
	timerLabel = Kit.Label("Timer", quizFrame, "0:00", UDim2.fromScale(0.6, 0), UDim2.fromScale(0.4, 0.08), "Number", UITheme.Gold, 30, Enum.TextXAlignment.Right)

	local card = Kit.Panel("QuestionCard", quizFrame, UDim2.fromScale(0, 0.11), UDim2.fromScale(1, 0.3), nil, UITheme.PanelLight)
	questionLabel = Kit.Label("Question", card, "", UDim2.fromScale(0.05, 0.1), UDim2.fromScale(0.9, 0.8), "BodyBold", UITheme.Paper, 34)

	for i = 1, 4 do
		local column = (i - 1) % 2
		local row = (i - 1) // 2
		local button = Kit.Button(quizFrame, CHOICE_LABELS[i], ANSWER_STYLES[i], UDim2.fromScale(column * 0.51, 0.46 + row * 0.27), UDim2.fromScale(0.49, 0.24))
		button.TextXAlignment = Enum.TextXAlignment.Left
		button.Activated:Connect(function()
			choose(i)
		end)
		answerButtons[i] = button
	end

	resultFrame = Kit.Panel("Result", w.Body, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.8, 0.8), Vector2.new(0.5, 0.5), UITheme.PanelLight)
	resultFrame.Visible = false
	local scale = Instance.new("UIScale")
	scale.Parent = resultFrame
	resultTitle = Kit.Label("Title", resultFrame, "", UDim2.fromScale(0.05, 0.08), UDim2.fromScale(0.9, 0.26), "Title", UITheme.Paper, 64)
	resultTitle.Rotation = -3
	resultScore = Kit.Label("Score", resultFrame, "", UDim2.fromScale(0.05, 0.38), UDim2.fromScale(0.9, 0.14), "Number", UITheme.Paper, 36)
	resultRewards = Kit.Label("Rewards", resultFrame, "", UDim2.fromScale(0.05, 0.54), UDim2.fromScale(0.9, 0.14), "BodyBold", UITheme.Gold, 28)
	local close = Kit.Button(resultFrame, "DONE", "Primary", UDim2.fromScale(0.5, 0.88), UDim2.fromScale(0.5, 0.16), Vector2.new(0.5, 1))
	close.Activated:Connect(function()
		Kit.CloseWindow(w)
	end)
	return w
end

function Class.Open(w: Kit.Window, data: any?)
	if type(data) ~= "table" or type(data.Questions) ~= "table" then
		return -- a refresh without data keeps the current quiz
	end
	questions = data.Questions
	answers = {}
	index = 1
	endsAt = if type(data.EndsAt) == "number" then data.EndsAt else workspace:GetServerTimeNow() + 60
	submitted = false
	quizFrame.Visible = true
	resultFrame.Visible = false
	showQuestion()

	if timerConnection then
		timerConnection:Disconnect()
	end
	timerConnection = RunService.Heartbeat:Connect(function()
		local remaining = endsAt - workspace:GetServerTimeNow()
		timerLabel.Text = Format.Duration(remaining)
		if remaining <= 0 and not submitted and w.Gui.Enabled then
			submit()
		end
	end)
	local _ = window
end

function Class.Close(_w: Kit.Window)
	if timerConnection then
		timerConnection:Disconnect()
		timerConnection = nil
	end
end

return Class
