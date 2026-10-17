# Blueprint Spec, World Scale & UI Design System

This is the reference Blueprint uses to turn a game idea, or a Roblox game to recreate, into a complete, build-ready spec. Every blueprint fills in **every section of Part A**, using the numbers in Parts B–D.

---

# PART A — The Blueprint Template

Copy this structure for every game. Use exact values. If something is a design choice, decide it and mark it *(adjustable)*.

### 0. Overview
- **Working title** (an original name), a **one-line pitch**, the **reference game(s)**, and **what we keep / what we change**
- **Genre**, **target age**, **devices** (mobile-first unless told otherwise), **server size**, and **session target** (minutes)
- **Art style**: low-poly / stylized / realistic, plus a mood board in words (3–5 adjectives and reference games)

### 1. Game Rules
- **Objective**: what the player is trying to do, short-term and long-term
- **Core loop**: numbered steps with how long each takes in seconds
- **Win/lose/fail states**: what happens on death, a reset, a stolen item, or leaving mid-round
- **Round structure** (if any): lobby → intermission (s) → round (s) → results (s)
- **PvP rules**: when it's allowed, safe zones, cooldowns, and spawn protection (s)
- **Social rules**: trading, parties, and friend bonuses
- **Every number**: walk speed, cooldowns, timers, capacity limits, and respawn time

### 2. World Map (overview)
- **Map size** in studs (X × Z) and the **layout pattern** (hub-and-spoke, linear zones, ring, open world, or plots)
- **Coordinate table** for every major area: Name | Center (X, Y, Z) | Size (X × Y × Z) | Purpose | Unlock condition
- **Paths** between areas: width and walk time (distance ÷ 16 studs/s)
- **Landmarks**: one tall, recognizable landmark per zone for navigation
- **SVG top-down map artifact**: to scale, 1 grid square = 10 studs, labeled, with a legend and an N arrow

### 3. Zone Specs (one per zone)
- Theme, palette (hex), materials, lighting mood
- **Layout**: what sits where (coordinates relative to the zone center)
- **Interactables**: name, position, type (ProximityPrompt / Touched / ClickDetector / UI button), what it does, cooldown
- **Spawns**: player spawns, item/enemy/NPC spawn points, rates, caps
- **Gate**: how it unlocks (cost, level, rebirth) and what the barrier looks like
- **Sound**: ambient loop and SFX

### 4. UI Design System
- **Palette tokens** (hex): Background, Panel, Panel Stroke, Primary, Secondary, Premium, Danger, Text, Text Stroke, Rarity colors
- **Typography**: font per role (title / button / body / numbers) and max text sizes
- **Button styles**: Primary / Secondary / Premium / Danger / Close / Icon, each with fill gradient, stroke, corner radius, text style, and pressed and disabled states
- **Panel style**: corner, stroke, padding, header bar, close button position
- **Motion**: open/close tween, button press, number tick-up, reward popup
- **Sound**: click, open, purchase, error, reward
- **HTML mockup artifacts** of the HUD and key screens, using these exact tokens

### 5. Screen-by-Screen UI
For each screen (HUD, Shop, Inventory, Rebirth, Settings, Daily Reward, Codes, Game Pass Store, Results, Trade…):
- **Purpose**, and **how it opens** (button, ProximityPrompt, auto-popup trigger)
- **Element table**: Name | Type | Parent | Position (UDim2) | Size (UDim2) | AnchorPoint | Style token | Behavior
- **States**: empty, loading, can't afford, owned/equipped, max level
- **Mobile check**: touch targets at least 44 px, nothing hidden under the thumbstick or jump button

### 6. Economy Tables
- Currencies, and how each is earned and spent
- **Upgrade table**: Tier | Cost | Effect | Time-to-afford (free player) | Time-to-afford (2× pass)
- **Item/pet/rarity table**: Name | Rarity | Odds % | Multiplier | Source
- **Rebirth/prestige**: requirement, what resets, what's kept, the multiplier formula
- **Pacing check**: first upgrade under 40 s, new zone every 5–15 min, first rebirth at 30–90 min

### 7. Systems & Data
- **Systems list**: name, server vs. client responsibility, RemoteEvents/RemoteFunctions needed
- **Save data schema**: a Lua table with every saved field and its default value
- **Leaderstats**: what shows on the player list
- **Anti-exploit**: everything server-validated (purchases, currency, distances, cooldowns)

### 8. Edge Cases & Tedious Details
Cover at minimum: a player leaving mid-action, a server shutdown during a save, two players grabbing the same item, a full inventory, a purchase while offline, spamming a button, falling off the map, AFK players, lag/latency on PvP hits, a new player joining a full server, a data load failure (kick with a message, never overwrite saves), and late joiners during rounds.

### 9. Monetization
Game passes and developer products, each with its price in R$, what it gives, where it's shown in the UI, and when it's prompted. All of it must follow Roblox policy (see the knowledge file).

### 10. Build Order
A numbered milestone list, each with a definition of done: greybox map → core mechanic → data saving → HUD → economy → shops → zones → polish/VFX → monetization → soft launch.

### 11. Decisions Log
A running list of every decision made in the conversation, kept up to date.

---

# PART B — Roblox World Scale Reference

| Thing | Value |
|---|---|
| 1 stud | about 0.28 m (Roblox's physics convention) |
| Avatar height | about 5–5.5 studs (R15 default), about 2 studs wide |
| Default WalkSpeed | **16 studs/s** |
| Default JumpHeight | **7.2 studs** (JumpPower 50) |
| Gravity | 196.2 studs/s² |
| Default Baseplate | 2048 × 16 × 2048 studs |
| Doorway | 6 W × 9 H studs minimum (8 × 10 feels comfortable) |
| Ceiling height (interiors) | 12–16 studs; 20+ for big halls |
| Corridor | 10–16 studs wide |
| Main path / crowd street | 20–40 studs wide |
| Stair step | 1 stud rise, 1.5–2 studs deep (or use a ramp/wedge) |
| Max climbable step without jumping | about 2 studs |
| Jumpable gap (flat, at default speed) | about 10–12 studs comfortably; obby "hard" jumps are 13–15 |
| Jumpable ledge height | up to about 6.5 studs (keep 1 stud of margin below 7.2) |
| Tycoon / base plot | 80 × 80 to 120 × 120 studs, with 20+ studs between plots |
| Steal-a-___ base | about 60 × 40 studs, with 8–10 collector pads |
| Spawn/lobby hub | 80 × 80 to 150 × 150 studs |

**Walk-time rule:** time = distance ÷ 16. Anything in the core loop should be within a **10–15 s walk (160–240 studs)**. A zone-to-zone trip over 30 s (about 480 studs) needs a teleporter, a vehicle, or a speed upgrade.

**Server sizes:** steal/PvP base games 6–10, simulators 12–20, horror co-op 4–8, battlegrounds 12–20, roleplay/social 30–50.

**Performance:** keep part counts low (use MeshParts and unions sparingly), keep StreamingEnabled on (the default for new places), and aim for under 50 unanchored physics parts per player. Mobile phones are the weakest device; design for them.

---

# PART C — UI Design System for Roblox

## C1. Layout rules
- **Size with Scale, not Offset**, so UI fits every screen: `UDim2.fromScale(...)`. Lock shapes with **UIAspectRatioConstraint**, and cap huge screens with **UISizeConstraint**.
- **Text:** `TextScaled = true` plus a **UITextSizeConstraint** (MaxTextSize around 36 for buttons, 48 for titles) so text stays readable.
- **Safe areas:** use the ScreenGui's `ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets` (the default). That keeps UI clear of Roblox's top bar and phone notches.
- **Touch targets:** at least 44 × 44 px on the smallest phone. Main action buttons should be around 10–12% of screen height.
- **Reserved zones on mobile (landscape):** the bottom-left ~30% × 40% is the **thumbstick**, and the bottom-right ~25% × 35% is the **jump button**. Keep important UI out of these areas.
- **ScreenGui settings:** `ResetOnSpawn = false` and `ZIndexBehavior = Enum.ZIndexBehavior.Sibling`, with one ScreenGui per major screen or one HUD plus a Frame per screen.

## C2. Standard HUD placement (simulator / tycoon / steal-a-___)
| Element | Position (AnchorPoint) | Notes |
|---|---|---|
| Currency stack | Left middle, `Position (0.01, 0.40)`, AnchorPoint (0, 0.5) | An icon plus a big number with an abbreviation (1.2K, 3.4M, 5.6B) |
| Menu buttons (Shop, Pets, Rebirth, etc.) | Left side under the currency, a vertical list of 3–6 square icon buttons | UIListLayout, padding 0.01 |
| Boosts / timers | Right middle, `(0.99, 0.40)`, AnchorPoint (1, 0.5) | Active 2× and event timers |
| Store / Robux button | Top-right area below the top bar | Premium (gold) style |
| Notifications / rewards | Top center, `(0.5, 0.12)`, AnchorPoint (0.5, 0) | Auto-hide after 3 s |
| Objective / quest tracker | Top center or right | One line: "Steal a Rare item (0/1)" |
| Main action button (mobile) | Right side above the jump button | Only if the game has a core action that isn't tap-on-object |

## C3. Palette presets (pick one, then adjust)
| Preset | BG / Panel | Panel Stroke | Primary | Secondary | Premium | Danger | Text | Fits |
|---|---|---|---|---|---|---|---|---|
| **Candy Sim** | `#2B2D42` / `#3A3D5C` | `#1B1C2E` | `#3FD15B` | `#3FA7FF` | `#FFC93C` | `#FF4D5E` | `#FFFFFF` | Simulators, pets, steal-a-___ |
| **Meme Pop** | `#1A1033` / `#2C1B54` | `#0D0820` | `#FF3EA5` | `#00D9FF` | `#FFE14D` | `#FF5A36` | `#FFFFFF` | Brainrot/meme games |
| **Cozy Farm** | `#F4E9D8` / `#FFF8EC` | `#8B6B4A` | `#6CC24A` | `#F2A541` | `#FFD166` | `#E5533D` | `#4A3426` | Farming, gardening, idle |
| **Dread** | `#0B0C10` / `#16181F` | `#000000` | `#C9C9C9` | `#5B7083` | `#B08D57` | `#9E1B1B` | `#E6E6E6` | Horror, survival |
| **Anime Clash** | `#0E0E14` / `#1C1C28` | `#000000` | `#FF6B1A` | `#7A5CFF` | `#FFD23F` | `#FF2E4C` | `#FFFFFF` | Battlegrounds, combat |
| **Clean Social** | `#F5F7FA` / `#FFFFFF` | `#D0D7E2` | `#4C8DFF` | `#7BD389` | `#FFB703` | `#EF476F` | `#1E2533` | Roleplay, hangouts |

**Rarity colors (standard):** Common `#B0B6BE` · Uncommon `#5BD96A` · Rare `#3FA7FF` · Epic `#B04DFF` · Legendary `#FFB627` · Mythic `#FF3B6B` · Secret `#111111` with a rainbow UIGradient.

## C4. Button styles (example tokens for "Candy Sim")
Each button is a `TextButton` or `ImageButton` with `AutoButtonColor = false`, plus children `UICorner`, `UIStroke` (ApplyStrokeMode = Border), `UIGradient` (Rotation 90), and `UIScale` (for the press animation).

| Style | Gradient (top → bottom) | Border stroke | Corner | Text |
|---|---|---|---|---|
| **Primary** | `#5CE077` → `#22A33C` | `#0E5A1F`, 3 px | `UDim.new(0.25, 0)` | White, FredokaOne, text stroke `#0E5A1F` 2 px |
| **Secondary** | `#66BBFF` → `#1F7FE0` | `#0B3F73`, 3 px | 0.25 | White, text stroke `#0B3F73` |
| **Premium (Robux)** | `#FFE066` → `#F59F00` | `#8A5300`, 3 px | 0.25 | White, text stroke `#8A5300`, plus a Robux icon on the left |
| **Danger** | `#FF7380` → `#D62839` | `#6E0D18`, 3 px | 0.25 | White, text stroke `#6E0D18` |
| **Close (X)** | `#FF5A5A` → `#C81E1E` circle | `#5A0A0A`, 3 px | `UDim.new(1, 0)` (circle) | "X", top-right of the panel, overlapping the corner by 30% |
| **Disabled** | `#9AA0A6` → `#6B7178` | `#3C4046` | same | `#E0E0E0`, no hover effect |

**Pressed:** tween UIScale to 0.92 over 0.08 s, then back to 1.0 with Back/Out over 0.15 s. **Hover (PC):** UIScale 1.05. **Click sound** on every press.

**Panels:** Panel color, `UICorner` 0.06, `UIStroke` 4 px Panel Stroke, `UIPadding` 0.03, a header bar with the title (FredokaOne, white, stroked), and the Close button top-right. Open with a size or UIScale tween from 0.8 → 1.0 (Back/Out, 0.25 s) and dim the background with a black frame at 0.5 transparency.

**Fonts (built in):** FredokaOne (playful, sims), LuckiestGuy (meme/loud titles), GothamBold or BuilderSans Bold (clean UI, roleplay), Bangers (comic/anime), Creepster or SpecialElite (horror titles only, never for body text). Numbers: FredokaOne or BuilderSans Bold.

**Number formatting:** abbreviate with K, M, B, T, Qa, Qi… at one decimal. Tick numbers up over 0.3 s when they change, with a "+123" popup that floats up and fades.

---

# PART D — Luau Build-Script Conventions

Build scripts are pasted into **Studio → View → Command Bar** and run once. Rules:
1. **Undoable:** wrap the script in `ChangeHistoryService:TryBeginRecording` / `FinishRecording` so Ctrl+Z removes it all.
2. **Idempotent:** destroy the previous `workspace.Map` or `StarterGui.MainHUD` first, so running it again doesn't duplicate anything.
3. **Data-driven:** put all coordinates, sizes, colors, and names in tables at the top, matching the blueprint's coordinate tables exactly.
4. **Organized:** use Folders per zone, name every Part, set `Anchored = true`, add BillboardGui labels on greybox parts, and use `Color3.fromHex` for colors.
5. **Greybox first:** use SmoothPlastic and the palette colors, with no art. Real models replace the parts later, so keep the names stable.
6. **No gameplay logic** in build scripts. Gameplay goes in Scripts and LocalScripts under ServerScriptService and StarterPlayerScripts, given separately.

### D1. Map greybox skeleton
```lua
-- Paste into the Studio Command Bar and press Enter. Ctrl+Z undoes it.
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local recording = ChangeHistoryService:TryBeginRecording("Build Greybox Map")

local ZONES = {
	-- Name, Center (studs), Size (X, Y, Z), Color
	{ Name = "SpawnHub", Center = Vector3.new(0, 0.5, 0), Size = Vector3.new(120, 1, 120), Color = "#7BD389" },
	{ Name = "Zone1_Meadow", Center = Vector3.new(0, 0.5, -180), Size = Vector3.new(160, 1, 160), Color = "#A3D977" },
}

local old = workspace:FindFirstChild("Map")
if old then old:Destroy() end
local map = Instance.new("Folder")
map.Name = "Map"
map.Parent = workspace

local function addLabel(part, text)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 50)
	gui.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 4, 0)
	gui.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Parent = gui
	gui.Parent = part
end

local function addPart(name, parent, size, center, hex)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = CFrame.new(center)
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromHex(hex)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

for _, zone in ZONES do
	local folder = Instance.new("Folder")
	folder.Name = zone.Name
	folder.Parent = map
	local floor = addPart("Floor", folder, zone.Size, zone.Center, zone.Color)
	addLabel(floor, zone.Name)
end

local spawn = Instance.new("SpawnLocation")
spawn.Anchored = true
spawn.Size = Vector3.new(12, 1, 12)
spawn.CFrame = CFrame.new(0, 1.5, 0)
spawn.Parent = map.SpawnHub

if recording then
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end
print("Greybox map built:", #ZONES, "zones")
```

### D2. UI builder skeleton
```lua
-- Paste into the Studio Command Bar. Builds StarterGui.MainHUD from the design tokens.
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local StarterGui = game:GetService("StarterGui")
local recording = ChangeHistoryService:TryBeginRecording("Build MainHUD")

local T = { -- design tokens from the blueprint
	Panel = "#3A3D5C", PanelStroke = "#1B1C2E", Text = "#FFFFFF",
	Primary = { "#5CE077", "#22A33C", "#0E5A1F" },
	Secondary = { "#66BBFF", "#1F7FE0", "#0B3F73" },
	Premium = { "#FFE066", "#F59F00", "#8A5300" },
}

local old = StarterGui:FindFirstChild("MainHUD")
if old then old:Destroy() end
local hud = Instance.new("ScreenGui")
hud.Name = "MainHUD"
hud.ResetOnSpawn = false
hud.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
hud.Parent = StarterGui

local function makeButton(name, text, style, parent, position, size, aspectRatio)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = false
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = position
	button.Size = size
	button.BackgroundColor3 = Color3.new(1, 1, 1)
	button.Text = text
	button.TextScaled = true
	button.Font = Enum.Font.FredokaOne
	button.TextColor3 = Color3.fromHex(T.Text)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.25, 0)
	corner.Parent = button

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.fromHex(style[1]), Color3.fromHex(style[2]))
	gradient.Parent = button

	local border = Instance.new("UIStroke")
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Thickness = 3
	border.Color = Color3.fromHex(style[3])
	border.Parent = button

	local textStroke = Instance.new("UIStroke") -- Contextual mode outlines the text
	textStroke.Thickness = 2
	textStroke.Color = Color3.fromHex(style[3])
	textStroke.Parent = button

	local textSize = Instance.new("UITextSizeConstraint")
	textSize.MaxTextSize = 36
	textSize.Parent = button

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = aspectRatio -- width ÷ height, e.g. 1 = square
	aspect.Parent = button

	local scale = Instance.new("UIScale")
	scale.Parent = button

	button.Parent = parent
	return button
end

local menu = Instance.new("Frame")
menu.Name = "LeftMenu"
menu.AnchorPoint = Vector2.new(0, 0.5)
menu.Position = UDim2.fromScale(0.01, 0.55)
menu.Size = UDim2.fromScale(0.08, 0.4)
menu.BackgroundTransparency = 1
menu.Parent = hud
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0.03, 0)
list.HorizontalAlignment = Enum.HorizontalAlignment.Center
list.Parent = menu

makeButton("ShopButton", "Shop", T.Primary, menu, UDim2.fromScale(0.5, 0), UDim2.fromScale(1, 0.22), 1)
makeButton("PetsButton", "Pets", T.Secondary, menu, UDim2.fromScale(0.5, 0), UDim2.fromScale(1, 0.22), 1)
makeButton("StoreButton", "Store", T.Premium, hud, UDim2.fromScale(0.92, 0.12), UDim2.fromScale(0.12, 0.08), 2.5)

if recording then
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end
print("MainHUD built")
```

### D3. Button press feel (LocalScript in StarterPlayerScripts)
```lua
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local hud = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("MainHUD")
local pressIn = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local release = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function hookButton(button)
	local scale = button:FindFirstChildOfClass("UIScale")
	if not scale then return end
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, pressIn, { Scale = 0.92 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, release, { Scale = 1 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, release, { Scale = 1 }):Play()
	end)
end

for _, descendant in hud:GetDescendants() do
	if descendant:IsA("GuiButton") then hookButton(descendant) end
end
hud.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("GuiButton") then hookButton(descendant) end
end)
```

When the AI writes the real scripts for a blueprint, it expands these skeletons with every zone, interactable, screen, and element from the spec.
