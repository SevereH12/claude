--!strict
-- Who may go where, and what to aim for next. This is the one place for
-- zone entry rules. Takes a server Profile or a client Snapshot: both carry
-- the tiers it reads. The server enforces it (Strikes, Movement, Research);
-- the client only uses it for barriers and the HUD.

local RunService = game:GetService("RunService")

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local Formulas = require(script.Parent.Formulas)

export type Progress = { bottleTier: number, bootTier: number }

export type GoalKind = "zone" | "bottle" | "boots"

export type Goal = {
	kind: GoalKind,
	title: string, -- "Vial", "Puddle Jumpers", "Mesa"
	detail: string, -- what it gives, or what it takes
	price: number, -- Volts still to spend to reach it
}

local Progression = {}

-- Roblox's Premium icon: a glyph Roblox's fonts draw in any text.
Progression.PREMIUM_ICON = utf8.char(0xE001)
-- Player attribute the Studio-only "Pretend Premium" test toggle sets
-- (Systems/DevCommands). Ignored outside Studio.
Progression.PRETEND_PREMIUM = "PretendPremium"

local PREMIUM_ONLY = `{Progression.PREMIUM_ICON} Premium members only`

-- Premium for zone entry: a real member, or in a Studio play test only, a
-- tester with Pretend Premium on. Pure, so tests can cover every case.
function Progression.isPremium(
	membership: Enum.MembershipType,
	pretend: boolean,
	inStudio: boolean
): boolean
	return membership == Enum.MembershipType.Premium or (inStudio and pretend)
end

-- The same for a live player. The server's answer is the one that counts;
-- it sends it to the client as snapshot.premium.
function Progression.playerIsPremium(player: Player): boolean
	return Progression.isPremium(
		player.MembershipType,
		player:GetAttribute(Progression.PRETEND_PREMIUM) == true,
		RunService:IsStudio()
	)
end

local function withArticle(name: string): string
	return if string.find(string.lower(name), "^[aeiou]") then `an {name}` else `a {name}`
end

local function needsBottle(zone: Types.ZoneDef): string
	return `Needs {withArticle(Formulas.bottle(zone.requiresBottle).name)}`
end

-- What a zone asks for, e.g. "Needs a Flask", or nil if it's open to all.
function Progression.requirement(zone: Types.ZoneDef): string?
	if zone.premium then
		return PREMIUM_ONLY
	elseif zone.requiresBottle > 1 then
		return needsBottle(zone)
	end
	return nil
end

-- `premium`: Progression.playerIsPremium on the server, snapshot.premium
-- on the client.
function Progression.canEnter(progress: Progress, zone: Types.ZoneDef, premium: boolean): boolean
	if zone.premium and not premium then
		return false
	end
	return progress.bottleTier >= zone.requiresBottle
end

-- Why a zone is locked for this player, or nil when they can go in.
function Progression.lockReason(progress: Progress, zone: Types.ZoneDef, premium: boolean): string?
	if zone.premium and not premium then
		return PREMIUM_ONLY
	elseif progress.bottleTier < zone.requiresBottle then
		return needsBottle(zone)
	end
	return nil
end

-- Volts one charge caught in `zone` is worth to this player. A premium
-- zone pays PREMIUM_VALUE_MULTIPLIER x the best other zone they can enter.
function Progression.boltValue(progress: Progress, zone: Types.ZoneDef): number
	if not zone.premium then
		return zone.chargeValue
	end
	local best = 0
	for _, other in Config.ZONES do
		if not other.premium and progress.bottleTier >= other.requiresBottle then
			best = math.max(best, other.chargeValue)
		end
	end
	return math.round(best * Config.PREMIUM_VALUE_MULTIPLIER)
end

-- Volts to buy every bottle after `current` up to and including `tier`.
local function bottleCost(current: number, tier: number): number
	local total = 0
	for t = current + 1, math.min(tier, #Config.BOTTLES) do
		total += Config.BOTTLES[t].price
	end
	return total
end

local KIND_ORDER: { [GoalKind]: number } = { zone = 1, bottle = 2, boots = 3 }

-- The next bottle, the next boots and the nearest zone a bottle unlocks,
-- cheapest first (a zone wins a tie: it's the bigger reward). Premium
-- zones aren't goals: Volts can't open them. Empty at the top.
function Progression.nextGoals(progress: Progress): { Goal }
	local goals: { Goal } = {}
	local bottle = Formulas.nextBottle(progress.bottleTier)
	if bottle then
		table.insert(goals, {
			kind = "bottle",
			title = bottle.name,
			detail = `Holds {bottle.capacity} charges`,
			price = bottle.price,
		})
	end
	local boots = Formulas.nextBoots(progress.bootTier)
	if boots then
		table.insert(goals, {
			kind = "boots",
			title = boots.name,
			detail = `+{boots.speedBonus} speed in storm zones`,
			price = boots.price,
		})
	end
	for _, zone in Formulas.sortedZones() do
		if not zone.premium and progress.bottleTier < zone.requiresBottle then
			local needed = Formulas.bottle(zone.requiresBottle).name
			table.insert(goals, {
				kind = "zone",
				title = zone.displayName,
				detail = `Buy {withArticle(needed)} to enter`,
				price = bottleCost(progress.bottleTier, zone.requiresBottle),
			})
			break
		end
	end
	table.sort(goals, function(a, b)
		if a.price ~= b.price then
			return a.price < b.price
		end
		return KIND_ORDER[a.kind] < KIND_ORDER[b.kind]
	end)
	return goals
end

return Progression
