--!strict
-- Class minigame (blueprint sections 1.8 and 6.4). During the Class period, the classroom doors
-- hand out a short multiple-choice quiz once per class period per player. Correct answers stay on
-- the server; the client only gets the questions and the (shuffled) choices.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClassQuestions = require(ReplicatedStorage.Shared.Config.ClassQuestions)
local DayCycle = require(ReplicatedStorage.Shared.Config.DayCycle)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Ranks = require(ReplicatedStorage.Shared.Config.Ranks)
local DayCycleMath = require(ReplicatedStorage.Shared.Logic.DayCycleMath)
local Net = require(ReplicatedStorage.Shared.Util.Net)
local RateLimiter = require(ReplicatedStorage.Shared.Util.RateLimiter)
local Notify = require(script.Parent.Parent.Systems.Notify)
local EconomyUtil = require(script.Parent.Parent.Systems.EconomyUtil)

local ClassService = {}
ClassService.Priority = 50

local Services: any

local CLASS_PERIOD = "Class"
local CHOICE_COUNT = 4

type Session = {
	DayNumber: number,
	Questions: { any }, -- what the client got: { { Q, Choices } }
	Answers: { number }, -- correct choice index per question (after shuffling)
	EndsAt: number,
	Submitted: boolean,
}

local sessions: { [Player]: Session } = {}
local limiter = RateLimiter.new(3, 2)
local rng = Random.new()
local uiOpen = Net.Event("UI_Open")

-- Seconds until the next Class period starts.
local function secondsUntilClass(): number
	local offset = 0
	for _, period in DayCycle.Periods do
		if period.Id == CLASS_PERIOD then
			break
		end
		offset += period.Length
	end
	local cycleTime = EconomyUtil.ServerNow() % DayCycle.CycleLength
	return (offset - cycleTime) % DayCycle.CycleLength
end

local function buildSession(period: any): Session
	local indices = {}
	for i = 1, #ClassQuestions.Questions do
		table.insert(indices, i)
	end
	local picked = EconomyUtil.Shuffled(indices, rng)
	local questions, answers = {}, {}
	for i = 1, math.min(ClassQuestions.PerClass, #picked) do
		local source = ClassQuestions.Questions[picked[i]]
		local order = EconomyUtil.Shuffled({ 1, 2, 3, 4 }, rng)
		local choices = {}
		local correct = 1
		for newIndex = 1, CHOICE_COUNT do
			local oldIndex = order[newIndex]
			choices[newIndex] = source.Choices[oldIndex]
			if oldIndex == source.Answer then
				correct = newIndex
			end
		end
		table.insert(questions, { Q = source.Q, Choices = choices })
		table.insert(answers, correct)
	end
	return { DayNumber = period.DayNumber, Questions = questions, Answers = answers, EndsAt = period.EndsAt, Submitted = false }
end

local function onClassInteract(player: Player)
	local period = Services.DayCycleService.GetPeriod()
	if period.Id ~= CLASS_PERIOD then
		Notify.Send(player, "No class right now. The next class starts in " .. DayCycleMath.FormatClock(secondsUntilClass()) .. ".", "info", 5)
		return
	end
	local session = sessions[player]
	if session and session.DayNumber == period.DayNumber then
		if session.Submitted then
			Notify.Send(player, "You already took this class. Come back next period!", "info")
			return
		end
		-- Re-open the same quiz (they closed the window).
		uiOpen:FireClient(player, "Class", { Questions = session.Questions, EndsAt = session.EndsAt })
		return
	end
	local created = buildSession(period)
	sessions[player] = created
	uiOpen:FireClient(player, "Class", { Questions = created.Questions, EndsAt = created.EndsAt })
end

local function onSubmit(player: Player, answers: any): (boolean, any)
	if not limiter:Allow(player) then
		return false, "Slow down."
	end
	local session = sessions[player]
	if not session or session.Submitted then
		return false, "No class to hand in."
	end
	if type(answers) ~= "table" then
		return false, "Invalid answers."
	end
	if EconomyUtil.ServerNow() > session.EndsAt + ClassQuestions.SubmitGraceSeconds then
		session.Submitted = true
		return false, "Class is over. The bell already rang."
	end
	local total = #session.Answers
	local correct = 0
	for i = 1, total do
		local answer = answers[i]
		if EconomyUtil.IsInt(answer, 1, CHOICE_COUNT) and answer == session.Answers[i] then
			correct += 1
		end
	end
	session.Submitted = true

	local passed = correct >= ClassQuestions.PassCorrect
	local yen, rep = 0, 0
	if passed then
		yen = Services.DataService.AddYen(player, Economy.ClassYen, "Class")
		if Services.RepService then
			Services.RepService.AddRep(player, Ranks.ClassReward, "Class")
			rep = Ranks.ClassReward
		end
		if Services.QuestService then
			Services.QuestService.Progress(player, "AttendClass", 1)
		end
	end
	return true, { Correct = correct, Total = total, Passed = passed, Yen = yen, Rep = rep }
end

function ClassService.Init(services: any)
	Services = services
	Net.Function("Class_Submit").OnServerInvoke = onSubmit
	Services.InteractionService.Register("Class", onClassInteract)
end

function ClassService.Start()
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
		limiter:Remove(player)
	end)
end

return ClassService
