# Roblox Game Design Knowledge Base

**Snapshot date: October 17, 2026.** Market figures change daily. Always check live charts before you decide anything.

---

## 1. Market snapshot (Fall 2026)

### What's on top right now
| Game | Genre | Notes |
|---|---|---|
| **Steal An Egg** | Steal-a-___ / pet collection | Peaked at about 2.2M CCU in Aug 2026, still at 1.2M to 1.7M on trackers in Sept/Oct. Roblox removed it in late Aug over its rewarded video-feed treadmill, but trackers show it live again. Its status is contested. |
| **Brookhaven RP** | Roleplay / social | The most-visited game ever (about 82.5B visits). Usually 300K to 400K+ CCU. Evergreen. |
| **Adopt Me!** | Pet collection / roleplay | 200K to 270K+ CCU. Evergreen, event-driven. |
| **Steal a Brainrot** | Steal-a-___ / meme collection | Holds the record peak of about **25M CCU**. Kicked off the "steal" wave. |
| **Grow a Garden** (and **Grow a Garden 2**, June 2026) | Idle farming / collection | A huge 2025 hit with a sequel in 2026. |
| **99 Nights in the Forest** | Survival / horror co-op | A 2025 breakout that's still charting. |
| **Murder Mystery 2** | Social deduction | Evergreen. A big trading economy. |
| **Blox Fruits** | Anime RPG / combat | Evergreen grinder. |
| **Jujutsu Shenanigans** | Anime battlegrounds | Anime combat stays strong. |
| **Dandy's World** | Horror / co-op | A character-collection horror game. |
| **Blade Ball, Volleyball Legends** | Timing-based PvP | Simple, skill-based, competitive. |

### Genre heat map
| Genre | Momentum | Difficulty to build | Why it works |
|---|---|---|---|
| **Steal-a-___ / brainrot collection** | 🔥 Very hot, but volatile | Low to medium | Collection + base defense + social PvP (stealing) + meme virality. Clones flood in fast. |
| **Simulators / tycoons / idle** | Steady, the most reliably profitable | Low to medium | Clear numbers going up, rebirth loops, easy monetization. |
| **Horror / survival co-op** | Growing fast | Medium | Friend groups, streamer-friendly, YouTube/TikTok clips. |
| **Anime battlegrounds / combat** | Fastest-growing by some accounts | **High** (VFX, netcode, balance) | Expressive combat, clips, character fantasy. |
| **Roleplay / social hangout** | Evergreen, slow to grow but sticky | Medium to high (lots of content) | Long sessions, friend invites, self-expression. |
| **Parkour / movement / obby** | Rising (movement-tech games) | Low (obby) to medium (movement) | A skill ceiling and flow. Obbies are the easiest entry point for beginners. |
| **Timing PvP (Blade Ball-style)** | Steady | Low to medium | 30-second matches, an instant skill read, cosmetics. |
| **Farming / gardening idle** | Hot after Grow a Garden | Low to medium | Calm loops, offline progress, rare mutations, trading. |

**Key lesson from 2025–26:** The biggest hits combine an **evergreen loop** (collect → upgrade → show off) with a **viral wrapper** (a meme theme like brainrot), plus **social friction** (stealing, trading, PvP). They ship fast and update weekly.

---

## 2. How Roblox decides who gets players (2026)

The algorithm changes (April 2026 onward, per Roblox's Q2 2026 shareholder letter and a June 2026 newsroom post) work like this:
- **A 28-day evaluation window**, up from 7 days. Short spikes count for less, and sustained retention counts for more.
- **New signals:** play-through rate, **first-play bounce rate** (players who leave fast on their first visit), spend days, and Robux per user.
- **An Aug 2026 test update** to better recognize long-term player value. Secondhand reports say it rewards games that do well on **both** retention and monetization.
- **DevEx boost:** Robux spent by **US players aged 18+** in eligible games earns a **42% higher DevEx rate** (since June 8, 2026). Mature, higher-fidelity games for adults are now more lucrative.

**What this means for you:**
1. The first session is everything. Kill bounce with a strong FTUE.
2. D7 and D28 retention matter more than peak CCU. Plan your return loops.
3. Monetization should feel healthy and repeatable (many small purchases on many days), not one-time whales.
4. Don't pour money into ads until D1 retention and session time match the benchmarks for your genre (Roblox's own advice, after you reach 100+ DAU).

### Benchmarks (rough guidance; compare with your genre's scorecard in Creator Hub)
| Metric | Weak | OK | Strong |
|---|---|---|---|
| D1 retention | < 10% | 15–25% | 30%+ (roleplay at 40% is exceptional; obbies run higher) |
| D7 retention | < 3% | 5–8% | 10%+ |
| Avg session | < 6 min | 10–20 min | 25 min+ |
| Payer conversion | < 0.5% | 1–3% | 4%+ |

These are industry rules of thumb, not official figures. Your Creator Hub benchmark scorecard shows your real comparison group.

---

## 3. Policy guardrails (must-know)

- **Reward-driven media feeds (Aug 25, 2026):** Roblox removes games from its **Kids and Select** catalogs if they combine all three: (1) a feed of short videos, images, or posts, (2) that autoplays, loops, or self-scrolls, (3) with a reward or implied reward for continued watching. **Rewarded video ads that the player chooses to start are fine.**
- **Paid random items** (eggs, crates, gacha): odds must be disclosed. Some regions restrict them further.
- **No off-platform transactions**, no misleading thumbnails or ads, and no copyrighted assets or names (a common takedown cause for clones).
- **Age ratings / content maturity questionnaire:** fill it out honestly. It affects who can see your game.

---

## 4. The anatomy of a hit Roblox game

### The three loops
1. **Core loop (30–120 seconds):** the action players repeat. *Example: steal an item → run back to base → it earns money.*
2. **Progression loop (one session):** what grows. *Example: money buys upgrades, which unlock rarer items and a bigger base.*
3. **Return loop (days and weeks):** why come back. *Examples: daily rewards, offline earnings, limited events, friends playing, weekly updates, an incomplete collection.*

### The first 60 seconds (FTUE)
- **0–10 seconds:** the player is doing the core action. No long menus, no walls of text, no 20-second loading screen.
- **10–30 seconds:** the first reward lands, with juice: sound, particles, a number popping up.
- **30–60 seconds:** they see a goal worth chasing (a rare item, a bigger base, a leaderboard) and the first upgrade is affordable.
- **First 5 minutes:** they have a reason to invite a friend and know what's coming tomorrow (daily reward preview, "come back in 1 hour" timers).
- Design for **mobile first**: big buttons, a tap-friendly UI, readable text on a 6-inch screen.

### Evergreen psychology that works (used fairly)
- **Collection and rarity:** common → rare → epic → legendary → mythic → secret. Show the rarest items prominently.
- **Visible status:** pets that follow you, auras, titles, leaderboards, a base others can see.
- **Social friction:** stealing, trading, PvP, team modes. It creates stories and clips.
- **Prestige/rebirth:** reset progress for a permanent multiplier. It extends the game for a long time with little content.
- **Offline progress:** "your base earned 12,000 while you were away" is a powerful return hook.
- **Events and FOMO done right:** weekend events and limited cosmetics, with a calendar so players feel invited, not pressured.

### Economy design basics
- Start fast: the first upgrades should come every 20 to 40 seconds.
- Scale costs 1.4× to 1.8× per tier. Add a rebirth when the curve starts feeling slow, usually 30 to 90 minutes in.
- One soft currency (earned) plus Robux products. Avoid a second premium currency early on.
- Keep a spreadsheet: time-to-afford per upgrade for a free player vs. a 2× gamepass player.

---

## 5. Monetization playbook (Robux)

| Product | Typical price | Notes |
|---|---|---|
| 2× money / 2× luck game pass | 99–399 R$ | The best sellers in simulators. |
| VIP pass (chat tag, VIP area, small bonus) | 199–499 R$ | Status. |
| Extra storage / pet slots / auto-collect | 99–299 R$ | Convenience. |
| Developer products: currency packs, boosts, spins | 19–1,000+ R$ | Repeatable buys. Show the best value. |
| Starter pack (one-time, first session) | 49–149 R$ | The highest-converting offer. Show after the first win, not on spawn. |
| Private servers | 50–200 R$/mo | Friend groups, roleplay. |
| Season/battle pass | 199–499 R$ | Strong for return loops. |
| Rewarded video ads (player-initiated) | n/a | Allowed and earns without spending. |

**Rules:** don't block core fun behind paywalls, keep free progress viable, sell time savers, status, and cosmetics, and offer good value early. Sustainable spending across many days is what the 2026 algorithm rewards.

---

## 6. Launch and growth checklist

- [ ] **Thumbnail and icon:** bright, one clear subject, readable on a phone, shows the fantasy (not a UI screenshot). A/B test them with Roblox's thumbnail testing.
- [ ] **Title:** short, searchable, and clear about the genre, e.g. "Steal a ___", "___ Simulator", "___ Tycoon".
- [ ] **Description:** a one-line hook, then features, update notes, and a group/Discord link.
- [ ] **Soft launch:** get your first 100 to 500 players via friends, Discord, and small sponsored ads. Watch D1 and session length.
- [ ] **Fix the FTUE** until D1 and session time beat the benchmarks. Only then scale ads.
- [ ] **Content creators:** reach out to YouTubers and TikTokers in your genre. Give them early access and a custom code or cosmetic.
- [ ] **Short-form clips:** post gameplay clips on TikTok, Shorts, and Reels every day during launch. Roblox also has an in-app gameplay video feed for creators.
- [ ] **Weekly updates** on a fixed day with a visible "update in 2d 4h" timer. Updates bring players back and signal life to the algorithm.
- [ ] **Roblox group:** group rewards (join for a bonus) grow your notification audience.
- [ ] **Analytics:** instrument funnels (FTUE steps), economy events, and custom events in Creator Hub analytics from day 1.

---

## 7. Genre playbooks (quick reference)

**Steal-a-___:** Base with collector pads → items spawn on a conveyor or shop belt → buy or steal from other bases → items earn passive income → upgrade base defenses (locks, timers, lasers) → rebirth. Key details: a short lock timer after a steal, rare spawns announced server-wide, a heavy meme theme. Risk: an extremely crowded genre, so your theme and twist must be fresh.

**Simulator:** Click or swing tool → collect resource → sell → upgrade tool and backpack → unlock new zones → hatch pets with multipliers → rebirth. Key details: zone gates, pet-merging, a big final zone to aspire to.

**Tycoon:** Claim a plot → droppers make money → buy buttons build the base step by step → unlock bigger machines → PvP or showing off. Key details: satisfying building animations and a clear "next button" glow.

**Horror co-op:** 2 to 6 friends → explore a map with objectives → a monster AI with clear rules → escalating tension → escape. Key details: audio design, a proximity voice/chat vibe, and randomized events for replay. Make it clip-worthy.

**Anime battlegrounds:** Pick a character with 4 moves and an ultimate → arena free-for-all → kill streaks. Key details: VFX, hit-stop, combo feel, and server-authoritative hit detection. Only attempt this with strong scripting and VFX skills.

**Obby:** Stages with checkpoints → skips for Robux → a trail/cosmetic shop → leaderboards. Key details: a clear difficulty curve and a creative theme. Best for first-time developers.

**Roleplay:** A town with houses, jobs, and vehicles → avatar and house customization → events. Key details: needs lots of content and polish, but it's the stickiest genre.

---

## 8. Sources (for this snapshot)
- Live player counts: Rokoala, GGAID, Robipedia trackers (Sept–Oct 2026)
- Wikipedia: *List of Roblox games*, *Steal a Brainrot*, *Adopt Me!*
- Roblox Q2 2026 shareholder letter; Roblox newsroom, "Optimizing Discovery" (June 2026); DevForum, "Boost Your Discovery…" (Aug 20, 2026)
- Roblox newsroom: DevEx +42% for 18+ (Apr 2026)
- DevForum: "Roblox Kids and Select: New Restrictions on Reward-Driven Media Feeds" (Aug 25, 2026); GamesRadar, TechSpot, MassivelyOP coverage of the *Steal An Egg* removal
- Roblox Creator Docs: Analytics
- Genre trend roundups: Cubix, Game-Ace, KitsBlox, creation.dev (2026). These are third-party and lower confidence.

**Update this file monthly.** Ask Claude: "Research the current top Roblox games and trends and update my knowledge file."
