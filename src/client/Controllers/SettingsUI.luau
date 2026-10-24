--!strict
-- SETTINGS panel (the ⚙️ tile on the menu): Music, Effects and Ambience
-- volume sliders and a Mute all toggle. Changes apply at once (Lib/Sfx) and
-- are saved in your profile (the SaveSettings remote, Systems/Settings), so
-- they're back next time you join. Each slider can be dragged, tapped, or
-- stepped with its - and + buttons (gamepad).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local Layout = require(script.Parent.Parent.Lib.Layout)
local Sfx = require(script.Parent.Parent.Lib.Sfx)
local UI = require(script.Parent.Parent.Lib.UI)
local State = require(script.Parent.State)

local COLORS = UI.COLORS
local GREY = Color3.fromRGB(150, 155, 175)
local STEP = 0.1 -- the - and + buttons
local SAVE_DELAY = 0.5 -- seconds after the last change before saving

type Key = "musicVolume" | "sfxVolume" | "ambienceVolume"
type Slider = { key: Key, name: string, label: TextLabel, fill: Frame, knob: Frame }

local SLIDERS: { { key: Key, name: string, preview: string? } } = {
	{ key = "musicVolume", name = "🎵 MUSIC" },
	{ key = "sfxVolume", name = "🔔 EFFECTS", preview = "click" },
	{ key = "ambienceVolume", name = "🌧 AMBIENCE" },
}

local SettingsUI = {}

local panel: Frame
local saveRemote: RemoteEvent
local sliders: { Slider } = {}
local muteButton: TextButton
local current: Types.SoundSettings = table.clone(Config.SOUND_SETTINGS)
local loaded = false -- the saved settings arrived (only the first snapshot's are used)
local saveToken = 0

local function get(key: Key): number
	if key == "musicVolume" then
		return current.musicVolume
	elseif key == "sfxVolume" then
		return current.sfxVolume
	end
	return current.ambienceVolume
end

local function set(key: Key, value: number)
	if key == "musicVolume" then
		current.musicVolume = value
	elseif key == "sfxVolume" then
		current.sfxVolume = value
	else
		current.ambienceVolume = value
	end
end

function SettingsUI.open()
	UI.openPanel(panel)
end

local function render()
	for _, slider in sliders do
		local value = get(slider.key)
		slider.label.Text = `{slider.name}  {math.round(value * 100)}%`
		slider.fill.Size = UDim2.fromScale(value, 1)
		slider.knob.Position = UDim2.fromScale(value, 0.5)
		slider.fill.BackgroundColor3 = if current.muted then GREY else COLORS.storm
	end
	muteButton.Text = if current.muted then "🔇 MUTED: TAP TO UNMUTE" else "🔊 MUTE ALL"
	UI.setEnabled(muteButton, true, if current.muted then COLORS.red else COLORS.panelTop)
end

-- Applies now, saves a moment after the last change (sliders change a lot).
local function changed()
	Sfx.apply(current)
	render()
	saveToken += 1
	local mine = saveToken
	task.delay(SAVE_DELAY, function()
		if mine == saveToken then
			saveRemote:FireServer(table.clone(current))
		end
	end)
end

local function setValue(slider: Slider, value: number, preview: string?)
	local rounded = math.round(math.clamp(value, 0, 1) * 100) / 100
	if rounded == get(slider.key) then
		return
	end
	set(slider.key, rounded)
	changed()
	if preview then
		Sfx.play(preview)
	end
end

local function buildSlider(
	parent: Instance,
	order: number,
	key: Key,
	name: string,
	preview: string?
)
	local row = UI.make(Instance.new("Frame"), {
		Name = key,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 74),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local label = UI.label({
		Title = true,
		Text = name,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 28),
		Parent = row,
	})
	UI.maxText(label, 22)
	local minus = UI.button({
		Name = "Minus",
		Text = "-",
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.fromOffset(40, 36),
		BackgroundColor3 = COLORS.panelDark,
		Parent = row,
	})
	local plus = UI.button({
		Name = "Plus",
		Text = "+",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 34),
		Size = UDim2.fromOffset(40, 36),
		BackgroundColor3 = COLORS.panelDark,
		Parent = row,
	})
	-- the bar: a wide invisible hit area round a thin track
	local bar = UI.make(Instance.new("TextButton"), {
		Name = "Bar",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(56, 34),
		Size = UDim2.new(1, -112, 0, 36),
		Parent = row,
	})
	local track = UI.make(Instance.new("Frame"), {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 12),
		BackgroundColor3 = COLORS.stroke,
		Parent = bar,
	})
	UI.corner(track, UDim.new(0.5, 0))
	local fill = UI.make(Instance.new("Frame"), {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = COLORS.storm,
		BorderSizePixel = 0,
		Parent = track,
	})
	UI.corner(fill, UDim.new(0.5, 0))
	local knob = UI.make(Instance.new("Frame"), {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = COLORS.volt,
		ZIndex = 2,
		Parent = track,
	})
	UI.corner(knob, UDim.new(0.5, 0))
	UI.stroke(knob, 2)

	local slider: Slider = { key = key, name = name, label = label, fill = fill, knob = knob }
	table.insert(sliders, slider)

	local function valueAt(x: number): number
		return (x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1)
	end
	local dragging: InputObject? = nil
	bar.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			dragging = input
			setValue(slider, valueAt(input.Position.X))
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local drag = dragging
		if not drag then
			return
		end
		local kind = input.UserInputType
		if
			input == drag
			or (
				kind == Enum.UserInputType.MouseMovement
				and drag.UserInputType == Enum.UserInputType.MouseButton1
			)
		then
			setValue(slider, valueAt(input.Position.X))
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local drag = dragging
		if drag and (input == drag or input.UserInputType == drag.UserInputType) then
			dragging = nil
			if preview then
				Sfx.play(preview) -- hear the new level
			end
		end
	end)
	minus.Activated:Connect(function()
		setValue(slider, get(key) - STEP)
	end)
	plus.Activated:Connect(function()
		setValue(slider, get(key) + STEP)
	end)
end

-- The saved settings, once, when you join (after that, this panel is the
-- one that changes them).
local function onSnapshot(snapshot: Types.Snapshot)
	if loaded or not snapshot.settings then
		return
	end
	loaded = true
	current = table.clone(snapshot.settings)
	Sfx.apply(current)
	render()
end

function SettingsUI.init()
	saveRemote = Net.get("SaveSettings")
	local _, root = Layout.screen("StormBottlerSettings", 6)
	local window =
		UI.window(root, "SettingsPanel", "⚙️ SETTINGS", COLORS.panelTop, Vector2.new(460, 400))
	panel = window.panel
	UI.make(Instance.new("UIListLayout"), {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = window.body,
	})
	for order, def in SLIDERS do
		buildSlider(window.body, order, def.key, def.name, def.preview)
	end
	muteButton = UI.button({
		Name = "Mute",
		Text = "",
		LayoutOrder = #SLIDERS + 1,
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = COLORS.panelTop,
		Parent = window.body,
	})
	UI.maxText(muteButton, 22)
	muteButton.Activated:Connect(function()
		UI.pop(muteButton)
		current.muted = not current.muted
		changed()
	end)
	render()
end

function SettingsUI.start()
	if State.current then
		onSnapshot(State.current)
	end
	State.Changed:Connect(onSnapshot)
end

return SettingsUI
