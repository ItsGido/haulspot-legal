# KENKA HIGH (喧嘩高校)

An original Roblox school-brawler: transfer into the roughest high school in town, earn your name in fights, build a crew, take over the streets, and claim the server's Banchō crown.

This folder is the complete game codebase as a [Rojo](https://rojo.space) project. Luau source files live on disk and sync into Roblox Studio, so the game can be built, reviewed and extended with Claude Code.

- **Design spec:** [`../roblox-ai/blueprints/kenka-high/blueprint.md`](../roblox-ai/blueprints/kenka-high/blueprint.md)
- **Code architecture and contracts:** [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- **Claude Code rules:** [`CLAUDE.md`](CLAUDE.md) · **Ready-made prompts:** [`docs/PROMPTS.md`](docs/PROMPTS.md)

## Quick start

### Option A: open the built place (no tools needed on your PC)
1. Get `KenkaHigh.rbxl` (run `scripts/check.sh` on any Linux machine, or ask Claude Code to build it). It's written to `build/KenkaHigh.rbxl`.
2. Double-click it to open in Roblox Studio and press **Play**. The greybox map, HUD and every system are built at runtime.
3. To test saving: **Game Settings → Security → Enable Studio Access to API Services** (you must publish the place first). Without it you get a temporary unsaved profile.
4. To test fights: **Test → Clients and Servers → 2 players → Start**.

### Option B: live-sync with Rojo (best for development)
1. Install [Rokit](https://github.com/rojo-rbx/rokit), then run `rokit install` in this folder (installs rojo, selene, stylua, luau-lsp).
2. Install the Rojo plugin in Studio (Plugins → Manage Plugins, or `rojo plugin install`).
3. Run `rojo serve`, open a new Baseplate in Studio, and click **Connect** in the Rojo plugin.
4. Edit files on disk (or let Claude Code edit them) and Studio updates live.

### Publish to Roblox from the command line
`scripts/publish.sh` builds, checks, and uploads the place with the Roblox **Open Cloud** Place Publishing API. Setup steps are at the top of the script (API key with `universe-places: write`, plus your universe and place ids).

## What's in the game
| System | Where |
|---|---|
| Skill-based melee combat: 4-hit combos, heavies, block/parry, posture, dash, weave, Heat moves, knockdowns, finishers | `CombatService`, `KnockoutService`, `CombatController`, `FXController` |
| 8 fighting styles with passives, 2 techniques + a Heat move each, and mastery levels | `Config/Styles`, `StyleService` |
| Zones (safe / duels-only / open fights) and turf zones that turn red during the turf war | `ZoneService`, `Map/MapData` |
| The 20-minute school day: homeroom, class, lunch, after school | `DayCycleService` |
| Rep and 8 ranks, rookie protection, anti-farm caps | `RepService` |
| Challenge duels with wagers, the server Banchō crown, gym tournaments | `ChallengeService`, `CrownService`, `TournamentService` |
| The new-player tutorial (fight with Goro) | `TutorialService`, `NPCService` |
| Daily/weekly/story quests (rumors) and a login streak | `QuestService` |
| Jobs (ramen delivery, konbini rhythm game, arcade tokens), class quizzes, shops, food buffs, scooters | `JobService`, `ClassService`, `ShopService`, `VehicleService` |
| Cosmetic capsules with visible odds and pity, character creator, height system | `CapsuleService`, `CosmeticsService` |
| Robux passes and products (safe receipt handling) | `MonetizationService` |
| Crews (saved across servers), crew HQs, turf capture and income, name tags | `CrewService`, `TurfService`, `NameTagService` |
| Manga-style HUD, phone with apps, every menu, popups and toasts | `HUDController`, `UI/Screens/*` |
| Saving with session locking, autosave, safe shutdown | `DataService` |

## Checks
```bash
scripts/setup-tools.sh   # Linux: download the tools into .tools/
scripts/check.sh         # type check (Roblox API types) + cross-references + unit tests + place build
```

## Before launch (placeholders)
- Robux ids → `src/shared/Config/Monetization.luau`
- Sound ids → `src/shared/Config/UITheme.luau` (`Sounds`)
- Animation ids → `src/shared/Config/Animations.luau` (built-in procedural animations are used until then)
- Real art: build the map in Studio as `Workspace.KenkaHighMap` (see `MapService` for the required folder names); the greybox is generated only when that folder is missing.
