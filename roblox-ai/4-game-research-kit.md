# Game Research Kit

Blueprint can't play Roblox itself. This kit is how it gets the details it needs: web research, screenshots from the user, and a scanner script for places that can be opened in Studio. Everything it learns goes into a **Game Dossier** saved to the Project's knowledge.

---

## 1. Screenshot shot list

Ask the user for the shots that matter for the question. Mobile and PC screenshots both work; full-screen is best. A short description of each shot ("this is the shop after I clicked the cart icon") helps.

**UI**
1. The HUD the moment you spawn (nothing opened)
2. Each menu opened: Shop, Inventory/Pets, Rebirth, Settings, Codes, Daily Rewards, Game Pass Store
3. A purchase confirmation popup and an "can't afford" message
4. A reward or level-up popup
5. The loading screen and any intro/tutorial screens

**World**
6. The spawn area, looking around in 4 directions
7. Each zone's entrance and its gate/unlock requirement
8. A zoomed-out view from the highest point you can reach
9. The player base/plot (if the game has one)
10. Any map board or teleport menu

**Numbers**
11. Upgrade prices for the first 5 tiers
12. Item/pet odds screens (games must show odds for paid random items)
13. Rebirth requirement and reward
14. Your stats after 5, 15, and 30 minutes of play (for pacing)

---

## 2. Web research checklist

For each game, try to find:
- [ ] The community wiki (usually `<game>.fandom.com`): items, prices, odds, zones, mechanics, update history
- [ ] The Roblox game page: description, max server size, genre, update date, game passes and prices
- [ ] Update logs / patch notes (official group, Discord announcements, X/Twitter)
- [ ] Guides and gameplay videos ("beginner guide", "all zones", "best upgrades")
- [ ] Live player counts from a tracker (for how popular it is now)

Mark every fact **Confirmed**, **Likely**, or **Guess**, with the source.

---

## 3. Place Scanner (for places you can open in Roblox Studio)

This works on **your own games**, on **uncopylocked places** (ones the creator made copyable), and on templates. You can't open other people's published games in Studio, so for those use screenshots and the wiki instead.

**How to use:** open the place in Studio → View → Command Bar → paste the script → press Enter. It creates `ServerStorage.PlaceScanResult`. Open it, select all, copy, and paste it into the chat with Blueprint (split it across messages if it's long).

```lua
-- Place Scanner: exports the map and UI layout as text for Blueprint.
-- Read-only except for creating ServerStorage.PlaceScanResult.
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local MAX_PARTS = 2500 -- raise this if the map is bigger
local lines = {}
local partCount = 0

local function round(n)
	return math.floor(n * 10 + 0.5) / 10
end

local function vec(v)
	return string.format("(%s, %s, %s)", round(v.X), round(v.Y), round(v.Z))
end

local function udim2(u)
	return string.format("{%s,%d},{%s,%d}", round(u.X.Scale * 100) / 100, u.X.Offset, round(u.Y.Scale * 100) / 100, u.Y.Offset)
end

local function scanWorld(instance, depth)
	for _, child in instance:GetChildren() do
		if child:IsA("Terrain") or child:IsA("Camera") then
			continue
		end
		local indent = string.rep("  ", depth)
		if child:IsA("BasePart") then
			partCount += 1
			if partCount <= MAX_PARTS then
				table.insert(lines, string.format("%s%s [%s] pos=%s size=%s color=#%s mat=%s",
					indent, child.Name, child.ClassName, vec(child.Position), vec(child.Size),
					child.Color:ToHex(), child.Material.Name))
			end
		elseif child:IsA("Model") or child:IsA("Folder") then
			local summary = ""
			if child:IsA("Model") then
				local cf, size = child:GetBoundingBox()
				summary = string.format(" center=%s size=%s", vec(cf.Position), vec(size))
			end
			table.insert(lines, string.format("%s%s [%s]%s", indent, child.Name, child.ClassName, summary))
		elseif child:IsA("ProximityPrompt") or child:IsA("ClickDetector") or child:IsA("SpawnLocation") then
			table.insert(lines, string.format("%s%s [%s]", indent, child.Name, child.ClassName))
		end
		scanWorld(child, depth + 1)
	end
end

local function scanGui(instance, depth)
	for _, child in instance:GetChildren() do
		local indent = string.rep("  ", depth)
		if child:IsA("GuiObject") then
			local line = string.format("%s%s [%s] pos=%s size=%s anchor=(%s, %s) bg=#%s",
				indent, child.Name, child.ClassName, udim2(child.Position), udim2(child.Size),
				round(child.AnchorPoint.X), round(child.AnchorPoint.Y), child.BackgroundColor3:ToHex())
			if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
				line ..= string.format(" text=%q font=%s textColor=#%s", child.Text, child.Font.Name, child.TextColor3:ToHex())
			end
			table.insert(lines, line)
		elseif child:IsA("UICorner") then
			table.insert(lines, string.format("%s(UICorner %s,%d)", indent, round(child.CornerRadius.Scale * 100) / 100, child.CornerRadius.Offset))
		elseif child:IsA("UIStroke") then
			table.insert(lines, string.format("%s(UIStroke %spx #%s)", indent, child.Thickness, child.Color:ToHex()))
		elseif child:IsA("UIGradient") then
			local keys = child.Color.Keypoints
			table.insert(lines, string.format("%s(UIGradient #%s -> #%s rot=%s)", indent, keys[1].Value:ToHex(), keys[#keys].Value:ToHex(), child.Rotation))
		elseif child:IsA("LayerCollector") then
			table.insert(lines, string.format("%s%s [%s]", indent, child.Name, child.ClassName))
		end
		scanGui(child, depth + 1)
	end
end

table.insert(lines, "=== PLACE SCAN: " .. game.Name .. " ===")
table.insert(lines, "--- WORLD (Workspace) ---")
scanWorld(workspace, 0)
if partCount > MAX_PARTS then
	table.insert(lines, string.format("... %d more parts not listed (raise MAX_PARTS)", partCount - MAX_PARTS))
end
table.insert(lines, "--- UI (StarterGui) ---")
scanGui(StarterGui, 0)

local old = ServerStorage:FindFirstChild("PlaceScanResult")
if old then old:Destroy() end
local result = Instance.new("ModuleScript")
result.Name = "PlaceScanResult"
result.Source = "--[[\n" .. table.concat(lines, "\n") .. "\n]]\nreturn nil"
result.Parent = ServerStorage
print(string.format("Place scan done: %d parts, %d lines. Open ServerStorage.PlaceScanResult and copy it.", partCount, #lines))
```

---

## 4. Game Dossier template

When research is done, Blueprint writes this up and the user saves it as `dossier-<game>.md` in the Project's knowledge.

```
# Game Dossier: <Game name>
Researched: <date> · Sources: <wiki URL, game page, screenshots, scan>

## At a glance
Genre · Creator · Server size · Peak/current CCU · Released · Last update

## Core loop (timed)
1. ... (~X s)

## Progression & economy
Currencies · Upgrade table · Rarity/odds table · Rebirth formula   [Confirmed/Likely/Guess per row]

## World map
Zones in order, with unlock requirements, rough sizes, and layout notes

## UI
HUD layout · Screens list · Palette (hex) · Fonts · Button style notes

## Monetization
Game passes and products with prices

## Why it works
3–5 bullet points

## Gaps / unknowns
What still needs a screenshot or source
```
