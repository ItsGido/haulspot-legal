--!strict
-- Capsule rolls with pity (blueprint section 6.7). Pure: pass in a random function (0..1).

type Config = any -- Config/Capsules.luau

export type PityState = { PityEpic: number, PityLegendary: number }
export type RollResult = { ItemId: string, Rarity: string, PityEpic: number, PityLegendary: number }

local CapsuleRoll = {}

local ORDER = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5 }

function CapsuleRoll.RarityRank(rarity: string): number
	return ORDER[rarity] or 0
end

-- Picks a rarity by weight, but never below minRank.
local function pickRarity(config: Config, minRank: number, random: () -> number): string
	local total = 0
	for _, rarity in config.Rarities do
		if ORDER[rarity.Id] >= minRank then
			total += rarity.Weight
		end
	end
	local roll = random() * total
	local last = config.Rarities[#config.Rarities].Id
	for _, rarity in config.Rarities do
		if ORDER[rarity.Id] >= minRank then
			roll -= rarity.Weight
			if roll < 0 then
				return rarity.Id
			end
			last = rarity.Id
		end
	end
	return last
end

-- One roll. pity counts how many rolls since the last Epic+ / Legendary+.
function CapsuleRoll.Roll(config: Config, pity: PityState, random: () -> number): RollResult
	local minRank = 1
	if pity.PityLegendary + 1 >= config.PityLegendary then
		minRank = ORDER.Legendary
	elseif pity.PityEpic + 1 >= config.PityEpic then
		minRank = ORDER.Epic
	end

	local rarity = pickRarity(config, minRank, random)
	local candidates = {}
	for _, item in config.Pool do
		if item.Rarity == rarity then
			table.insert(candidates, item)
		end
	end
	assert(#candidates > 0, "capsule pool has no items of rarity " .. rarity)
	local item = candidates[math.clamp(math.floor(random() * #candidates) + 1, 1, #candidates)]

	local rank = ORDER[rarity]
	return {
		ItemId = item.Id,
		Rarity = rarity,
		PityEpic = if rank >= ORDER.Epic then 0 else pity.PityEpic + 1,
		PityLegendary = if rank >= ORDER.Legendary then 0 else pity.PityLegendary + 1,
	}
end

-- Rolls until a guarantee: how many rolls are left before Epic+ / Legendary+ is certain.
function CapsuleRoll.RollsUntilGuarantee(config: Config, pity: PityState): (number, number)
	return config.PityEpic - pity.PityEpic, config.PityLegendary - pity.PityLegendary
end

return CapsuleRoll
