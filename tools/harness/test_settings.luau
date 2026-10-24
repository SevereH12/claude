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
	check(table.find(Settings.SECTIONS, def.section) ~= nil, `{def.key} is on a real tab`)
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

-- the save migration: prompt 11's sound settings carry over -------------------------
local PlayerData = world:require("ServerScriptService.Server.Systems.PlayerData")
local migrated = PlayerData.migrate({
	version = 11,
	settings = { musicVolume = 0.4, sfxVolume = 0.8, ambienceVolume = 0.2, muted = true },
})
check(migrated.version == 12, "migrated to v12")
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
