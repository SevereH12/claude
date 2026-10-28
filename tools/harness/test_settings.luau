--!nocheck
-- Settings (Util/Settings): the defaults, sanitize (unknown keys, wrong
-- types, clamping, bad choices, bad keys), the keybind rules (reserved keys,
-- the allowlist, swapping on a clash) and the v11 -> v12 save migration.
--   lune run tools/harness/test_settings.luau
local World = require("./World")

local world = World.new("src")
local Settings = world:require("ReplicatedStorage.Shared.Util.Settings")

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

-- defaults: today's keys and full volume ------------------------------------------
local defaults = Settings.defaults()
check(defaults.version == Settings.VERSION, "defaults carry the version")
local expected = {
	kb_Menu = "M",
	pad_Menu = "ButtonY",
	kb_Shop = "B",
	kb_Research = "R",
	kb_Teleport = "T",
	kb_Boosts = "P",
	kb_Rewards = "G",
	kb_RemoteSell = "V",
	pad_RemoteSell = "ButtonL1",
	kb_Settings = "Comma",
	pad_Shop = "",
}
for key, value in expected do
	check(defaults[key] == value, `default {key} = {value} (got {tostring(defaults[key])})`)
end
for _, key in { "masterVolume", "musicVolume", "sfxVolume", "ambienceVolume", "uiVolume" } do
	check(defaults[key] == 1, `default {key} is 100%`)
end
check(defaults.muted == false, "not muted by default")
for _, def in Settings.DEFS do
	check(
		table.find(Settings.SECTIONS, def.section) ~= nil or def.section == Settings.HIDDEN,
		`{def.key} is on a real tab`
	)
	check(Settings.clean(def, def.default) == def.default, `{def.key}'s default is valid`)
end

-- sanitize -------------------------------------------------------------------------
local clean = Settings.sanitize({
	hacker = 9e9, -- unknown: dropped
	musicVolume = 7, -- clamped to 1
	sfxVolume = -3, -- clamped to 0
	ambienceVolume = "loud", -- wrong type: default
	uiVolume = 0 / 0, -- NaN: default
	masterVolume = 0.33, -- rounded to the 5% step
	muted = "yes", -- wrong type: default
	kb_Shop = "K", -- fine
	kb_Research = "W", -- reserved: default
	kb_Teleport = "Hacker", -- not a key: default
	pad_Menu = "ButtonA", -- reserved: default
	pad_Shop = "ButtonX", -- fine
	kb_Boosts = "", -- cleared: fine
})
check(clean.hacker == nil, "unknown keys dropped")
check(clean.musicVolume == 1 and clean.sfxVolume == 0, "volumes clamped to 0..1")
check(clean.ambienceVolume == 1 and clean.uiVolume == 1, "wrong types and NaN back to default")
check(math.abs(clean.masterVolume - 0.35) < 1e-9, "sliders snap to their step")
check(clean.muted == false, "a bool that isn't one: default")
check(clean.kb_Shop == "K" and clean.pad_Shop == "ButtonX", "allowed keys kept")
check(clean.kb_Research == "R", "reserved key back to default")
check(clean.kb_Teleport == "T", "unknown key name back to default")
check(clean.pad_Menu == "ButtonY", "reserved controller button back to default")
check(clean.kb_Boosts == "", "a cleared binding stays cleared")
check(clean.version == Settings.VERSION, "sanitize sets the version")
check(Settings.sanitize("nonsense").kb_Menu == "M", "a non-table becomes the defaults")
local twice = Settings.sanitize({ kb_Shop = "M" }) -- Menu keeps M by default
check(twice.kb_Menu == "M" and twice.kb_Shop == "", "two actions on one key: the later loses it")

-- choices (a made-up def, as part B's will be)
local choiceDef = {
	key = "x",
	kind = "choice",
	default = "Normal",
	section = "Graphics",
	label = "",
	hint = "",
	choices = { "Normal", "Large" },
}
check(Settings.clean(choiceDef, "Large") == "Large", "a listed choice is kept")
check(Settings.clean(choiceDef, "Huge") == "Normal", "an unlisted choice: default")

-- keybind rules -------------------------------------------------------------------
for _, reserved in
	{
		"W",
		"A",
		"S",
		"D",
		"Up",
		"Space",
		"LeftShift",
		"Slash",
		"Return",
		"Tab",
		"Escape",
		"F9",
		"F12",
	}
do
	local ok, reason = Settings.canBind("Keyboard", reserved)
	check(not ok and reason ~= nil, `{reserved} is reserved`)
end
for _, reserved in
	{ "ButtonA", "ButtonB", "ButtonStart", "ButtonSelect", "Thumbstick1", "Thumbstick2" }
do
	check(not Settings.canBind("Controller", reserved), `{reserved} is reserved`)
end
check(Settings.canBind("Keyboard", "K"), "K can be bound")
check(Settings.canBind("Keyboard", "Comma"), "Comma can be bound")
check(not Settings.canBind("Keyboard", "ButtonX"), "a controller button isn't a keyboard key")
check(not Settings.canBind("Controller", "K"), "a keyboard key isn't a controller button")
check(not Settings.canBind("Keyboard", "LeftControl"), "keys off the allowlist are refused")

local values = Settings.defaults()
local bound, swapped = Settings.bind(values, "kb_Shop", "K")
check(bound and bound.kb_Shop == "K" and swapped == nil, "Shop rebinds to K")
check(Settings.actionFor(bound, "Keyboard", "K") == "Shop", "K now opens the shop")
check(Settings.actionFor(bound, "Keyboard", "B") == nil, "B no longer does")
local swappedValues, other = Settings.bind(values, "kb_Shop", "R")
check(other == "Research", "taking Research's key reports the swap")
check(
	swappedValues.kb_Shop == "R" and swappedValues.kb_Research == "B",
	"the two actions swap keys"
)
local refused, _, reason = Settings.bind(values, "kb_Shop", "W")
check(refused == nil and reason ~= nil, "binding a reserved key is refused with a reason")
local cleared = Settings.bind(values, "kb_Shop", "")
check(cleared.kb_Shop == "", "an empty name clears the binding")
local padBound, padSwap = Settings.bind(values, "pad_Shop", "ButtonY")
check(
	padSwap == "Menu" and padBound.pad_Menu == "" and padBound.pad_Shop == "ButtonY",
	"controller swap: Menu gets Shop's old (none)"
)
check(Settings.actionFor(values, "Controller", "ButtonL1") == "RemoteSell", "L1 is Remote Sell")
check(
	Settings.keyLabel("Comma") == ","
		and Settings.keyLabel("ButtonL1") == "L1"
		and Settings.keyLabel("") == "—",
	"key labels"
)

-- graphics presets ------------------------------------------------------------------
local presetTable = {
	Low = { 0.25, "Off", false, 0, "Near", "Off", "Hidden" },
	Medium = { 0.6, "Soft", true, 0.5, "Far", "Simple", "My sites" },
	High = { 1, "Full", true, 1, "All", "Full", "All" },
}
for name, row in presetTable do
	local picked = Settings.change(Settings.defaults(), "graphicsPreset", name)
	check(picked.graphicsPreset == name, `choosing {name} keeps {name}`)
	for index, key in Settings.PRESET_KEYS do
		check(
			picked[key] == row[index],
			`{name}: {key} = {tostring(row[index])} (got {tostring(picked[key])})`
		)
		check(
			Settings.clean(Settings.def(key), row[index]) == row[index],
			`{name}'s {key} is a valid value`
		)
	end
end
local low = Settings.change(Settings.defaults(), "graphicsPreset", "Low")
local custom = Settings.change(low, "shadows", true)
check(
	custom.graphicsPreset == "Custom" and custom.shadows == true,
	"changing one graphics setting makes it Custom"
)
check(custom.glow == "Off", "and keeps the rest of the preset")
local fov = Settings.change(low, "fieldOfView", 80)
check(
	fov.graphicsPreset == "Low" and fov.fieldOfView == 80,
	"field of view isn't part of the preset"
)
local same = Settings.change(low, "shadows", false)
check(same.graphicsPreset == "Low", "setting a value it already has doesn't make it Custom")
check(Settings.sanitize({ fieldOfView = 200 }).fieldOfView == 90, "field of view clamps to 90")
check(Settings.decorRange("Near") == 250 and Settings.decorRange("Far") == 500, "decoration ranges")
check(Settings.decorRange("All") == math.huge, "All hides nothing")

-- starting preset by device (and one step lower on a low Roblox graphics level)
check(Settings.devicePreset("Phone", 0) == "Low", "phone: Low")
check(Settings.devicePreset("Tablet", 0) == "Medium", "tablet: Medium")
check(Settings.devicePreset("Desktop", 0) == "High", "PC: High")
check(Settings.devicePreset("Console", 0) == "High", "console: High")
check(Settings.devicePreset("Desktop", 3) == "Medium", "PC on Roblox graphics 3: Medium")
check(Settings.devicePreset("Tablet", 2) == "Low", "tablet on Roblox graphics 2: Low")
check(Settings.devicePreset("Phone", 1) == "Low", "a phone can't go lower than Low")
check(Settings.devicePreset("Desktop", 4) == "High", "Roblox graphics 4 or more: no step down")
check(Settings.devicePreset("Desktop", 10) == "High", "Roblox graphics 10: High")

-- accessibility defaults
local d = Settings.defaults()
check(
	d.reduceFlashing == false and d.cameraShake == 1 and d.colourblind == "Off",
	"accessibility defaults"
)
check(
	d.textSize == "Normal" and d.showPopups and d.showNameTags and d.showOffers,
	"HUD shows everything by default"
)
check(d.flashAsked == false and d.graphicsSet == false, "nothing asked or set yet")
check(
	Settings.sanitize({ colourblind = "Purple" }).colourblind == "Off",
	"an unknown colourblind mode: Off"
)

-- the save migration: prompt 11's sound settings carry over -------------------------
local PlayerData = world:require("ServerScriptService.Server.Systems.PlayerData")
local migrated = PlayerData.migrate({
	version = 11,
	settings = { musicVolume = 0.4, sfxVolume = 0.8, ambienceVolume = 0.2, muted = true },
})
check(migrated.version >= 12, "migrated to v12 (or a later version)")
check(
	migrated.settings.musicVolume == 0.4 and migrated.settings.muted == true,
	"old sound settings kept"
)
check(
	migrated.settings.kb_Shop == "B" and migrated.settings.uiVolume == 1,
	"new settings at their defaults"
)

if failures > 0 then
	error(`{failures} settings checks failed`)
end
print("settings checks passed")
