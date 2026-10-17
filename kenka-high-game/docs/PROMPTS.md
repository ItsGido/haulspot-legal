# Prompt pack: continuing Kenka High with Claude Code

Open this folder (`kenka-high-game/`) in Claude Code and paste any of these. Claude Code reads `CLAUDE.md` and `docs/ARCHITECTURE.md` automatically, so it knows the project rules.

## Getting it running
- "Run scripts/setup-tools.sh and scripts/check.sh, then tell me how to open the built place in Roblox Studio."
- "I opened build/KenkaHigh.rbxl in Studio and got these errors in Output: <paste>. Fix them."
- "Walk me through testing a 2-player fight in Studio with Test > Clients and Servers."

## Art and feel
- "Replace the procedural animations: here are my animation ids <ids>. Put them in Config/Animations.luau and make sure every action uses them."
- "I uploaded these sounds <ids>. Wire them into Config/UITheme.luau Sounds and add any missing hooks (bell at period change, rank-up, KO)."
- "I built a real map in Studio and saved it as Workspace.KenkaHighMap. Check MapData coordinates still match my interactables and turf walls, and update MapData from a Place Scanner export I'll paste."
- "Make hit effects juicier: screen shake curves, hit-stop, and speed lines on heavies."

## Balance and content
- "Boxing is winning too much. Lower its dash cooldown reduction and show me the before/after numbers."
- "Add a 9th fighting style, Kung Fu, with a full kit in Config/Styles.luau and tests."
- "Add 10 new daily rumors and 5 weekly ones that use existing quest events."
- "Add a Winter Festival event: a limited capsule set, festival map decorations, and a 2x yen weekend switch in Config."

## Monetization and launch
- "I created these game passes and products on the Creator Hub: <ids>. Put them in Config/Monetization.luau."
- "Set up scripts/publish.sh for my experience (universe <id>, place <id>) and publish a Saved version."
- "Write the Roblox game page description, 5 thumbnail ideas, and an update log for v1.0."
- "Go through blueprint section 12 (build order) and list what's done, what's partly done, and what's missing."

## Quality
- "Run scripts/check.sh and fix everything it reports."
- "Review CombatService for exploits: what can a modified client do? Fix anything real."
- "Add unit tests for any new logic you add to src/shared/Logic."
