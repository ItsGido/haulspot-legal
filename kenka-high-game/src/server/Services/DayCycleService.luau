--!strict
-- The 20-minute school day (blueprint section 1.8). Publishes the current period on
-- ReplicatedStorage attributes so clients can show the clock:
--   PeriodId, PeriodName, PeriodEndsAt (compare with workspace:GetServerTimeNow())

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DayCycle = require(ReplicatedStorage.Shared.Config.DayCycle)
local DayCycleMath = require(ReplicatedStorage.Shared.Logic.DayCycleMath)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Notify = require(script.Parent.Parent.Systems.Notify)

local DayCycleService = {}
DayCycleService.Priority = 3

DayCycleService.PeriodChanged = Signal.new() -- (newState, oldState?)

local current: DayCycleMath.PeriodState? = nil
local warnedForDay = -1

function DayCycleService.GetPeriod(): DayCycleMath.PeriodState
	return DayCycleMath.At(DayCycle, workspace:GetServerTimeNow())
end

function DayCycleService.IsTurfWar(): boolean
	return DayCycleService.GetPeriod().Id == "AfterSchool"
end

function DayCycleService.Init(_services: any) end

function DayCycleService.Start()
	while true do
		local state = DayCycleService.GetPeriod()
		ReplicatedStorage:SetAttribute("PeriodId", state.Id)
		ReplicatedStorage:SetAttribute("PeriodName", state.Name)
		ReplicatedStorage:SetAttribute("PeriodEndsAt", state.EndsAt)

		if not current or current.Id ~= state.Id or current.DayNumber ~= state.DayNumber then
			local old = current
			current = state
			if old then
				local period = DayCycle.Periods[state.Index]
				Notify.All("🔔 " .. state.Name .. ": " .. period.Description, if state.Id == "AfterSchool" then "bad" else "info", 6)
			end
			DayCycleService.PeriodChanged:Fire(state, old)
		end

		-- Warn before the turf war starts.
		if state.Id == "Lunch" and state.Remaining <= DayCycle.TurfWarningSeconds and warnedForDay ~= state.DayNumber then
			warnedForDay = state.DayNumber
			Notify.All(string.format("⚠ Turf war starts in %d seconds! Turf zones turn RED.", math.ceil(state.Remaining)), "bad", 5)
		end
		task.wait(0.5)
	end
end

return DayCycleService
