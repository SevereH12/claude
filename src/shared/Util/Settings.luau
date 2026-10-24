--!strict
-- The settings schema: every setting the SETTINGS panel shows, with its
-- kind, default, limits and tab. Pure, used by both sides: the server
-- stores only `Settings.sanitize(sent)`, and the client builds its panel
-- and reads values through Lib/SettingsStore.
--
-- Values are a flat table: { version = 1, masterVolume = 1, kb_Shop = "B", ... }.
-- A key binding is a KeyCode name ("B", "Comma", "ButtonL1") or "" (none).

local Settings = {}

Settings.VERSION = 1

export type Kind = "bool" | "slider" | "choice" | "key"
export type Device = "Keyboard" | "Controller"
export type Values = { [string]: any }

export type Def = {
	key: string,
	kind: Kind,
	default: any,
	section: string, -- the tab it's on (Settings.SECTIONS)
	label: string,
	hint: string,
	min: number?, -- slider
	max: number?,
	step: number?,
	choices: { string }?, -- choice
	device: Device?, -- key
	action: string?, -- key: the action it triggers (Settings.ACTIONS)
}

Settings.SECTIONS = { "Controls", "Sound", "Graphics", "Accessibility & HUD" }

-- The actions you can bind, in the Controls tab's order, with today's keys.
-- Close is fixed on Esc and B (controller).
export type Action = { id: string, label: string, keyboard: string, controller: string }
Settings.ACTIONS = {
	{ id = "Menu", label = "Menu", keyboard = "M", controller = "ButtonY" },
	{ id = "Shop", label = "Shop", keyboard = "B", controller = "" },
	{ id = "Research", label = "Research", keyboard = "R", controller = "" },
	{ id = "Teleport", label = "Teleport", keyboard = "T", controller = "" },
	{ id = "Boosts", label = "Boosts", keyboard = "P", controller = "" },
	{ id = "Rewards", label = "Rewards", keyboard = "G", controller = "" },
	{ id = "RemoteSell", label = "Remote Sell", keyboard = "V", controller = "ButtonL1" },
	{ id = "Settings", label = "Settings", keyboard = "Comma", controller = "" },
} :: { Action }

-- Keys that belong to Roblox or to moving, and can never be bound (Esc and
-- B on a controller always close panels; Backspace clears a binding).
Settings.RESERVED = {
	Keyboard = {
		W = "moving",
		A = "moving",
		S = "moving",
		D = "moving",
		Up = "moving",
		Down = "moving",
		Left = "moving",
		Right = "moving",
		Space = "jumping",
		LeftShift = "Roblox (shift lock)",
		RightShift = "Roblox (shift lock)",
		Slash = "chat",
		Return = "chat",
		KeypadEnter = "chat",
		Tab = "Roblox",
		Escape = "closing panels",
		Backspace = "clearing a key",
		F9 = "Roblox",
		F10 = "Roblox",
		F11 = "Roblox",
		F12 = "Roblox",
	},
	Controller = {
		ButtonA = "jumping and picking",
		ButtonB = "closing panels",
		ButtonStart = "Roblox",
		ButtonSelect = "Roblox",
		Thumbstick1 = "moving",
		Thumbstick2 = "the camera",
	},
} :: { [Device]: { [string]: string } }

-- The only names a binding may be (the server refuses anything else).
local ALLOWED: { [Device]: { [string]: boolean } } = { Keyboard = {}, Controller = {} }
for _, letter in string.split("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "") do
	ALLOWED.Keyboard[letter] = true
end
for _, name in
	{
		"Zero",
		"One",
		"Two",
		"Three",
		"Four",
		"Five",
		"Six",
		"Seven",
		"Eight",
		"Nine",
		"Comma",
		"Period",
		"Semicolon",
		"Quote",
		"LeftBracket",
		"RightBracket",
		"Minus",
		"Equals",
		"BackSlash",
		"Backquote",
		"F1",
		"F2",
		"F3",
		"F4",
		"F5",
		"F6",
		"F7",
		"F8",
	}
do
	ALLOWED.Keyboard[name] = true
end
for _, name in { "ButtonX", "ButtonY", "ButtonL1", "ButtonR1", "ButtonL2", "ButtonR2" } do
	ALLOWED.Controller[name] = true
end
for device, reserved in Settings.RESERVED do
	for name in reserved do
		ALLOWED[device][name] = nil
	end
end
Settings.ALLOWED = ALLOWED

-- How a key shows on a button hint: "B", ",", "L1".
local SHORT: { [string]: string } = {
	Comma = ",",
	Period = ".",
	Semicolon = ";",
	Quote = "'",
	LeftBracket = "[",
	RightBracket = "]",
	Minus = "-",
	Equals = "=",
	BackSlash = "\\",
	Backquote = "`",
	Zero = "0",
	One = "1",
	Two = "2",
	Three = "3",
	Four = "4",
	Five = "5",
	Six = "6",
	Seven = "7",
	Eight = "8",
	Nine = "9",
}
function Settings.keyLabel(name: string): string
	if name == "" then
		return "—"
	end
	return SHORT[name] or (string.match(name, "^Button(.+)$") or name)
end

-- The setting key for an action's binding on a device.
function Settings.bindKey(device: Device, actionId: string): string
	return (if device == "Keyboard" then "kb_" else "pad_") .. actionId
end

-- The schema, in panel order. -------------------------------------------------
local DEFS: { Def } = {}
local function add(def: Def)
	table.insert(DEFS, def)
end

for _, action in Settings.ACTIONS do
	add({
		key = Settings.bindKey("Keyboard", action.id),
		kind = "key",
		default = action.keyboard,
		section = "Controls",
		label = action.label,
		hint = "",
		device = "Keyboard",
		action = action.id,
	})
	add({
		key = Settings.bindKey("Controller", action.id),
		kind = "key",
		default = action.controller,
		section = "Controls",
		label = action.label,
		hint = "",
		device = "Controller",
		action = action.id,
	})
end

local function volume(key: string, label: string, hint: string)
	add({
		key = key,
		kind = "slider",
		default = 1,
		min = 0,
		max = 1,
		step = 0.05,
		section = "Sound",
		label = label,
		hint = hint,
	})
end
volume("masterVolume", "Master", "Everything at once")
volume("musicVolume", "Music", "The background music")
volume("sfxVolume", "Effects", "Lightning, catching, selling and rewards")
volume("ambienceVolume", "Ambience", "Wind, waves, rain and the power plant hum")
volume("uiVolume", "UI", "Button clicks, panels and messages")
add({
	key = "muted",
	kind = "bool",
	default = false,
	section = "Sound",
	label = "Mute all",
	hint = "No sound at all",
})

Settings.DEFS = DEFS

local byKey: { [string]: Def } = {}
for _, def in DEFS do
	byKey[def.key] = def
end

function Settings.def(key: string): Def?
	return byKey[key]
end

-- Every setting at its default.
function Settings.defaults(): Values
	local values: Values = { version = Settings.VERSION }
	for _, def in DEFS do
		values[def.key] = def.default
	end
	return values
end

-- A value checked against its setting: the clean value, or the default.
function Settings.clean(def: Def, value: unknown): any
	if def.kind == "bool" then
		return if typeof(value) == "boolean" then value else def.default
	elseif def.kind == "slider" then
		if typeof(value) ~= "number" or value ~= value then
			return def.default
		end
		local low, high = def.min or 0, def.max or 1
		local step = def.step or 0
		local clamped = math.clamp(value, low, high)
		if step > 0 then
			clamped = math.clamp(low + math.floor((clamped - low) / step + 0.5) * step, low, high)
		end
		return clamped
	elseif def.kind == "choice" then
		return if typeof(value) == "string" and table.find(def.choices or {}, value)
			then value
			else def.default
	else -- key
		if value == "" then
			return ""
		end
		local device = def.device or "Keyboard"
		return if typeof(value) == "string" and ALLOWED[device][value] then value else def.default
	end
end

-- A clean settings table from anything (a save, a client's request):
-- unknown keys dropped, wrong types back to their default, numbers clamped,
-- choices and keys checked against their lists, one action per key.
function Settings.sanitize(raw: unknown): Values
	local source: { [any]: any } = if typeof(raw) == "table" then raw :: any else {}
	local values: Values = { version = Settings.VERSION }
	for _, def in DEFS do
		values[def.key] = Settings.clean(def, source[def.key])
	end
	-- two actions on one key: the later one goes back to none
	for _, device in { "Keyboard", "Controller" } :: { Device } do
		local used: { [string]: boolean } = {}
		for _, action in Settings.ACTIONS do
			local key = Settings.bindKey(device, action.id)
			local name = values[key]
			if name ~= "" then
				if used[name] then
					values[key] = ""
				end
				used[name] = true
			end
		end
	end
	return values
end

-- Can this key be bound on this device? true, or false and why.
function Settings.canBind(device: Device, name: string): (boolean, string?)
	local reserved = Settings.RESERVED[device][name]
	if reserved then
		return false, `{Settings.keyLabel(name)} is for {reserved}`
	end
	if not ALLOWED[device][name] then
		return false, `{Settings.keyLabel(name)} can't be used for a shortcut`
	end
	return true, nil
end

-- Binds `name` to the action of setting `key` (or clears it with ""). Returns
-- the new values and, if another action had that key, its id: that action
-- takes this one's old key (a swap). nil values: refused (reason).
function Settings.bind(values: Values, key: string, name: string): (Values?, string?, string?)
	local def = byKey[key]
	if not def or def.kind ~= "key" then
		return nil, nil, "Not a key setting"
	end
	local device = def.device or "Keyboard"
	if name ~= "" then
		local ok, reason = Settings.canBind(device, name)
		if not ok then
			return nil, nil, reason
		end
	end
	local out = table.clone(values)
	local old = out[key]
	local swapped: string? = nil
	if name ~= "" then
		for _, action in Settings.ACTIONS do
			local other = Settings.bindKey(device, action.id)
			if other ~= key and out[other] == name then
				out[other] = old
				swapped = action.id
			end
		end
	end
	out[key] = name
	return out, swapped, nil
end

-- The settings on one tab (for "Reset this tab").
function Settings.inSection(section: string): { Def }
	local list = {}
	for _, def in DEFS do
		if def.section == section then
			table.insert(list, def)
		end
	end
	return list
end

-- The action a pressed key triggers on a device, or nil.
function Settings.actionFor(values: Values, device: Device, name: string): string?
	if name == "" then
		return nil
	end
	for _, action in Settings.ACTIONS do
		if values[Settings.bindKey(device, action.id)] == name then
			return action.id
		end
	end
	return nil
end

return Settings
