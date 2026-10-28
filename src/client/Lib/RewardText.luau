--!strict
-- What a reward gives this player, as card text, and its icon. Used by the
-- REWARDS panel (days, gifts, quests) and the Research panel's LOG tab
-- (Lib/StormLogTab), so they all say the same thing. Volts grow with the
-- player's best zone, and a boost for a pass they own says so and pays
-- Volts instead (Util/Rewards.resolve).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local BoostRules = require(ReplicatedStorage.Shared.Util.Boosts)
local PassRules = require(ReplicatedStorage.Shared.Util.Passes)
local RewardRules = require(ReplicatedStorage.Shared.Util.Rewards)
local Store = require(ReplicatedStorage.Shared.Util.Store)
local Types = require(ReplicatedStorage.Shared.Types)

local RewardText = {}

-- The text (one line per part) and the icon: a boost's pass art, or a
-- Volts pack's (bigger reward, bigger pack).
function RewardText.describe(reward: Types.Reward, snapshot: Types.Snapshot): (string, number)
	local resolved = RewardRules.resolve(reward, snapshot.passes)
	local lines: { string } = {}
	if resolved.charges > 0 then
		table.insert(lines, `+{Format.abbreviate(Store.volts(resolved.charges, snapshot))} ⚡`)
	end
	for _, boost in resolved.boosts do
		local def = BoostRules.def(boost.key)
		if def then
			table.insert(lines, `{def.name} {boost.minutes}m`)
		end
	end
	for _, key in resolved.swapped do
		local def = BoostRules.def(key)
		local pass = if def then PassRules.def(def.pass) else nil
		if pass then
			table.insert(lines, `(you own {pass.name})`)
		end
	end
	local image = 0
	local first = resolved.boosts[1]
	if resolved.charges == 0 and first then
		local def = BoostRules.def(first.key)
		local pass = if def then PassRules.def(def.pass) else nil
		image = if pass then pass.image else 0
	else
		local size = if resolved.charges >= 1000 then 3 elseif resolved.charges >= 250 then 2 else 1
		image = Config.VOLT_PACKS[size].image
	end
	return table.concat(lines, "\n"), image
end

return RewardText
