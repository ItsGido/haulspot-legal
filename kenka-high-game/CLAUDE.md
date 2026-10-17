# Kenka High: Claude Code guide

An original Roblox school-brawler (roleplay + skill-based melee PvP). The code is a Rojo project: Luau source files on disk are synced into Roblox Studio.

- **Design spec:** `../roblox-ai/blueprints/kenka-high/blueprint.md` (rules, numbers, UI). Follow it unless told otherwise.
- **Code contract:** `docs/ARCHITECTURE.md` (services, their APIs, remotes, attributes). Read it before changing anything.

## Commands
```bash
scripts/setup-tools.sh        # one-time: downloads rojo, luau-lsp, selene, stylua, luau into .tools/
scripts/check.sh              # type check + lint + unit tests + rojo build. Must print ALL CHECKS PASSED
scripts/check.sh src/server/Services/CombatService.luau   # type check only the given files (the rest still runs)
.tools/rojo build default.project.json -o build/KenkaHigh.rbxl   # build a place file you can open in Studio
.tools/rojo serve             # live-sync into Studio (install the Rojo plugin in Studio first)
.tools/luau tests/run.luau    # unit tests for src/shared/Logic
```

## Rules
- `--!strict` on every server, client, Logic and Util file. Config files and `Map/MapData` are non-strict.
- **The server is authoritative.** Clients send intent only. Validate types and ranges of every remote argument, rate-limit, and re-check cost, rank, distance and cooldown on the server.
- Every tuning number lives in `src/shared/Config/`. Keep `src/shared/Logic/` pure (no Roblox APIs) and covered by `tests/run.luau`.
- Services and controllers use the Init/Start pattern and reach each other through the table passed to `Init`. Never `require` a sibling service directly.
- New remotes must be added to `src/shared/Util/Net.luau` and documented in `docs/ARCHITECTURE.md`.
- New profile fields go in `DEFAULT_PROFILE` in `DataService.luau` (old saves get them automatically).
- UI is built in code with `src/client/UI/Kit.luau` and `Config/UITheme.luau`: Scale-based sizes, mobile-first, the Manga Ink style.
- Strict-mode tip: for "find or create" code, create into a new local and then assign (see `getOrCreate` in DataService).
- Player-written text (crew names) must go through `TextService:FilterStringAsync`.
- Never reward watching an autoplaying media feed (Roblox policy, Aug 2026). Capsule odds must stay visible in the UI.

## Placeholders to fill before launch
- Robux product and pass ids: `src/shared/Config/Monetization.luau` (0 = disabled).
- Sound ids: `Config/UITheme.luau` → `Sounds` (0 = silent).
- Animation ids: `Config/Animations.luau` (0 = built-in procedural animations).
- Art: the map is greybox built by `MapService` from `Map/MapData.luau`. Replace it by saving a real `Workspace.KenkaHighMap` in the place (keep the folder and part names listed in MapService).

## Testing in Studio
1. `scripts/check.sh`, then open `build/KenkaHigh.rbxl` in Studio (or use `rojo serve` and connect the plugin).
2. Game Settings → Security → turn on **Enable Studio Access to API Services** to test saving. With it off, players get an unsaved in-memory profile and a warning in the output.
3. Test multiplayer combat with Test → Clients and Servers → 2+ players.
4. `Config/Game.luau` → `Studio` has testing switches (skip tutorial, small tournaments).
