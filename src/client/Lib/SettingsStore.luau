--!strict
-- The player's settings on the client: SettingsStore.get(key) and
-- SettingsStore.set(key, value), and SettingsStore.Changed(key, value) when
-- one changes (including when the saved ones arrive on join), so every
-- controller reacts live. Until the saved settings arrive, everything reads
-- its default (Util/Settings). Changes are sent to the server a second after
-- the last one (SaveSettings), which saves them in the profile.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Util.Settings)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local SAVE_DELAY = 1 -- seconds after the last change

local SettingsStore = {}

SettingsStore.Changed = Signal.new() :: Signal.Signal<string, any>
SettingsStore.loaded = false -- the saved settings have arrived

local values: Rules.Values = Rules.defaults()
local saveToken = 0
local saveRemote: RemoteEvent? = nil

function SettingsStore.get(key: string): any
	return values[key]
end

-- A copy of every value (for the panel's resets and for binding).
function SettingsStore.all(): Rules.Values
	return table.clone(values)
end

local function scheduleSave()
	saveToken += 1
	local mine = saveToken
	task.delay(SAVE_DELAY, function()
		if mine == saveToken then
			local remote = saveRemote or Net.get("SaveSettings")
			saveRemote = remote
			remote:FireServer(table.clone(values))
		end
	end)
end

-- Replaces every value, firing Changed for the ones that differ.
local function replace(newValues: Rules.Values, save: boolean)
	local clean = Rules.sanitize(newValues)
	local before = values
	values = clean
	for _, def in Rules.DEFS do
		if before[def.key] ~= clean[def.key] then
			SettingsStore.Changed:Fire(def.key, clean[def.key])
		end
	end
	if save then
		scheduleSave()
	end
end

-- Sets one setting (checked against the schema) and saves it soon.
function SettingsStore.set(key: string, value: any)
	local def = Rules.def(key)
	if not def then
		return
	end
	local clean = Rules.clean(def, value)
	if values[key] == clean then
		return
	end
	values[key] = clean
	SettingsStore.Changed:Fire(key, clean)
	scheduleSave()
end

-- Sets several at once (a key swap, a reset) and saves them soon.
function SettingsStore.setAll(newValues: Rules.Values)
	replace(newValues, true)
end

-- Calls `fn(value)` now and every time `key` changes.
function SettingsStore.watch(key: string, fn: (any) -> ())
	fn(values[key])
	SettingsStore.Changed:Connect(function(changed: string, value: any)
		if changed == key then
			fn(value)
		end
	end)
end

-- The saved settings, sent once by the server when you join.
task.spawn(function()
	Net.get("Settings").OnClientEvent:Connect(function(saved: unknown)
		SettingsStore.loaded = true
		replace(saved :: any, false)
	end)
end)

return SettingsStore
