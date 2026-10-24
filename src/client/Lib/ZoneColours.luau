--!strict
-- A zone's colour on this screen: its own (Config.ZONES), or with
-- SETTINGS > Accessibility & HUD > Colourblind rings on, one from a
-- high-contrast set that stays apart for that kind of colour blindness.
-- Used for warning rings and the zone banner.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Shared.Util.Formulas)
local Types = require(ReplicatedStorage.Shared.Types)
local SettingsStore = require(script.Parent.SettingsStore)

-- Okabe-Ito colours (safe for red-green), and a set without blue-yellow pairs.
local SETS: { [string]: { Color3 } } = {
	["Red-green"] = {
		Color3.fromRGB(0, 114, 178), -- blue
		Color3.fromRGB(230, 159, 0), -- orange
		Color3.fromRGB(86, 180, 233), -- sky blue
		Color3.fromRGB(240, 228, 66), -- yellow
		Color3.fromRGB(213, 94, 0), -- vermillion
		Color3.fromRGB(204, 121, 167), -- reddish purple
		Color3.fromRGB(255, 255, 255), -- white
	},
	["Blue-yellow"] = {
		Color3.fromRGB(220, 40, 60), -- red
		Color3.fromRGB(0, 200, 200), -- teal
		Color3.fromRGB(255, 255, 255), -- white
		Color3.fromRGB(200, 0, 160), -- magenta
		Color3.fromRGB(120, 220, 80), -- green
		Color3.fromRGB(255, 140, 180), -- pink
		Color3.fromRGB(150, 60, 220), -- violet
	},
}

local ZoneColours = {}

local indexOf: { [string]: number } = {}
for index, zone in Formulas.sortedZones() do
	indexOf[zone.id] = index
end

-- Is a colourblind mode on? (Rings then get a dashed outline and a ⚡.)
function ZoneColours.assist(): boolean
	return SettingsStore.get("colourblind") ~= "Off"
end

function ZoneColours.of(zone: Types.ZoneDef?, fallback: Color3): Color3
	local set = SETS[SettingsStore.get("colourblind")]
	if not set or not zone then
		return if zone then zone.color else fallback
	end
	return set[((indexOf[zone.id] or 1) - 1) % #set + 1]
end

return ZoneColours
