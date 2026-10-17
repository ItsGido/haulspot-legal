# KENKA HIGH (喧嘩高校): Game Blueprint v1

> An original school-brawler inspired by the *Gakuran* dossier. It keeps what works (the delinquent fantasy, roleplay and fighting in one world, skill-based combat, identity rolls) and fixes the weak spots (no progression, gangs that only exist on Discord, gacha frustration, new-player bounce, falling player counts).
> All names, places, characters, and kits are original. Values marked *(adj)* are design choices you can tune.

**Companion files:** `map.svg` (top-down map to scale) · `ui-mockup.html` (HUD and key screens) · `build-map.luau` (greybox builder) · `build-hud.luau` (HUD builder)

---

## 0. Overview

| Field | Value |
|---|---|
| **Title** | KENKA HIGH (喧嘩高校, "Brawl High") |
| **Pitch** | Transfer into the roughest high school in town, earn your name in fights, build a crew, take over the streets, and claim the crown of **Banchō**. |
| **Reference** | *Gakuran* (Roblox), plus delinquent manga in general |
| **Keep** | Japanese school and town setting, green/fight zones, parry-and-punish melee, height as a meaningful stat, cheap cosmetic rolls, roleplay |
| **Change** | Real progression (Rep ranks, style mastery), **in-game crews and a turf war**, styles **earned, not gambled**, a guided first fight, rookie protection, challenge duels, a school-day event cycle, terms (seasons), a server Banchō crown |
| **Genre** | Roleplay + skill-based melee PvP |
| **Target age** | 13+ core, 16+ maturity rating (fist-fighting violence, no blood) *(adj)* |
| **Devices** | Mobile-first, plus PC and controller |
| **Server size** | 30 |
| **Session target** | 25–40 min (one school day is 20 min; designed so players stay for 1–2 cycles) |
| **Art style** | Stylized-realistic, warm and cinematic: golden-hour lighting, cherry blossoms, wet asphalt and neon at night. Mood: *gritty, nostalgic, cool, rowdy, warm*. UI looks like manga: thick black ink outlines, speed lines, bold slanted titles. |

---

## 1. Game Rules

### 1.1 Objective
- **Short term (a session):** win fights, finish rumors (quests), earn yen, rank up.
- **Mid term (a week):** master styles, build a crew, hold turf, win a gym tournament.
- **Long term (a term, 8 weeks):** reach **Legend** rank, top the term leaderboard, and hold the server's Banchō crown.

### 1.2 Core loop (timed)
1. **Check the phone** for rumors, the turf status, and the school clock (5 s)
2. **Head to an activity**: a fight zone, a job, class, or the dojo (10–25 s walk)
3. **Do it**: a fight (45–90 s), a job shift (60–120 s), or a class minigame (60 s)
4. **Get rewarded**: Rep, yen, mastery XP, scrolls, with a rank bar animation (3 s)
5. **Spend or upgrade**: food buff, outfit, new technique, crew upgrade, then back to step 1

### 1.3 Zones (the most important rule)
| Zone | Color | Rule |
|---|---|---|
| **Green** | `#3BC46B` | No combat at all. Classrooms, clubs, shops, jobs, station, nurse. |
| **Yellow** | `#F4C542` | Combat **only through an accepted Challenge duel**. Courtyard, shopping street, park, field. |
| **Red** | `#E4322B` | Open fighting. Rookie protection applies (see 1.6). Rooftop, back lot, basketball court, riverbank, docks. |

- During **After School**, all **turf zones become Red** (the turf war window). Players get a 10 s warning toast and the zone pill flashes.
- Entering a Red zone shows a toast: "⚠ RED ZONE: open fights".
- Combat keys do nothing in a Green zone, and the stance is put away automatically.

### 1.4 Combat rules
| Value | Number |
|---|---|
| Base HP | **90–115** (set by height, see 1.5) |
| Posture (guard/stamina) | 100. Regen 12/s after 1.5 s without blocking, sprinting, or dashing. |
| **M1 light combo** | 4 hits: 4 / 4 / 4 / 6 damage. 0.35 s between hits. The 4th hit knocks back 6 studs. The combo resets after 1.0 s idle. |
| **M2 heavy** | 12 damage, 0.45 s windup, 1.4 s cooldown. **Breaks guard** (deals 35 posture damage when blocked). |
| **Block** (hold) | Takes 20% damage. Each blocked hit costs 10 posture. Walk speed is ×0.5 while blocking. |
| **Guard broken** (posture 0) | Stunned for 1.2 s, takes +20% damage. Posture refills to 40 afterward. |
| **Parry** (tap block) | 0.18 s window at the start of block. Stuns the attacker 0.6 s and gives the parrier +15 posture and +10 Heat. Spamming has a 0.8 s lockout. |
| **Dash** | 14 studs in 0.3 s, 2.0 s cooldown, 15 posture. |
| **Weave** (jump + direction while in stance) | 0.25 s i-frames, 6-stud slip, 1.5 s cooldown, 10 posture. |
| **Techniques** (2 per style) | Unlocked by mastery, 6–12 s cooldowns (see Section 6) |
| **Heat meter** | 0–100. +2 per hit landed, +10 per parry, +5 per hit taken. At 100 the **Heat Move** is ready (25 damage, cinematic camera zoom 0.6 s, can be dodged or parried). |
| **Knockdown** | 0 HP means **Downed** for 8 s: you crawl at 4 studs/s and can't attack. |
| **Help up** | A crewmate or friend holds E for 3 s on a downed player. They get back up at 30 HP. |
| **Finish** | The attacker holds F for 1.5 s on a downed player (interrupted by any hit). The victim is sent to the **Nurse's Office** and respawns in 5 s. |
| **Recover** | If nobody finishes you within 8 s, you stand up at 25 HP with 3 s of protection. |
| Losing | −5 Rep (you can't drop below the floor of your current rank). **You never lose yen.** |
| Out of combat | Combat ends 8 s after the last hit dealt or taken. Then HP regenerates 5%/s. |
| Respawn | 5 s at the Nurse's Office (main building, floor 1) |

### 1.5 Height (chosen, not rolled)
Pick a height with a slider at creation from **157 cm to 193 cm** (5'2"–6'4"). You can change it at the Nurse's Office scale for 2,500 yen, once per 24 h. Height changes:
| Height | HP | Walk speed | Reach multiplier | Hitbox |
|---|---|---|---|---|
| 157 cm | 90 | 17 | 0.95 | smallest |
| 175 cm | 102 | 16 | 1.02 | medium |
| 193 cm | 115 | 15 | 1.10 | largest |
Formula: `t = (cm - 157) / 36` → HP = 90 + 25t, Walk = 17 − 2t, Reach = 0.95 + 0.15t, Character scale = 0.92 + 0.16t.

### 1.6 Rookie protection
- **Transfer Student and Freshman** (Ranks 1–2) can only be attacked in Red zones by players at most 1 rank above them. Higher-ranked attacks pass through harmlessly, with a small "ROOKIE" tag above the rookie.
- Rookies can turn this off in Settings ("I'm ready"). It also turns off automatically at Rank 3.
- Rep from beating anyone 3+ ranks below you is 0 (anti-bullying).

### 1.7 Challenge duels
- Hold E on another player (ProximityPrompt "Challenge", 8 studs), or tap their name on the player list.
- The target gets a popup: **Accept / Decline** (10 s, auto-decline).
- On accept, a **30-stud-radius ring** appears around the midpoint. Outsiders can't hit the duelists and the duelists can't hit outsiders. Leaving the ring for 3 s counts as a loss.
- First KO wins. There's no finish step; the loser stands up at 50% HP.
- Rep wager: 20 + 10 × (loser rank − winner rank), clamped to 5–60.
- Challenge cooldown: 30 s after a duel, and 60 s for re-challenging the same player after they decline.

### 1.8 School day cycle (server-wide, 20 real minutes, loops)
| Period | Length | What happens |
|---|---|---|
| **Morning Homeroom** | 3 min | The bell rings. Jobs pay +25%. Food buffs cost 20% less. |
| **Class** | 5 min | Classrooms open the **Class minigame** (60 s quiz or rhythm game, +120 yen and +20 Rep, once per class period). |
| **Lunch** | 3 min | The cafeteria and rooftop become social hotspots. The food shop runs a lunch special. |
| **After School** | 9 min | **Turf war window**: turf zones turn Red, graffiti walls can be captured, and Red zones give **double Rep**. The gym tournament starts at 1:00 into After School when signups are full. |
- The phone clock and the HUD period pill show the time left. A school bell sound plays at each change.

### 1.9 Server Banchō crown
- The crown starts each server **unclaimed**. The first player to win **3 challenge duels in a row** (against Rank 3+) claims it.
- The holder gets a crown above their head, a gold map marker, +50% Rep, and a server-wide announcement.
- Anyone who beats the holder in a challenge duel takes the crown.
- The holder **must accept** challenges from Rank 5+ (auto-accepted). There's a 90 s cooldown between crown duels. If the holder leaves, the crown becomes unclaimed again.

### 1.10 Social rules
- Crews: up to **12 members**, created at Rank 3 for 5,000 yen (see 7.3).
- Trading: **none** in v1 (avoids scams and duping). Yen can be gifted through YenPay at Rank 3+ (max 10,000 per day, logged).
- Friends get **+10% Rep** for fights won near each other (within 60 studs).

---

## 2. World Map (overview)

- **Size:** about 840 × 860 studs (X −420 to 420, Z −380 to 480). Ground at Y = 0. **North = −Z.**
- **Layout:** the **school campus** (north) linked by **Gate Street** (south) to the **town**, with a cross street, **Kawa-dori**, at Z = 120 running east to the river and west to the park.
- **Walk times** (16 studs/s): gate → shopping street 9 s, gate → station 26 s, gate → docks 32 s. **Scooters** (Rank 2, 8,000 yen, 40 studs/s) cut that by about 60%.
- **Landmarks:** the school clock tower (52 studs tall + a 20-stud tower), the red steel river bridge, the station's neon sign, the dock cranes (60 studs), the arcade's giant pixel sign.

### 2.1 Area table
| # | Area | Zone | Center (X, Z) | Size (X × Z) | Purpose | Unlock |
|---|---|---|---|---|---|---|
| 1 | **School Courtyard** (spawn) | Yellow | (0, −70) | 200 × 120 | Spawn, fountain, rumor board, social hub | — |
| 2 | Main School Building | Green | (0, −170) | 240 × 60 (52 tall) | Nurse's Office (respawn), classrooms, lockers | — |
| 3 | West Wing | Green | (−140, −70) | 50 × 160 | Classrooms (Class minigame) | — |
| 4 | East Wing (Clubs) | Green | (140, −70) | 50 × 160 | Music, art, cooking clubs (roleplay) | — |
| 5 | **Rooftop** | Red | (0, −170) at Y = 52 | 240 × 60 | Iconic duel spot, Banchō hangout | — |
| 6 | **Back Lot / Bike Shed** | Red | (0, −260) | 200 × 80 | Classic after-school fight spot | — |
| 7 | Gym | Green (event) | (−260, −230) | 120 × 90 | Gym tournament arena | — |
| 8 | **Basketball Court** | Red | (240, −230) | 90 × 60 | Open fights, pickup games | — |
| 9 | Dojo | Green | (240, −100) | 60 × 50 | Style switching, technique unlocks, spar rings | — |
| 10 | School Field | Yellow | (−300, −60) | 200 × 140 | Track, PE events, open space | — |
| 11 | **Shotengai** (shopping street) | Yellow → **Turf T1** | (0, 250) | 80 × 220 | Shops, jobs, capsule machines | — |
| 12 | Train Station | Green | (0, 420) | 140 × 50 | Alternate spawn (Rank 3+), future expansion gate | — |
| 13 | **Riverbank** (under the bridge) | Red → **Turf T2** | (360, 100) | 120 × 560 | Classic riverbed brawls | — |
| 14 | Kawa-dori Bridge | Yellow | (360, 120) | 120 × 24 | Crosses the river | — |
| 15 | **Hinode Park** | Yellow → **Turf T3** | (−230, 220) | 160 × 160 | Cherry trees, hangouts | — |
| 16 | **Docks** (crew HQs) | Red → **Turf T4** | (−300, 410) | 220 × 120 | 4 warehouses lead into crew HQ interiors | Rank 3 for HQ doors |
| 17 | **Neon Alley** (arcade) | Yellow → **Turf T5** | (170, 260) | 120 × 100 | Pixel Den arcade, nightlife roleplay | — |

### 2.2 Roads
| Road | Center (X, Z) | Size (X × Z) |
|---|---|---|
| Gate Street | (0, 190) | 24 × 380 |
| Kawa-dori | (0, 120) | 840 × 24 |

### 2.3 Map artifact
See **`map.svg`**: 1 grid square = 10 studs, zone colors as above, landmarks and points of interest labeled, with a legend and a north arrow.

---

## 3. Zone Specs

### Z1 School Courtyard (spawn), Yellow
- **Theme:** the front of the school at golden hour. Cherry trees, a stone fountain, iron lamp posts, benches, the clock tower dead ahead.
- **Palette:** stone `#CFC6B8`, sakura `#FF9EC4`, lamp glow `#FFD27A`, uniform navy `#2E4A8C`.
- **Layout** (relative to the center (0, −70)): Spawn pad (0, +40) facing north · Fountain (0, 0), radius 10 · **Rumor Board** (+40, −30) · School gate arch (0, +60), 30 wide · 6 cherry trees in two rows at X ±60 · Benches along X ±80.
- **Interactables:** Rumor Board (ProximityPrompt "Read Rumors" → opens Rumors) · Fountain (prompt "Toss a coin", 10 yen, cosmetic sparkle, 1/min).
- **Spawns:** players at the spawn pad (and the Nurse's Office after a KO). NPC "Goro" for the first-time tutorial only.
- **Sound:** wind and birds by day, cicadas in the evening, the school bell at period changes.

### Z2 Main School Building, Green
- 3 floors of 16 studs each, plus the roof. A central stairwell (10 wide) and 2 end stairwells.
- **Floor 1:** entrance hall with lockers (style loadout preview) · **Nurse's Office** (west end, respawn plus the height-change scale) · Staff room (locked, decoration).
- **Floor 2:** 4 classrooms (Class minigame terminals: the teacher's desk, prompt "Take Class").
- **Floor 3:** 4 classrooms plus the Student Council room (term leaderboard board).
- **Roof access:** central stairwell door, label "ROOFTOP: RED ZONE".

### Z5 Rooftop, Red
- Chain-link fence 8 studs tall around the edge, water tank, AC units for cover, a bench. The Banchō's spot is a painted circle where the crown holder gets a subtle aura.
- Fall protection: the fence is unclimbable. Anyone falling off is teleported to the courtyard after 1 s.

### Z6 Back Lot / Bike Shed, Red
- A bike shed (40 × 12) along the north wall, trash bins, a vending machine (drink buff, 80 yen), concrete walls with graffiti. Floodlight at night.

### Z7 Gym (tournament), Green except during matches
- A sign-up board at the entrance (prompt "Join Tournament", needs 8 players, Rank 2+).
- Center ring 40 × 40, with bleachers on 2 sides for spectators.
- **Tournament:** 8-player single elimination, best of 1, 2 min per match (on a timeout, higher HP% wins). Prizes: winner +1,000 Rep, 10 scrolls, the "Gym King" title for 24 h · finalist +400 Rep, 4 scrolls · semifinalists +150 Rep.

### Z8 Basketball Court, Red
- A fenced court with 2 hoops (a pickup shooting minigame: prompt "Shoot", fun only). Bleachers. Floodlights.

### Z9 Dojo, Green
- A tatami hall with the **Sensei NPC** (prompt "Train" → Style screen), 2 **spar rings** (non-lethal duels, no Rep, mastery XP ×0.5, practice dummies).
- Style switching is free here. Owned styles only.

### Z10 School Field, Yellow
- A 200-stud running track (time trial, leaderboard, cosmetic reward), soccer goals.

### Z11 Shotengai (shopping street), Yellow → Turf T1
- A covered arcade-style street with paper lanterns. Shops line both sides of Gate Street:
| Shop | Position (X, Z) | Type | Function |
|---|---|---|---|
| Ichiban Bowl (ramen) | (−30, 170) | Green interior | Food buffs + **Ramen Delivery job** |
| Konbini 24 | (30, 170) | Green interior | Snacks/drinks + **Konbini Shift job** |
| Tailor Tanaka | (−30, 220) | Green interior | Uniform variants, jackets, hair |
| Capsule Corner | (30, 220) | Green interior | **Cosmetic capsule machines** (odds shown) |
| Speedy Cycles | (−30, 270) | Green interior | Scooters and bikes |
| Sento (bathhouse) | (30, 270) | Green interior | Roleplay hangout, "Refreshed" buff (+10% posture regen, 10 min) |
| Kissa Hoshi (café) | (−30, 320) | Green interior | Roleplay, drinks |
| Pharmacy | (30, 320) | Green interior | Bandages (heal out of combat, 50 yen) |
- **Turf wall T1:** (0, 345), a graffiti wall at the south end of the street.

### Z13 Riverbank, Red → Turf T2
- A dry concrete riverbed with a shallow water channel (30 wide, knee-deep, −2 walk speed in water). Grass slopes down from the street on both sides (ramps every 80 studs).
- **Turf wall T2:** (380, 150), under the south side of the bridge. This is the most iconic fight spot in the game.

### Z15 Hinode Park, Yellow → Turf T3
- A cherry-tree grove, a pond, a playground (roleplay), a gazebo.
- **Turf wall T3:** (−230, 220), the back of the public restroom block.

### Z16 Docks, Red → Turf T4
- Shipping containers (cover and parkour), 2 cranes, 4 warehouses (40 × 40 each) at X −380, −320, −260, −200, Z = 440.
- **Crew HQ doors:** each warehouse door (prompt "Enter Crew HQ", Rank 3+, crew members only) teleports the crew to their private HQ interior, built at runtime 2,000 studs below the map, one per active crew.
- **Turf wall T4:** (−300, 390), a container wall.

### Z17 Neon Alley, Yellow → Turf T5
- Narrow neon-lit lanes with vending machines and karaoke signage. **Pixel Den** arcade at (170, 245): cabinet minigames, a claw machine (cosmetics, yen), the **Arcade Attendant job**.
- **Turf wall T5:** (170, 290).

---

## 4. UI Design System: "Manga Ink"

### 4.1 Palette tokens
| Token | Hex | Use |
|---|---|---|
| Ink (background, outlines) | `#0F1016` | Dimmer, outlines |
| Panel | `#1C1E2B` | Panels |
| Panel Light | `#262A3B` | Rows, cards |
| Panel Stroke | `#000000` | 4 px manga outline |
| Paper (text) | `#F5F1E8` | Main text |
| Muted text | `#A9ADBD` | Secondary text |
| **Kenka Red (primary)** | gradient `#FF5A4F` → `#B81D17`, stroke `#4A0906` | Main actions, fight UI |
| **Uniform Navy (secondary)** | `#4A6FC4` → `#22397A`, stroke `#0B1530` | Secondary actions |
| **Gold (premium/Robux)** | `#FFE066` → `#E09A00`, stroke `#6B4400` | Store, Robux, crown |
| **Success green** | `#5FE08A` → `#249A4C`, stroke `#0B3D1D` | Confirm, claim |
| Sakura (social accent) | `#FF9EC4` | Crew, friends, roleplay |
| HP bar | `#E4322B` on `#3A0F0E` | Health |
| Posture bar | `#F4C542` on `#3A300E` | Posture |
| Heat bar | `#FF7A1A` → `#FFD23F` | Heat |
| Zones | Green `#3BC46B` · Yellow `#F4C542` · Red `#E4322B` | Zone pill, map |
| Rarity | Common `#B0B6BE` · Rare `#3FA7FF` · Epic `#B04DFF` · Legendary `#FFB627` · Mythic `#FF3B6B` | Capsules |

### 4.2 Typography (built-in Roblox fonts)
| Role | Font | Max text size |
|---|---|---|
| Titles, rank-ups, KO text | **Bangers** (manga), slanted with a 2 px black stroke | 64 |
| Buttons | **BuilderSans Bold** (`Enum.Font.BuilderSansBold`) | 32 |
| Body | **BuilderSans Medium** | 22 |
| Numbers (yen, Rep, damage) | **FredokaOne** | 36 |

### 4.3 Button styles
All buttons: `TextButton`, `AutoButtonColor = false`, UICorner `UDim.new(0.18, 0)`, a **4 px black UIStroke border** (the manga ink), a 2 px stroke in the style color on the text, a UIGradient at Rotation 90, and a UIScale for the press animation.
| Style | Fill gradient | Text stroke | Use |
|---|---|---|---|
| Primary | `#FF5A4F` → `#B81D17` | `#4A0906` | Accept, Fight, Challenge |
| Secondary | `#4A6FC4` → `#22397A` | `#0B1530` | Menus, Back |
| Premium | `#FFE066` → `#E09A00` | `#6B4400` | Robux purchases (with the Robux icon left of the text) |
| Success | `#5FE08A` → `#249A4C` | `#0B3D1D` | Claim, Confirm |
| Ghost | Panel Light `#262A3B`, 2 px stroke `#000` | none | Tabs, list rows |
| Close | Red circle 0.08 × 0.08 (aspect 1) with a white "✕" | `#4A0906` | Top-right corner of a panel, overlapping it by 30% |
| Disabled | `#5A5E6B` → `#3B3E48`, text `#A9ADBD` | none | Can't afford / locked |

### 4.4 Panels
- Panel color `#1C1E2B`, UICorner 0.04, **UIStroke 4 px black**, UIPadding 0.03.
- **Header strip:** Kenka Red, slanted with a **3° rotation** on the title label, Bangers title in Paper with a black stroke.
- **Speed-line texture** behind headers (an ImageLabel at 0.85 transparency).
- Background dimmer: a full-screen Ink frame at 0.45 transparency.

### 4.5 Motion
| Event | Animation |
|---|---|
| Panel open | UIScale 0.85 → 1 (Back, Out, 0.22 s) and a dimmer fade 0 → 0.45 (0.15 s) |
| Panel close | UIScale 1 → 0.9 and a fade (0.12 s) |
| Button press | 0.92 (0.08 s) → 1 (Back, 0.15 s) |
| Hit landed | Damage number pops up 2 studs, floats up and fades (0.6 s), plus a 0.05 s hit-stop and a camera shake of 0.3 |
| Parry | A white screen flash at 0.8 → 1 transparency (0.15 s) and a "PARRY!" Bangers stamp |
| KO | Slow-mo 0.4 s (camera only) and a big "K.O." stamp in a manga panel slam |
| Rank up | Full-width banner slides in from the left (0.3 s), holds 2.5 s, plus a gold particle burst |
| Yen/Rep change | Number ticks up over 0.4 s with a "+123" float |

### 4.6 Sound
Click: a short paper snap · Open: a whoosh · Purchase: a coin register · Error: a low thunk · Hit: punch impacts in 3 variations · Parry: a metallic ting · Rank up: a taiko drum hit and a crowd shout · School bell: a chime (classic Westminster melody).

---

## 5. Screen-by-Screen UI

All positions are `UDim2` scale values. `ScreenInsets = CoreUISafeInsets`.

### 5.1 HUD (always on)
| Element | Type | Position | Size | Anchor | Style | Behavior |
|---|---|---|---|---|---|---|
| PlayerCard | Frame | (0.01, 0.02) | (0.24, 0.11) | (0, 0) | Panel | Holds the rank badge, name, HP, posture, and Heat |
| RankBadge | ImageLabel | inside, left | (0.22, 0.9) of the card, aspect 1 | — | Rank color ring | Tap → Rank screen |
| HPBar | Frame + fill | right of the badge, top | (0.72, 0.28) | — | HP tokens | Fill tweens 0.15 s. White "ghost" damage bar lags 0.4 s behind |
| PostureBar | Frame + fill | under HP | (0.72, 0.16) | — | Posture tokens | Flashes when below 25 |
| HeatBar | Frame + fill | under posture | (0.72, 0.12) | — | Heat gradient | Glows at 100 |
| ZonePill | Frame | (0.5, 0.02) | (0.2, 0.05) | (0.5, 0) | Zone color fill, black stroke | "RED ZONE · Riverbank". Pulses on change |
| PeriodPill | Frame | (0.5, 0.075) | (0.16, 0.04) | (0.5, 0) | Panel | "AFTER SCHOOL 6:12" |
| CurrencyStack | Frame | (0.99, 0.02) | (0.16, 0.1) | (1, 0) | Panel | ¥ yen (FredokaOne) and a Rep bar to the next rank |
| StoreButton | TextButton | (0.99, 0.135) | (0.1, 0.06) | (1, 0) | Premium | Opens the Store |
| MenuRail | Frame + UIListLayout | (0.01, 0.42) | (0.055, 0.42) | (0, 0.5) | — | 4 square buttons (aspect 1, full rail width, padding 0.015): **Phone, Style, Crew, Map**. Ends above the thumbstick area. |
| TurfTicker | Frame | (0.99, 0.21) | (0.17, 0.18) | (1, 0) | Panel | Shows the 5 turfs with their owner emblems. Visible during After School |
| Toasts | Frame | (0.5, 0.16) | (0.4, 0.06) | (0.5, 0) | Panel | Queue of auto-hiding messages (3 s) |
| **Mobile combat cluster** | Frame | (0.985, 0.74) | (0.3, 0.32) | (1, 1) | — | Sits **above** the jump button and below the TurfTicker: Attack (big, aspect 1), Heavy, Block, Dash, Tech1, Tech2, Stance toggle. Heat appears as a ring around Attack when full. |

### 5.2 Phone (Left Alt / Phone button)
- A center-right frame (0.72, 0.5), size (0.28, 0.8), anchor (0.5, 0.5), aspect 0.5. Phone body `#0F1016`, screen `#1C1E2B`, 12 px corner.
- **3 × 3 app grid** (UIGridLayout, cell (0.28, 0.16)): **Rumors, Jobber, Crew, Map, YenPay, Style, Fights, Store, Settings**. Each icon is a rounded square in its own color with a white glyph and a label below.
- The status bar shows the school clock and the yen balance.
- **You don't get rooted while the phone is open** (a fix over the reference), but walk speed is ×0.7 and the phone closes automatically if you're hit.

### 5.3 Rumors (quests)
- Tabs: **Daily (3)** · **Weekly (3)** · **Story** (the Transfer Arc, 10 steps for new players).
- Row: icon, title, progress bar, reward chips (Rep, yen, scroll), and a **Claim** button (Success style) when complete.
- Daily reset at 00:00 UTC. Rerolling 1 daily rumor per day is free.

### 5.4 Style / Dojo
- Left: a vertical list of the 8 styles (owned styles in color, locked ones greyed with a scroll cost).
- Right: the selected style's name (Bangers), passive, technique cards (Mastery 5 / 10, Heat at 15) with a lock state, the mastery bar, and **Equip** (Primary) or **Unlock: 25 scrolls** (Success) or **Unlock: 249 R$** (Premium).

### 5.5 Crew
- No crew: **Create Crew** (Rank 3, 5,000 yen) → name (3–16 characters, filtered), color (12 swatches), emblem (a 40-emblem grid). Also a list of public crews in the server with **Request to Join**.
- In a crew: roster (role and online status), turf held, crew Rep this week, invite button, leave button, and for leaders: promote, kick, crew settings.

### 5.6 Map
- A full-screen map image with zone colors, the player arrow, crewmates (sakura dots), turf owners (emblems), and the Banchō (gold crown icon). Tap a shop to set a waypoint (a beam guide in the world).

### 5.7 Challenge popup
- Center (0.5, 0.35), size (0.34, 0.24), anchor (0.5, 0.5). Header "CHALLENGE!" in Bangers. "[Name] · Rank 4 Delinquent wants to fight. Wager: 30 Rep". **Accept** (Primary) / **Decline** (Ghost), with a 10 s countdown bar.

### 5.8 KO screen (when finished)
- A manga panel slams in with "K.O." and "Knocked out by [Name]". "Waking up in the Nurse's Office… 5". A tip line at the bottom.

### 5.9 Capsule Corner
- A machine illustration, a **visible odds table**, the pity counter ("Legendary guaranteed in 42"), **Roll ×1 (1,500 ¥)**, **Roll ×1 (25 R$)**, **Roll ×10 (225 R$)**. The reveal animation is a capsule shake, then a pop with the rarity color burst.

### 5.10 Store
- Tabs: **Passes · Tokens · Term Pass**. Each card shows an icon, name, 1-line benefit, and a Premium price button.

### 5.11 Character creator (FTUE step after the tutorial fight)
- A 3D preview on the left. Tabs: **Height** (slider showing HP/Speed/Reach live) · **Face** · **Hair** · **Uniform**. **Done** (Primary). Faces and hair have 12 free options each. Capsule exclusives are shown locked.

### 5.12 Settings
- Music/SFX volume, camera shake on/off, damage numbers on/off, rookie protection toggle ("I'm ready to fight anyone"), mobile button layout editor (drag to move, saved).

---

## 6. Economy Tables

### 6.1 Currencies
| Currency | Earned from | Spent on |
|---|---|---|
| **Yen (¥)** | Jobs, class, rumors, turf income, fights (small) | Food buffs, clothes, scooters, crew creation, capsules, height change |
| **Rep** | Fights, rumors, tournaments, turf, class | Never spent. Rep = rank progress. |
| **Style Scrolls** | Rumors, rank-ups, tournaments, mastery milestones, login streak | Unlocking styles (25 each) |
| **Robux** | — | Passes, tokens, Term Pass |

### 6.2 Rank ladder (permanent)
| Rank | Title | Total Rep | Unlocks |
|---|---|---|---|
| 1 | Transfer Student | 0 | Tutorial, rookie protection |
| 2 | Freshman | 500 | Scooters, gym tournament |
| 3 | Troublemaker | 2,500 | **Crews**, YenPay gifting, station spawn, rookie protection ends |
| 4 | Delinquent | 8,000 | Jacket customization |
| 5 | Enforcer | 20,000 | Motorcycle (60 studs/s, 45,000 ¥), forced crown challenges |
| 6 | Lieutenant | 45,000 | Name color |
| 7 | Ace | 90,000 | Aura cosmetic slot |
| 8 | **Legend** | 160,000 | Legend jacket, entry to the hall of fame |
Each rank-up gives **5 scrolls** and 1,000 ¥ × rank.

### 6.3 Rep sources
| Action | Rep |
|---|---|
| Win an open fight (KO + finish or recover) | +15 (+0 if the target is 3+ ranks lower) |
| Win a challenge duel | +20 + 10 × (rank gap), clamped 5–60 |
| Lose any fight | −5 (floored at the current rank) |
| Class minigame | +20 |
| Daily rumor | +100–200 |
| Weekly rumor | +500–800 |
| Turf capture (each crew member present) | +200 |
| Gym tournament | Winner 1,000 · finalist 400 · semifinalist 150 |
| Double Rep | Red zones during After School, ×2 |
| Same opponent | Rep from beating the same player is capped at 3 times per hour |

**Pacing check:** Rank 2 in about 15 min (the tutorial plus a few fights), Rank 3 (crews) in about 1.5–2 h, Rank 5 in about 10 h, Legend in about 80 h.

### 6.4 Yen sources
| Job / source | Time | Pay |
|---|---|---|
| **Ramen Delivery** (ride a scooter along a timed route, 3 drops) | 90 s | 250 ¥, +50 for gold time |
| **Konbini Shift** (scan items, a rhythm minigame) | 120 s | 220 ¥ |
| **Arcade Attendant** (collect tokens, fix machines) | 90 s | 200 ¥ |
| Class minigame | 60 s | 120 ¥ |
| Turf income | while held | 30 ¥/min to each crew member online |
| Fight win | — | 20 ¥ |
Jobs pay +25% in Morning Homeroom. Every job is an **active minigame** (no AFK farming; this helps the 2026 algorithm's engagement signals).

### 6.5 Yen sinks
| Item | Price |
|---|---|
| Ramen (Posture regen +20%, 5 min) | 120 ¥ |
| Onigiri (+10 max HP out of combat, 5 min) | 80 ¥ |
| Energy drink (dash cooldown −0.3 s, 3 min) | 150 ¥ |
| Bandages (heal 30 HP out of combat) | 50 ¥ |
| Uniform variants | 1,500–20,000 ¥ |
| Scooter | 8,000 ¥ |
| Motorcycle | 45,000 ¥ |
| Height change | 2,500 ¥ (once per 24 h) |
| Crew creation | 5,000 ¥ |
| Capsule | 1,500 ¥ |
Food buffs never stack in the same category and don't work in duels or tournaments (keeping them fair).

### 6.6 Fighting styles (all **sidegrades**: same base damage, different tools)
| Style | Get it | Passive | Tech 1 (Mastery 5) | Tech 2 (Mastery 10) | Heat Move (Mastery 15) |
|---|---|---|---|---|---|
| **Street Brawler** | Starter | *Scrappy*: +10% damage below 30% HP | Headbutt: short guard break, 8 s cd | Haymaker: charge 0.8 s, 18 dmg, 10 s cd | Dropkick |
| **Boxing** | Starter | *Footwork*: dash cooldown −0.5 s | Feint Jab: cancels into a dash, 6 s cd | Counter Hook: after a parry, 14 dmg, 8 s cd | Rush Combo |
| **Karate** | Starter | *Kime*: heavy attacks +10% damage | Front Kick: +3 studs reach, 7 s cd | Breaking Chop: 40 posture damage, 10 s cd | Iron Fist |
| **Judo** | 25 scrolls | *Kuzushi*: a successful parry auto-throws (6 dmg) | Hip Toss: grab, 10 dmg, 9 s cd | Foot Sweep: knockdown 0.8 s, 10 s cd | Shoulder Slam |
| **Muay Thai** | 25 scrolls | *Clinch*: the 4th M1 is a knee with +15 posture damage | Teep: push 10 studs, 7 s cd | Spinning Elbow: 13 dmg, 9 s cd | Flying Knee |
| **Capoeira** | 25 scrolls | *Ginga*: weave cd −0.5 s, i-frames 0.3 s | Cartwheel Kick: a moving attack, 8 s cd | Rasteira: low sweep, 10 s cd | Armada Spin |
| **Sumo** | 25 scrolls | *Rooted*: 30% knockback resistance, −1 walk speed | Slap Barrage: 5 × 3 dmg, 9 s cd | Charge: 18-stud rush, 11 s cd | Ring-Out Shove |
| **Taekwondo** | 25 scrolls | *Long Leg*: kicks +1 stud reach | Axe Kick: overhead, guard break, 9 s cd | Spinning Back Kick: 14 dmg, 10 s cd | Tornado Kick |
- New players **pick 1 of the 3 starters** for free during the tutorial.
- **Mastery:** levels 1–20. Level L needs 120 × L XP. A win is 80 XP, a loss 25 XP, hits +1 each (capped at 40 per fight). Mastery 5 takes about 30–40 min with a style. Mastery 20 unlocks a style-colored jacket trim (cosmetic).
- **Balance rule:** if any style's win rate is over 54% across Rank 4+ duels for a week, tune it.

### 6.7 Cosmetic capsules (no combat effect)
| Rarity | Odds | Examples |
|---|---|---|
| Common | 60% | Hair dyes, badges |
| Rare | 28% | Jacket embroidery, headbands |
| Epic | 9% | Long coats, unique hairstyles |
| Legendary | 2.7% | Fight auras (sakura petals, lightning, flame) |
| Mythic | 0.3% | Animated jackets, KO stamps |
- **Pity:** Epic or better guaranteed every **10** rolls; Legendary or better guaranteed at **60**. The pity count is saved and shared across yen and Robux rolls.
- Duplicates convert to **Capsule Points** (5 / 15 / 40 / 100 / 250 by rarity). A shop sells any non-Mythic item for points.

---

## 7. Systems & Data

### 7.1 Systems (server-authoritative)
| System | Server | Client | Remotes |
|---|---|---|---|
| **DataService** | Loads and saves the profile (ProfileStore-style session locking), autosave every 120 s, save on leave and BindToClose | — | — |
| **CombatService** | Validates every attack: cooldowns, range (reach + 2 studs latency allowance), zone rules, rookie protection, i-frames. Applies damage, posture, Heat. | Input, animations, VFX, client hit prediction | `Combat_Request` (RemoteEvent: action, target hint), `Combat_Feedback` (server → client) |
| **ZoneService** | Zone parts with attributes `ZoneType`, `ZoneName`, `TurfId`. Tracks each player's zone every 0.25 s. | Zone pill, toasts | `Zone_Changed` |
| **DayCycleService** | The 20-min cycle synced with `workspace:GetServerTimeNow()` | Clock UI, bell | Attribute on ReplicatedStorage: `PeriodName`, `PeriodEndsAt` |
| **ChallengeService** | Requests, accept/decline, ring, result, wager | Popup | `Challenge_Send`, `Challenge_Respond`, `Challenge_Update` |
| **CrownService** | Streak tracking and the holder | Crown marker | `Crown_Changed` |
| **RepService** | Rep, ranks, rank-ups, anti-farm caps | Rank bar, banner | `Rep_Update` |
| **StyleService** | Owned styles, mastery, equip (Dojo-only check) | Style screen | `Style_Equip`, `Style_Unlock` |
| **QuestService** | Rumors: daily and weekly rolls, progress events, claims | Rumors app | `Quest_Update`, `Quest_Claim` |
| **JobService** | Starts and validates job minigames (server checks timing and route checkpoints) | Minigame UI | `Job_Start`, `Job_Step`, `Job_Finish` |
| **CrewService** | Crews saved in a **separate DataStore** keyed by crew id. Cross-server membership via MemoryStore for online lists. Message filtering through TextService. | Crew app | `Crew_Action` (RemoteFunction) |
| **TurfService** | Capture meters, contests, ownership per server, income ticks | Turf ticker, walls | `Turf_Update` |
| **ShopService** | Validates purchases (price, rank, affordability) | Shop UIs | `Shop_Buy` (RemoteFunction) |
| **CapsuleService** | Server-side rolls, pity, dupes → points | Reveal animation | `Capsule_Roll` (RemoteFunction) |
| **MonetizationService** | `ProcessReceipt` (idempotent through a saved receipt list), game pass checks | Prompts | — |
| **TournamentService** | Sign-ups, bracket, teleporting into the ring, results | Bracket UI | `Tourney_Update` |

### 7.2 Save data schema
```lua
local DEFAULT_PROFILE = {
	Version = 1,
	Yen = 500,
	Rep = 0,
	Rank = 1,
	Scrolls = 0,
	HeightCm = 175,
	Appearance = { Face = 1, Hair = 1, HairColor = 1, Uniform = 1, Jacket = 0 },
	Styles = { Owned = { "StreetBrawler" }, Equipped = "StreetBrawler", Mastery = {} }, -- Mastery[styleId] = { Level = 1, XP = 0 }
	Cosmetics = { Owned = {}, Equipped = { Aura = nil, KOStamp = nil } },
	Capsule = { PityEpic = 0, PityLegendary = 0, Points = 0 },
	Quests = { DailySeed = 0, Daily = {}, Weekly = {}, Story = 1, LastDailyReset = 0, LastWeeklyReset = 0 },
	Login = { Streak = 0, LastDay = 0 },
	CrewId = nil,
	Vehicles = { Scooter = false, Motorcycle = false },
	Settings = { Music = 0.6, SFX = 0.8, CameraShake = true, DamageNumbers = true, RookieOptOut = false, MobileLayout = {} },
	Stats = { Wins = 0, Losses = 0, DuelsWon = 0, TourneysWon = 0, TurfCaptures = 0, PlaytimeMin = 0 },
	Term = { Id = 1, Rep = 0, PassOwned = false, PassTier = 0, ClaimedFree = {}, ClaimedPaid = {} },
	LastHeightChange = 0,
	TutorialDone = false,
	PurchaseHistory = {}, -- receipt ids, last 100
}
```
**Leaderstats** (player list): Rank title, then Rep.

### 7.3 Crew data (CrewStore, key `crew_<id>`)
```lua
{ Id = "c_8f2a", Name = "Red Ravens", Color = 3, Emblem = 17, Leader = 12345,
  Members = { [12345] = "Leader", [67890] = "Lieutenant" }, MaxMembers = 12,
  WeeklyRep = 0, TotalCaptures = 0, Created = 1760000000 }
```
- Edits use `UpdateAsync` (never `SetAsync`), so two servers can't overwrite each other.
- Crew names go through `TextService:FilterStringAsync` and a uniqueness check (an OrderedDataStore name index).

### 7.4 Anti-exploit essentials
- The server owns HP, posture, Heat, Rep, yen, cooldowns, and zone state. The client only sends **intent**.
- Hit checks: distance ≤ reach × heightMult + 2, facing within 100°, the target isn't in i-frames or protected, the attacker isn't stunned.
- Movement sanity check: flag (don't kick on first offense) if speed > 1.5× allowed for 2 s. Teleport-back on a confirmed exploit.
- Remote rate limits: combat 12 per second, shop 2 per second, crew 1 per second. Anything over is dropped and logged.
- Purchases: `ProcessReceipt` grants only after the save succeeds, and repeat receipt ids are ignored.

---

## 8. Edge Cases & Tedious Details

| Case | Handling |
|---|---|
| A player leaves mid-fight | Counts as a loss for them (−5 Rep) if they took damage in the last 8 s. The opponent gets the win only if it's a duel or the leaver was below 50% HP. |
| A player leaves mid-duel | The duel ends, and the opponent wins the wager. |
| A player leaves while downed | Counts as finished. |
| Crown holder leaves | The crown becomes unclaimed, with a server announcement. |
| Server shutdown | `BindToClose` saves all profiles (up to 25 s). Duels end with no result. |
| Data load fails | Retry 3 times with backoff, then **kick with "Data failed to load, please rejoin"**. Never play on default data (it would overwrite the save). |
| Two servers load the same profile | Session locking: the newer server waits or steals the lock after 60 s. Every save checks the lock. |
| Both players parry at the same time | Both get a 0.3 s stagger (a clash with VFX). Neither gets a parry bonus. |
| Both hit on the same frame | The server processes them in arrival order, so both can land. |
| Fighting across a zone border | Hits only land if **both** players are in a zone that allows it. A player who steps into Green after being hit stays in combat for 8 s (can't be hit, can't attack, still can't use jobs). |
| A Green zone used as a shield | Being in combat blocks job and shop prompts for 8 s, so players can't use Green zones to cheese fights. |
| Falling off the map / into the void | Teleport to the courtyard at Y < −50. No KO. |
| Stuck in geometry | Settings → "Unstuck": teleport to the courtyard. 60 s cooldown, disabled while in combat. |
| AFK | Roblox kicks after 20 min idle. AFK players don't earn turf income (an input check every 2 min). |
| Button spam | Client debounce plus server cooldowns. Extra requests are ignored silently. |
| Duel ring outsiders | Outsiders get pushed out of the ring softly when it forms. Their projectiles and hits pass through duelists. |
| Two crews capturing the same wall | Contested: the meter pauses and the wall flashes both colors. |
| Captors are KO'd | Their contribution stops. Progress decays 2%/s with nobody present. |
| Crew is full | The Join button is disabled with the text "Crew full (12/12)". |
| Crew leader leaves the crew | Leadership goes to the oldest Lieutenant, otherwise the oldest member. The crew disbands when the last member leaves. |
| Rank-up mid-fight | The banner waits until combat ends. |
| Rookie toggles protection off then on | Can't turn it back on during combat or for 10 min after turning it off. |
| Buying with insufficient yen | The button shows the Disabled style plus "Need ¥X more". The server re-checks. |
| Robux purchase while the player is leaving | The receipt is processed on the next join (no grant until the save succeeds). |
| Tournament player leaves | The opponent advances. If the bracket gets fewer than 4 players before start, it's cancelled and signups return. |
| Chat/name filtering | All player text (crew names, phone messages, rumor board posts) goes through TextService. |
| Mobile: phone opened mid-fight | The Phone button is disabled while in combat. |
| Players at the 30-player cap | Friends join through follow if a slot opens. Roblox handles this. |
| Height change while in a crew HQ/duel | Only at the Nurse's Office scale, so it can't happen during a fight. |

---

## 9. Monetization

| Product | Type | Price | Gives | Where shown |
|---|---|---|---|---|
| **VIP** | Game pass | 299 R$ | +10% yen, VIP booth in Pixel Den, gold chat tag, 1 extra free daily rumor reroll | Store, the VIP booth door |
| **2× Yen** | Game pass | 399 R$ | Double yen from jobs and class (not turf) | Store, job end screen (once per session) |
| **Outfit Slots** | Game pass | 149 R$ | 6 saved outfits (instead of 2) | Tailor |
| **Crew Plus** | Game pass | 249 R$ | Crew banner in the HQ, 12 extra emblem colors, HQ decor items (cosmetic only, crew size stays 12) | Crew app |
| **Style Ticket** | Dev product | 249 R$ | Unlock 1 style of your choice (sidegrades only) | Style screen next to the scroll price |
| **Capsule Token** | Dev product | 25 R$ ×1 · 225 R$ ×10 | Capsule rolls (pity applies) | Capsule Corner |
| **Starter Pack** | Dev product (one-time, 48 h after first join) | 99 R$ | 5,000 ¥, 10 scrolls, 3 capsule tokens, Rookie jacket | Shown after the **first won challenge**, never on spawn |
| **Term Pass** | Dev product (per term) | 399 R$ | 40 tiers of cosmetics. A free track exists for everyone. | Store, end of a rumor claim |
| **Name Change** | Dev product | 99 R$ | Change your display name in game (filtered) | Settings |
| **Private Server** | Roblox setting | 150 R$/month | Private servers with friends | Game page |
| Rewarded video ads | Roblox Rewarded Ads (player-initiated only) | — | +1 daily rumor reroll or a 2× job payout, max 3 per day | Rumors app, job end screen |

**Policy:** capsule odds are visible in the game · no paid power (styles are sidegrades, food buffs don't work in duels) · **no reward-driven media feeds anywhere** (Roblox's Aug 2026 rule).

---

## 10. FTUE: "Transfer Day" (the first 5 minutes)

| Time | Beat |
|---|---|
| 0–3 s | Spawn at the school gate. Short camera sweep over the courtyard and clock tower (skippable). |
| 3–8 s | NPC **Goro**, a cocky senior, bumps into you: *"Oi, transfer kid. You lost?"* A popup asks you to **pick your fighting style**: Street Brawler / Boxing / Karate (3 big cards, one tap). |
| 8–25 s | A scripted tutorial fight in a duel ring. Prompts: **Attack** (M1 combo) → **Block** Goro's heavy → **Parry** the next one (slow-motion assist on the first try) → **Heavy** to break his guard. |
| 25–40 s | Goro goes down: "K.O.!" stamp, **+60 Rep, +300 ¥**. Goro: *"…Not bad. You'll need a crew to survive here."* |
| 40–60 s | Rank bar animates toward Freshman. A waypoint arrow leads to the **Nurse's Office mirror** (character creator: height, face, hair) and the **Rumor Board**, with Story rumor 1 already tracked. |
| 1–5 min | Story rumors 1–3: customize your look → finish a job shift → win a challenge against a real player (rookie-friendly matchmaking text: "Look for players with a green ROOKIE tag"). Rank 2 is reached around minute 10–15. The daily login calendar appears after the first claim. |

Goal: the first action in under 10 s, the first reward in under 40 s, a clear next goal at 60 s.

---

## 11. Live Ops & Retention

- **Daily:** 3 rumors, a login streak (Day 1 300 ¥ · Day 2 500 ¥ · Day 3 1 scroll · Day 4 1,200 ¥ · Day 5 2 scrolls · Day 6 1 capsule token · Day 7 3 scrolls and an exclusive badge, then it repeats).
- **Every 20 min:** the school day cycle (the After School turf war).
- **Hourly-ish:** the gym tournament.
- **Weekly (every Saturday, a fixed update day):** new rumors, a balance patch, the crew turf leaderboard reset with rewards (the top 3 crews get an emblem border for the week).
- **Term (8 weeks):** a new Term Pass, term leaderboard rewards (the top 100 get the "Term Legend" title), 1 new style or map district per term.
- **Events:** a Cultural Festival (Oct), Winter Festival (Dec), Sakura Festival (Apr), Summer Fireworks (Aug). Each brings a limited cosmetic set and a festival map dressing.

---

## 12. Build Order (milestones, solo or a small team)

| # | Milestone | Done when |
|---|---|---|
| 1 | **Greybox map** | `build-map.luau` is run, the walk-test feels right, distances are tuned |
| 2 | **Core combat** | M1/M2/block/parry/dash/weave and posture work server-authoritatively between 2 test players, with placeholder animations |
| 3 | **Zones** | Green/Yellow/Red rules, zone pill, combat lockout in Green |
| 4 | **Data** | Profile load/save, session lock, leaderstats, BindToClose |
| 5 | **HUD** | `build-hud.luau` is run and wired to live HP, posture, Heat, yen, Rep, zone, and period |
| 6 | **KO loop** | Downed, finish, help up, recover, Nurse respawn |
| 7 | **Rep and ranks** | Rep sources, rank-ups, banner, rookie protection |
| 8 | **FTUE** | The Goro tutorial, style pick, Story rumors 1–3 |
| 9 | **Challenge duels and the crown** | Ring, wager, crown streaks |
| 10 | **Styles** | 3 starters with passives and techniques, mastery, Dojo |
| 11 | **Economy** | 3 jobs, food shop, scooter, Rumors (daily/weekly) |
| 12 | **School day cycle** | Periods, bell, class minigame |
| 13 | **Crews and turf** | Crew create/join, turf walls, capture, income |
| 14 | **Art pass** | Replace the greybox with models (keep part names), lighting, VFX, sounds |
| 15 | **Monetization** | Passes, products, capsules with pity, Starter Pack |
| 16 | **Soft launch** | 100–500 players. Track D1, session length, and FTUE funnel drop-off. Fix before scaling ads. |
| 17 | Remaining styles, tournament, Term Pass | Weekly updates from here |

**MVP for soft launch = milestones 1–12** (about 4–6 weeks for an experienced solo scripter). Crews and turf come in the first big update. That gives a "CREWS UPDATE" hook for marketing.

---

## 13. Decisions Log
1. Title is **KENKA HIGH**, an original setting with no names from the reference.
2. Height is **chosen with a slider**, not rolled (it fixes gacha frustration). It's changeable for 2,500 ¥ once per 24 h.
3. Styles are **sidegrades**, earned with scrolls (25) or a Style Ticket (249 R$). Gacha is **cosmetic only**, with disclosed odds and pity at 10 and 60.
4. Three zone types: Green (none), Yellow (duels only), Red (open). Turf zones turn Red during After School.
5. You never lose yen on death. Losing costs −5 Rep, floored at the current rank.
6. Rookie protection for Ranks 1–2 (opt-out available).
7. Crews: max 12, in-game, with turf capture on 5 walls. Crew Plus is cosmetic only.
8. A 20-minute school day cycle drives events.
9. The server Banchō crown changes hands through challenge duels. The holder must accept Rank 5+ challenges.
10. Server size 30. Mobile-first UI with the combat cluster above the jump button.
11. No player trading in v1.
12. MVP is milestones 1–12. Crews come in the first update.
