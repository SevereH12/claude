--!strict
-- Which pack to offer when a player taps something they can't afford
-- (Controllers/TopUpUI; tools/harness/test_topup.luau tests it). Pure: no
-- Roblox services. Only packs with a real product id are offered.
--   TopUp.volts(short, progress): the Volts pack for `short` missing Volts:
--     the cheapest in Robux whose Volts (Util/Store.packVolts, which grow
--     with progress) cover it; if none does, the biggest.
--   TopUp.glints(short, rank): the same for a promotion to `rank`, from
--     the Glint packs of tier `rank` (Glints of that tier always count).
-- Both take the packs to choose from last (Config's by default), so the
-- tests can try packs with no product id.

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local Progression = require(script.Parent.Progression)
local Store = require(script.Parent.Store)

local TopUp = {}

-- A pack to choose from: what it gives this player and its Robux price.
type Option<T> = { pack: T, amount: number, price: number }

-- From `candidates`, the cheapest whose amount covers `short` (the bigger
-- on a tie), else the biggest. nil when there are none.
local function choose<T>(candidates: { Option<T> }, short: number): T?
	local best: Option<T>? = nil
	local biggest: Option<T>? = nil
	for _, option in candidates do
		if option.amount >= short then
			if
				best == nil
				or option.price < best.price
				or (option.price == best.price and option.amount > best.amount)
			then
				best = option
			end
		end
		if biggest == nil or option.amount > biggest.amount then
			biggest = option
		end
	end
	local pick = best or biggest
	return if pick then pick.pack else nil
end

function TopUp.volts(
	short: number,
	progress: Progression.Progress,
	packs: { Types.VoltPackDef }?
): Types.VoltPackDef?
	local candidates: { Option<Types.VoltPackDef> } = {}
	for _, pack in packs or Config.VOLT_PACKS do
		if pack.productId ~= 0 then
			local amount = Store.packVolts(pack, progress)
			table.insert(candidates, { pack = pack, amount = amount, price = pack.price })
		end
	end
	return choose(candidates, short)
end

function TopUp.glints(
	short: number,
	rank: number,
	packs: { Types.GlintPackDef }?
): Types.GlintPackDef?
	local candidates: { Option<Types.GlintPackDef> } = {}
	for _, pack in packs or Config.GLINT_PACKS do
		if pack.productId ~= 0 and pack.tier == rank then
			table.insert(candidates, { pack = pack, amount = pack.glints, price = pack.price })
		end
	end
	return choose(candidates, short)
end

return TopUp
