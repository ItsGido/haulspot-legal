# Kenka High: Architecture & Interface Contract

This is the single source of truth for how the game's code fits together. Every service, controller and screen follows it. If you change an interface here, update every caller.

Design reference: `../roblox-ai/blueprints/kenka-high/blueprint.md` (rules, numbers, UI spec).

---

## 1. Layout (Rojo)

| Folder | Becomes | Contents |
|---|---|---|
| `src/shared` | `ReplicatedStorage.Shared` | `Config/` (all tuning numbers), `Logic/` (pure, unit-tested math), `Map/MapData`, `Util/` (Net, Signal, Cleaner, RateLimiter) |
| `src/server` | `ServerScriptService.Server` | `Main.server.luau` (bootstrap), `Services/` (one ModuleScript per service), `Systems/` (helpers such as `Notify`) |
| `src/client` | `StarterPlayerScripts.Client` | `Main.client.luau` (bootstrap), `Controllers/`, `UI/Kit` (Manga Ink components), `UI/Screens/` (one window per module) |
| `src/character` | `StarterCharacterScripts` | `Health` (disables default regen) |

### Service / controller pattern
```lua
local MyService = {}
MyService.Priority = 50 -- optional, lower starts first (default 100)
local Services: any

function MyService.Init(services: any) -- no yielding: store references, connect remotes
	Services = services
end

function MyService.Start() -- runs in its own thread: loops, player hooks
end

return MyService
```
Services call each other through the table passed to Init: `Services.DataService.AddYen(player, 100, "Job")`. Never `require` another service module directly (that creates circular requires). Functions use `.` not `:`.

Controllers (client) are identical, receiving `Controllers` in Init.

### Coding rules
- `--!strict` on every server/client/Logic/Util file. Config files and MapData are non-strict.
- Strict-mode pattern for "find or create": create into a new local, then assign (see `DataService.getOrCreate`). Don't do `local x = find(); if not x then x = Instance.new() x.Prop = ... end` (Luau narrows `x` to nil inside the branch).
- Cast service tables and remote payloads to `any` when needed. Don't fight the type checker on dynamic data.
- **Server is authoritative.** The client sends intent only. Validate every remote argument's type and range, rate-limit with `RateLimiter`, and re-check costs, ranks, distances and cooldowns on the server.
- All tuning numbers live in `src/shared/Config/*`. No magic numbers in services.
- Player-facing text from players (crew names, messages) must go through `TextService:FilterStringAsync`.
- UI is built in code with `UI/Kit` and `Config/UITheme`. Sizes are Scale-based UDim2. Mobile-first.
- Run `scripts/check.sh` before finishing. It must print `ALL CHECKS PASSED`.

---

## 2. Services (server) and their public API

Implemented foundation (don't rewrite; extend if needed):

### DataService (Priority 10)
- `GetProfile(player) -> profile?` · `WaitForProfile(player) -> profile?`
- `Replicate(player, ...topLevelKeys)`: sends keys to the client (Data_Update) and refreshes player attributes
- `Update(player, keys, fn(profile))` · `AddYen(player, amount, source?) -> added` (sources "Job"/"Class" get VIP and 2x bonuses, reports the "EarnYen" quest) · `SpendYen(player, amount) -> bool` · `AddScrolls(player, n)`
- `GetPublicProfile(player)` · `SaveNow(player)` · `HasPurchase(player, receiptId)` · `RecordPurchase(player, receiptId)` · `IsMemoryProfile(player)`
- Signals: `ProfileLoaded(player, profile)`, `ProfileReleasing(player, profile)`
- Profile schema: `DEFAULT_PROFILE` in `DataService.luau`. Add new fields there (reconcile fills old saves).

### MapService (Priority 1)
- Builds `Workspace.KenkaHighMap` from `MapData` if missing. Folders: `Zones`, `Buildings`, `Interactables` (tagged `Interactable`, attributes `Kind`, `InteractId`, with a ProximityPrompt), `TurfWalls` (tagged `TurfWall`, attribute `TurfId`), `DummySpawns`, `Spawns`.
- `GetMapFolder()` · `GetSpawnCFrame(name: "Courtyard"|"NurseRespawn"|"Station")` · `Teleport(player, cframe)` · `SetNextSpawn(player, name)` (applies on next CharacterAdded)
- Handles the interactable kinds `Teleport` and `Station`, the void check and the `Unstuck` remote.

### InteractionService (Priority 5)
- `Register(kind, handler(player, interactable, part))`: one handler per kind (see MapData for kinds). It checks distance and blocks "safe" kinds during combat or when downed.

### ZoneService (Priority 20)
- `GetZone(player) -> { Name, BaseType, Type, Turf? }` (Type is after the turf war rule) · `GetZoneType(player)` · `ZoneAt(position)`
- Signal `ZoneChanged(player, new, old?)`. Player attributes: `Zone`, `ZoneType`, `ZoneTurf`.

### DayCycleService (Priority 3)
- `GetPeriod() -> { Id, Name, Index, Elapsed, Remaining, EndsAt, DayNumber }` · `IsTurfWar()`
- Signal `PeriodChanged(new, old?)`. ReplicatedStorage attributes: `PeriodId`, `PeriodName`, `PeriodEndsAt`.

### Systems/Notify
- `Notify.Send(player, text, kind?, duration?)` · `Notify.All(...)` · `Notify.Many(players, ...)`. Kinds: info, good, bad, zone, gold, crew.

To implement (each owned by one workstream):

### CombatService [Combat]
- `IsInCombat(player) -> bool` · `IsDowned(player) -> bool`
- `RefreshStats(player)`: re-applies MaxHP, walk speed and passives from height, style and buffs (call after a height, style or buff change)
- `Heal(player, amount) -> bool` (out of combat only) · `Revive(model, hpFraction)` (clears downed, sets HP)
- `RegisterFighter(model, opts)`: makes any Humanoid model fightable (NPCService uses it)
- Signals: `HitLanded(attackerModel, targetModel, info)`, `Parried(defenderModel, attackerModel)`, `HeatLanded(attackerModel, targetModel)`
- Hit permission (`CanHit`): Green blocks everything. Duelists can only hit each other (`ChallengeService.AreDueling`). Otherwise both must be in Red (`ZoneMath.AllowsOpenFight`). Rookie protection (`RepMath.RookieAllowsHit` with the player attributes `Rank`, `RookieProtected`). No hitting downed or `Protected` targets. NPCs flagged `IgnoreZones` can be hit anywhere by their allowed attacker.
- At 0 HP: if in a duel, call `ChallengeService.OnDuelKO(loserPlayer, winnerPlayer)` (no downed state). Otherwise call `KnockoutService.OnZeroHP(targetModel, attackerModel)`.
- Food buffs come from `ShopService.GetBuffValue(player, stat)` (stats: `PostureRegen` fraction, `MaxHP` flat, `DashCooldown` seconds delta, `WalkSpeed` flat). They're ignored while in a duel or tournament.
- Reports quests: `LandHit`, `Parry`, `UseHeat`.

### KnockoutService [Combat]
- `OnZeroHP(targetModel, attackerModel?)`: downed for 8 s (crawl), server ProximityPrompts on the downed character: **Finish** (key V, hold 1.5 s, attacker or anyone who may hit them) and **Help Up** (key E, hold 3 s, crewmates and friends). Finish sends them to the Nurse (`MapService.SetNextSpawn(player, "NurseRespawn")`, then respawn after 5 s) and fires `KO_Screen` with `CosmeticsService.GetKOStamp(attacker)`. Recovering stands them up at 25 HP with 3 s of `Protected`.
- `IsDowned(model) -> bool`
- Signals: `Downed(targetModel, attackerModel?)`, `Finished(targetModel, attackerModel?)`, `Recovered(targetModel)`, `FightEnded(winner: Player, loser: Player, info)`. **The fight result is decided at knockdown**: `FightEnded` fires on Downed when both are players, with `info = { Kind = "Open", WinnerHits, LoserHits }`, and calls `RepService.FightResult`.

### NPCService [Combat]
- `SpawnFighter(opts) -> Model`. `opts = { Name, Mode = "Dummy"|"Tutorial"|"Sparring", CFrame, HeightCm?, Style?, MaxHP?, Owner: Player?, IgnoreZones: boolean?, Respawn: boolean? }`. Dummies stand still. Tutorial mode approaches its Owner and alternates slow M1s with a telegraphed heavy every ~3 s (to teach block and parry). Sparring mode fights back lightly.
- `Despawn(model)`. Spawns dojo dummies at `MapData.Dummies` on Start (hitting them gives 1 mastery XP per 2 hits, no Rep).

### RepService [Progression]
- `GetRank(player) -> number` · `AddRep(player, amount, reason)` (raw add, handles rank-ups: 5 scrolls + 1000 yen × rank, fires `RankUp`, reports the `RankUp` quest with amount = the new rank number and `Notify`)
- `FightResult(winner: Player, loser: Player, info)`: the one place fight rewards happen. `info.Kind` is "Open", "Duel" or "Tournament". It applies the Rep formulas (RepMath), anti-farm caps, the After School Red-zone ×2, the crown ×1.5, the friend +10%, the loss penalty, yen (`Combat.FightWinYen`), mastery XP (win/loss + hits capped), stats (Wins/Losses/DuelsWon), and the quests `WinFight` and `WinDuel`.

### StyleService [Progression]
- `GetEquippedStyle(player) -> Style config` · `GetMasteryLevel(player, styleId?) -> number` · `HasTechnique(player, slot: "Tech1"|"Tech2"|"Heat") -> bool` · `AddMasteryXP(player, xp)` (equipped style) · `GrantStyle(player, styleId)`
- Handles the `Dojo` interactable (opens the "Style" screen with `{ AtDojo = true }`, reports the quest `VisitDojo`) and the remotes `Style_Equip` (only within `Styles.DojoRange` of the Sensei) and `Style_Unlock` (scrolls; "Robux" uses a Style Ticket credit or prompts the StyleTicket product).

### ChallengeService [Progression]
- Server-created "Challenge" ProximityPrompt on every character (key E, 8 studs, hold 0.3 s). The client hides the prompt on its own character.
- Remotes `Challenge_Send`, `Challenge_Incoming`, `Challenge_Respond`, `Challenge_Update`. A ring part (30-stud radius, transparent cylinder) during the duel. Leaving the ring for 3 s is a loss.
- `IsInDuel(player)` · `AreDueling(a, b)` · `OnDuelKO(loser, winner)` · `StartForcedDuel(a, b, opts)` with `opts = { Kind = "Tournament", Center: Vector3, Radius, TimeLimit, OnEnd = function(winner?, loser?, reason) }` (no accept, no wager)
- Signal `DuelEnded(winner, loser, info)`. Normal duels call `RepService.FightResult(winner, loser, { Kind = "Duel", Wager })` and set the loser to 50% HP via `CombatService.Revive`. Player attribute `InDuel`.

### CrownService [Progression]
- Server Banchō crown (blueprint 1.9). Listens to `ChallengeService.DuelEnded`. ReplicatedStorage attributes `CrownHolderId`, `CrownHolderName`, player attribute `Crown`. `IsCrownHolder(player)`. A forced accept for Rank 5+ challengers (ChallengeService asks `CrownService.MustAccept(target, challenger)`).

### TournamentService [Progression]
- `Tournament` interactable sign-up. 8 players (Studio: `Game.Studio.TournamentMinPlayers`). Single elimination via `ChallengeService.StartForcedDuel` in the gym ring. Prizes per `Ranks` and `Game.Tournament`. Broadcasts `Tourney_Update`. Player attribute `InTournament`. Reports the quest `TournamentMatch`.

### TutorialService [Progression]
- First join (`profile.TutorialDone == false`): spawns Goro via `NPCService.SpawnFighter({ Mode = "Tutorial", Owner = player, IgnoreZones = true, ... })` near the courtyard, sends `Tutorial_Update` steps (PickStyle → Attack → Block → Parry → Heavy → KO → Customize/Rumors pointer). `Tutorial_PickStyle(styleId)` grants and equips one starter. `Tutorial_Skip` ends it. Sets `TutorialDone` and gives +60 Rep and +300 yen. `IsInTutorial(player)`.

### QuestService [Economy]
- `Progress(player, event, amount?)` (event names: `Config/Quests.luau`). Daily (3, reset 00:00 UTC by `DayCycleMath.UtcDay`), weekly (3, reset Monday UTC), the story chain, and 1 free reroll per day (+1 with VIP). Remotes `Quest_Claim` and `Quest_Reroll`. The login streak on join (`LoginReward` remote). Handles the `RumorBoard` interactable (opens "Rumors").
- Profile shape: `Quests.Daily = { { Id, Progress, Claimed } }`, the same for Weekly, `Quests.Story = { Index, Progress }`.

### JobService [Economy]
- The `Job` interactable starts the job in `interactable.Job`. RamenDelivery (server checks drop points in order), KonbiniShift (client rhythm minigame, server checks duration and score sanity), ArcadeAttendant (server spawns token parts; touch or prompt to collect). Remotes `Job_Update`, `Job_Submit`, `Job_Cancel`. Pay via `DataService.AddYen(player, pay, "Job")` (+25% in Morning). Reports `FinishJob`. Player attribute `ActiveJob`. Cancelled automatically if the player enters combat or leaves the area.

### ClassService [Economy]
- The `Class` interactable during the Class period (once per class period per player): opens the "Class" screen with 5 multiple-choice questions. `Class_Submit(answers)` passes with 3/5 or better: +120 yen (`AddYen(..., "Class")`), +20 Rep (`RepService.AddRep`), quest `AttendClass`.

### ShopService [Economy]
- The `Shop` interactable opens "Shop" with `{ ShopId }`. `Shop_Buy(shopId, itemId)` validates the item belongs to that shop, rank, price (Morning food discount), and that the player is near the shop. Applies food buffs (one per Group, replace), bandages (`CombatService.Heal`), vehicles (profile `Vehicles`), uniforms (profile `OwnedUniforms`). `Shop_EquipUniform`. `GetBuffValue(player, stat) -> number` (0 if none or expired). Player attributes `Buff_<Group>` = expiry server time. `Fountain` (coin toss, cooldown), `Bathhouse` (free buff). `YenPay_Send` (Rank 3+, daily limit, logs). Reports `BuyFood`.

### VehicleService [Economy]
- `Vehicle_Toggle(vehicleId?)`: mount an owned vehicle (a simple welded model plus walk speed = vehicle speed), or dismount. Dismount automatically on combat, damage or entering a Green interior.

### CapsuleService [Economy]
- The `Capsule` interactable opens "Capsule". `Capsule_Roll(count 1|10, currency "Yen"|"Token")` uses `CapsuleRoll` with saved pity; duplicates become points. `Capsule_Equip(slot, itemId?)` · `Capsule_BuyWithPoints(itemId)`.

### CosmeticsService [Economy]
- `Apply(player)`: height scale (HumanoidDescription Height/Width/Depth/Head scale from `HeightStats.Scale`), uniform color (an armband/jacket part until clothing assets exist), equipped Armband/Aura/Trail, and the title (player attribute `TitleText`). Runs on CharacterAdded and after changes.
- `GetKOStamp(player) -> string` · the `Mirror` interactable opens "Creator". `Creator_Save(changes)` (height costs `Economy.HeightChangeCost` with a 24 h cooldown, except during the tutorial or the first save) reports `Customize`.

### MonetizationService [Economy]
- `OwnsPass(player, key) -> bool` (cached, Studio override) · `GetOwnedPasses(player) -> { [key] = true }` · `RegisterProduct(key, handler(player) -> boolean)` · `PromptProduct(player, key)`
- `MarketplaceService.ProcessReceipt`: idempotent through `DataService.HasPurchase/RecordPurchase`, grants and then `SaveNow` before returning PurchaseGranted. Built-in handlers: CapsuleToken1/10, StarterPack (only within 48 h of first join and once), YenPack, NameChange (sets a CustomName credit), TermPass. StyleTicket adds `profile.StyleTickets += 1` (StyleService redeems it).

### CrewService [Social]
- DataStores `Game.CrewStoreName` (key `crew_<id>`) and `Game.CrewNameStoreName` (lowercase name → id, claimed with UpdateAsync). All edits use UpdateAsync.
- `Crew_Action(action, args)` actions: `Create {Name, Color, Emblem}`, `Invite {UserId}`, `RespondInvite {CrewId, Accept}`, `Leave`, `Kick {UserId}`, `Promote {UserId}`, `Demote {UserId}`, `Info`, `ListServer`, `RequestJoin {CrewId}`, `AcceptRequest {UserId}`, `Disband`.
- `GetCrewId(player)` · `GetCrewSummary(crewId)` · `AreCrewmates(a, b)` · `GetCrewColor(player)`. Signal `CrewChanged(player, crewId?)`. Player attributes `CrewName`, `CrewColor`, `CrewEmblem`. The `CrewHQ` interactable teleports members to their HQ interior (built under `MapData.CrewHQOrigin`) with an exit pad. Reports `JoinCrew`. Remotes `Crew_Update` and `Crew_Invite`.

### TurfService [Social]
- During After School only: crew members within `Crews.CaptureRadius` of a turf wall build capture progress (×members, max ×3). Contested means paused. Progress decays when empty. On capture, the owner's color/emblem goes on the wall, `RepService.AddRep(member, Ranks.TurfCaptureReward)` goes to each member present, and the quest `CaptureTurf`. Income of `Crews.TurfIncome` (`Economy.TurfIncomePerMinute`) per minute to online members of owning crews (not AFK). Ownership resets when the next After School starts. Broadcasts `Turf_Update` every second during the turf war and on changes.

### NameTagService [Social]
- An overhead BillboardGui on every character: name (CustomName if set), rank title in the rank color, crew emblem and name in the crew color, cosmetic title (`TitleText`), a green "ROOKIE" tag when `RookieProtected`, and a gold crown when `Crown`. Updates on attribute changes.

---

## 3. Client controllers and screens

Foundation: `DataController` (profile cache: `Get`, `Observe`, `Changed`), `UIController` (`Open(name, data)`, `Close`, `Toggle`, `Refresh`, `IsOpen`, `GetCurrent`; also opened by the server's `UI_Open`), `UI/Kit` (Window, Panel, Button, Label, Bar, Scroll...).

| Owner | Controllers | Screens (`UI/Screens/*.luau`, Name = file name) |
|---|---|---|
| Combat | `CombatController` (input, stance, client prediction, cooldown UI state; **`CombatController.Request(action)`** is public for the mobile buttons), `FXController` (procedural or ID-based animations, hit sparks, damage numbers, camera shake, parry flash, heat zoom) | — |
| Progression | `ChallengeController` (hides own prompt, ring visuals if client-side) | — (the popups live in UI) |
| Economy | `JobController` (job HUD: timer, waypoint beam to drops/tokens, the konbini rhythm minigame), `VehicleController` (mount key B) | `Shop`, `Capsule`, `Creator`, `Class` |
| Social | `CrewController` (invite popup) | `Crew` |
| UI | `HUDController` (MainHUD per blueprint 5.1 bound to attributes), `ToastController` (Notify), `PopupController` (Challenge popup, RankUp banner, KO overlay, LoginReward, Tournament banner, Tutorial overlay with style pick) | `Phone` (3×3 app grid that opens the other screens), `Rumors`, `Style`, `Map`, `YenPay`, `Fights`, `Store`, `Settings` |

Screen names used with `UIController.Open`: `Phone`, `Rumors`, `Style`, `Crew`, `Map`, `YenPay`, `Fights`, `Store`, `Settings`, `Shop`, `Capsule`, `Creator`, `Class`.

### Input map (PC / gamepad)
| Action | PC | Gamepad |
|---|---|---|
| Stance toggle | T | Y |
| Light attack (M1) | Left click | R2 |
| Heavy (M2) | Right click or R | R1 |
| Block (hold) / Parry (tap) | F | L2 |
| Dash | Q | B |
| Sprint (hold) | Left Shift | L3 |
| Weave | Space + a move direction while in stance | A + direction in stance |
| Tech 1 / Tech 2 / Heat | Z / X / G | DPad Left / DPad Right / L1 |
| Phone | Left Alt or the Phone button | DPad Up |
| Vehicle | B | DPad Down |
| Finish downed (prompt) | V (hold) | — |
| Help up / Challenge / interact (prompt) | E | X |

---

## 4. Remotes (all declared in `src/shared/Util/Net.luau`)

| Remote | Direction | Payload |
|---|---|---|
| Data_Update | S→C | `{ [topLevelKey] = value }` |
| Data_Request (RF) | C→S | → public profile (+ `Derived = { Passes, Memory }`) |
| Notify | S→C | `{ Text, Kind, Duration? }` |
| UI_Open | S→C | `screenName, data?` |
| Settings_Save | C→S | `{ Music?, SFX?, CameraShake?, DamageNumbers?, RookieOptOut?, MobileLayout? }` |
| Unstuck | C→S | — |
| Combat_Request | C→S | `action, data?`. Actions: `Stance`, `M1`, `Heavy`, `BlockStart`, `BlockEnd`, `Dash`, `Weave`, `SprintStart`, `SprintEnd`, `Tech1`, `Tech2`, `Heat`. data: `{ Direction: Vector3? }` |
| Combat_FX | S→All | `{ Kind, Attacker: Model, Target: Model?, Action?, Index?, Damage?, Blocked?, Position: Vector3? }`. Kinds: Swing, Hit, Block, Parry, GuardBreak, Dash, Weave, Heat, Knockdown, Finish, Clash, Technique |
| Combat_Cooldown | S→C | `action, seconds` |
| KO_Screen | S→C | `{ KillerName, Stamp, RespawnIn }` |
| RankUp | S→C | `{ Rank, Title, Scrolls, Yen }` |
| Challenge_Send | C→S | `targetPlayer` |
| Challenge_Incoming | S→C | `{ From: Player, FromName, FromRank, FromTitle, Wager, ExpiresAt }` |
| Challenge_Respond | C→S | `fromPlayer, accept: boolean` |
| Challenge_Update | S→C | `{ State = "Sent"|"Declined"|"Expired"|"Started"|"Ended"|"Cancelled", Opponent?, OpponentName?, Center?, Radius?, Winner?, WinnerName?, Wager?, Message? }` |
| Tourney_Update | S→All | `{ State = "Idle"|"Signup"|"Running"|"Finished", Players = {names}, Needed, Bracket = { { { A, B, Winner? } } } (rounds), Match = { A, B, EndsAt }?, Message? }` |
| Tutorial_Update | S→C | `{ Step: string, Text, Choices? = {styleIds}, Done? }` |
| Tutorial_PickStyle (RF) | C→S | `styleId` → ok |
| Tutorial_Skip | C→S | — |
| Job_Update | S→C | `{ JobId, State = "Started"|"Progress"|"Finished"|"Cancelled", Data? }`, shape owned by JobService/JobController |
| Job_Submit | C→S | `jobId, data` |
| Job_Cancel | C→S | — |
| Vehicle_Toggle | C→S | `vehicleId?` |
| LoginReward | S→C | `{ Day, Streak, Reward = { Yen?, Scrolls?, CapsuleTokens?, Badge? } }` |
| Crew_Update | S→C | crew summary or nil: `{ Id, Name, Color, Emblem, Leader, MyRole, Members = { { UserId, Name, Role, Online } }, MaxMembers, WeeklyRep, TurfsHeld = {turfIds} }` |
| Crew_Invite | S→C | `{ CrewId, CrewName, FromName }` |
| Turf_Update | S→All | `{ Active: boolean, Turfs = { [turfId] = { Name, OwnerCrewId?, OwnerName?, OwnerColor?, OwnerEmblem?, CapturingName?, CapturingColor?, Progress (0-100), Contested } } }` |
| Style_Equip (RF) | C→S | `styleId` → ok, message |
| Style_Unlock (RF) | C→S | `styleId, "Scrolls"|"Robux"` → ok, message |
| Quest_Claim / Quest_Reroll (RF) | C→S | `questId` → ok, message |
| Class_Submit (RF) | C→S | `answers {number}` → ok, `{ Correct, Total, Passed, Yen, Rep }` |
| Shop_Buy (RF) | C→S | `shopId, itemId` → ok, message |
| Shop_EquipUniform (RF) | C→S | `itemId` → ok, message |
| Capsule_Roll (RF) | C→S | `count, currency` → ok, `{ { ItemId, Rarity, Duplicate, Points } }` or message |
| Capsule_Equip (RF) | C→S | `slot, itemId?` → ok, message |
| Capsule_BuyWithPoints (RF) | C→S | `itemId` → ok, message |
| Creator_Save (RF) | C→S | `{ HeightCm?, Face?, Hair?, HairColor? }` → ok, message |
| Crew_Action (RF) | C→S | `action, args` → ok, result or message |
| YenPay_Send (RF) | C→S | `targetUserId, amount` → ok, message |

## 5. Attributes

| On | Attribute | Owner | Meaning |
|---|---|---|---|
| Player | Yen, Rep, Rank, RankTitle, Scrolls, Style, HeightCm, CrewId, TutorialDone, RookieProtected | DataService | mirrors the profile |
| Player | Zone, ZoneType, ZoneTurf | ZoneService | current zone |
| Player | InDuel, Crown, InTournament | Progression | flags |
| Player | CrewName, CrewColor, CrewEmblem | CrewService | crew display |
| Player | TitleText | CosmeticsService | equipped title |
| Player | Buff_<Group> (server time expiry), ActiveJob, Vehicle | Economy | |
| Player | NextSpawn | MapService | internal |
| Character / NPC model | Fighter (true), HP, MaxHP, Posture, MaxPosture, Heat, Stance, Blocking, Downed, InCombat, Protected, StunnedUntil, IsNPC, DisplayName | CombatService / KnockoutService / NPCService | fight state (HUD reads these) |
| ReplicatedStorage | PeriodId, PeriodName, PeriodEndsAt | DayCycleService | school clock |
| ReplicatedStorage | CrownHolderId, CrownHolderName | CrownService | crown |
