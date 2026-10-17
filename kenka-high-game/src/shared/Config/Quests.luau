-- Rumors (quests). Services report progress with QuestService.Progress(player, eventName, amount).
--
-- Event names (the full list; services must use these exact strings):
--   "WinFight"      any fight won (open fight KO or duel)
--   "WinDuel"       challenge duel won
--   "LandHit"       a hit landed on a player or NPC
--   "Parry"         successful parry
--   "FinishJob"     any job shift completed
--   "AttendClass"   class minigame passed
--   "CaptureTurf"   took part in a turf capture
--   "EarnYen"       yen earned (amount = yen)
--   "BuyFood"       bought a food item
--   "VisitDojo"     opened the Style screen at the Sensei
--   "Customize"     saved changes in the character creator
--   "JoinCrew"      joined or created a crew
--   "RankUp"        reached a new rank
--   "UseHeat"       landed a Heat move
--   "TournamentMatch" played a tournament match

export type QuestDef = {
	Id: string,
	Title: string,
	Event: string,
	Goal: number,
	Rep: number,
	Yen: number,
	Scrolls: number,
}

local Quests = {
	DailyCount = 3,
	WeeklyCount = 3,
	DailyRerollsFree = 1,

	Daily = {
		{ Id = "d_win3", Title = "Win 3 fights", Event = "WinFight", Goal = 3, Rep = 150, Yen = 300, Scrolls = 2 },
		{ Id = "d_duel2", Title = "Win 2 challenge duels", Event = "WinDuel", Goal = 2, Rep = 200, Yen = 250, Scrolls = 2 },
		{ Id = "d_hits60", Title = "Land 60 hits", Event = "LandHit", Goal = 60, Rep = 100, Yen = 200, Scrolls = 2 },
		{ Id = "d_parry10", Title = "Parry 10 attacks", Event = "Parry", Goal = 10, Rep = 150, Yen = 250, Scrolls = 2 },
		{ Id = "d_jobs3", Title = "Finish 3 job shifts", Event = "FinishJob", Goal = 3, Rep = 100, Yen = 400, Scrolls = 2 },
		{ Id = "d_class2", Title = "Attend 2 classes", Event = "AttendClass", Goal = 2, Rep = 120, Yen = 300, Scrolls = 2 },
		{ Id = "d_food3", Title = "Eat 3 meals in town", Event = "BuyFood", Goal = 3, Rep = 100, Yen = 150, Scrolls = 2 },
		{ Id = "d_heat2", Title = "Land 2 Heat moves", Event = "UseHeat", Goal = 2, Rep = 150, Yen = 250, Scrolls = 2 },
		{ Id = "d_yen1500", Title = "Earn 1,500 yen", Event = "EarnYen", Goal = 1500, Rep = 120, Yen = 200, Scrolls = 2 },
	} :: { QuestDef },

	Weekly = {
		{ Id = "w_win25", Title = "Win 25 fights", Event = "WinFight", Goal = 25, Rep = 800, Yen = 2500, Scrolls = 8 },
		{ Id = "w_duel12", Title = "Win 12 challenge duels", Event = "WinDuel", Goal = 12, Rep = 800, Yen = 2000, Scrolls = 8 },
		{ Id = "w_turf3", Title = "Capture 3 turfs with your crew", Event = "CaptureTurf", Goal = 3, Rep = 700, Yen = 3000, Scrolls = 8 },
		{ Id = "w_jobs15", Title = "Finish 15 job shifts", Event = "FinishJob", Goal = 15, Rep = 500, Yen = 3500, Scrolls = 8 },
		{ Id = "w_parry60", Title = "Parry 60 attacks", Event = "Parry", Goal = 60, Rep = 600, Yen = 2000, Scrolls = 8 },
		{ Id = "w_tourney3", Title = "Play 3 tournament matches", Event = "TournamentMatch", Goal = 3, Rep = 600, Yen = 2500, Scrolls = 8 },
	} :: { QuestDef },

	-- "Transfer Arc": the new-player story, done in order.
	Story = {
		{ Id = "s1", Title = "Customize your look at the Nurse's Office mirror", Event = "Customize", Goal = 1, Rep = 40, Yen = 200, Scrolls = 0 },
		{ Id = "s2", Title = "Finish a job shift in town", Event = "FinishJob", Goal = 1, Rep = 60, Yen = 300, Scrolls = 1 },
		{ Id = "s3", Title = "Win a challenge duel", Event = "WinDuel", Goal = 1, Rep = 80, Yen = 300, Scrolls = 1 },
		{ Id = "s4", Title = "Grab a meal in the Shotengai", Event = "BuyFood", Goal = 1, Rep = 40, Yen = 150, Scrolls = 0 },
		{ Id = "s5", Title = "Attend a class", Event = "AttendClass", Goal = 1, Rep = 60, Yen = 200, Scrolls = 1 },
		{ Id = "s6", Title = "Visit the Sensei at the Dojo", Event = "VisitDojo", Goal = 1, Rep = 40, Yen = 150, Scrolls = 1 },
		{ Id = "s7", Title = "Land 5 parries", Event = "Parry", Goal = 5, Rep = 80, Yen = 250, Scrolls = 1 },
		{ Id = "s8", Title = "Win 5 fights", Event = "WinFight", Goal = 5, Rep = 120, Yen = 400, Scrolls = 2 },
		{ Id = "s9", Title = "Reach Troublemaker rank", Event = "RankUp", Goal = 2, Rep = 0, Yen = 500, Scrolls = 2 },
		{ Id = "s10", Title = "Join or create a crew", Event = "JoinCrew", Goal = 1, Rep = 200, Yen = 1000, Scrolls = 3 },
	} :: { QuestDef },
}

return Quests
