--!strict
-- One layout system for every screen (the maths is in Lib/LayoutMath).
--   * Layout.class: "Phone", "Tablet", "Desktop" or "Console", from what the
--     device has (touch, keyboard, gamepad) and its screen size. It only
--     changes when the screen is resized or rotated or a gamepad comes or
--     goes; clicking or tapping never flips it (Studio's phone emulator
--     reports a mouse click as a change of input).
--   * Layout.screen(name, order): a ScreenGui inside the device safe area
--     and a `root` frame to build into, in DESIGN PIXELS: the root is
--     1/scale of the screen and a UIScale on it brings it back to full
--     size, so everything inside scales together. On a console the root
--     keeps 5% clear of the TV's edges.
--   * Layout.area: the root's size in design pixels; Layout.topbar: which
--     parts of the top row Roblox's own buttons take (the middle is free);
--     Layout.hud: where each HUD piece goes (LayoutMath.hud; the
--     tutorial's card moves the toasts: Layout.setTutorial). All update
--     with Changed.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local LayoutMath = require(script.Parent.LayoutMath)

export type DeviceClass = LayoutMath.DeviceClass

type Screen = { gui: ScreenGui, root: Frame, scale: UIScale, padding: UIPadding }

local Layout = {}

Layout.class = "Desktop" :: DeviceClass
Layout.viewport = Vector2.new(1920, 1080)
Layout.scale = 1
Layout.textLevel = 0 -- the Text size setting (Layout.setTextLevel)
Layout.portrait = false
Layout.tutorial = false -- the tutorial's step card is showing (Layout.setTutorial)
Layout.area = Vector2.new(1280, 720)
Layout.topbar = { left = 0, right = 0, height = 0 } :: LayoutMath.Topbar
Layout.hud = LayoutMath.hud("Desktop", Layout.area, Layout.topbar)
Layout.Changed = Signal.new() :: Signal.Signal<DeviceClass>

-- The text size HUD chips are sized for now (LayoutMath.chipText): the
-- HUD picks each chip's wording with it (LayoutMath.fitText).
function Layout.chipText(): number
	return LayoutMath.chipText(Layout.class, Layout.scale, Layout.textLevel)
end

local screens: { Screen } = {}
-- an empty frame filling the first screen's padded root: its size and
-- position are the area every screen builds in
local measure: Frame? = nil

local function preferredInput(): string?
	local ok, value = pcall(function()
		return (UserInputService :: any).PreferredInput
	end)
	return if ok and typeof(value) == "EnumItem" then value.Name else nil
end

local function camera(): Camera?
	return workspace.CurrentCamera
end

local function applyScreen(screen: Screen)
	local s = Layout.scale
	screen.root.Size = UDim2.fromScale(1 / s, 1 / s)
	screen.scale.Scale = s
	local edge = UDim.new(LayoutMath.edgePadding(Layout.class), 0)
	screen.padding.PaddingTop = edge
	screen.padding.PaddingBottom = edge
	screen.padding.PaddingLeft = edge
	screen.padding.PaddingRight = edge
end

-- Area, top bar and HUD from the measuring frame (or an estimate before
-- there is one). True if anything moved.
local function remeasure(): boolean
	local s = Layout.scale
	local frame = measure
	local area, origin
	if frame and frame.AbsoluteSize.X > 0 then
		area = frame.AbsoluteSize / s
		-- a position above the top bar's bottom can read negative (Roblox
		-- measures some GUI from under its bar): the screen top is 0 either way
		origin = Vector2.new(
			math.max(0, frame.AbsolutePosition.X),
			math.max(0, frame.AbsolutePosition.Y)
		)
	else
		local edge = LayoutMath.edgePadding(Layout.class)
		area = Layout.viewport * (1 - 2 * edge) / s
		origin = Layout.viewport * edge
	end
	-- Roblox's top bar: its free middle (TopbarInset) in the root's design
	-- pixels; no more than a fifth of the screen whatever it reports
	local inset = GuiService.TopbarInset
	local topbar: LayoutMath.Topbar = {
		left = math.max(0, (inset.Min.X - origin.X) / s),
		right = math.min(area.X, (inset.Max.X - origin.X) / s),
		height = math.clamp((inset.Max.Y - origin.Y) / s, 0, area.Y * 0.2),
	}
	if inset.Max.X <= inset.Min.X then
		topbar = { left = 0, right = area.X, height = 0 } -- no top bar
	end
	local old, oldBar = Layout.area, Layout.topbar
	local changed = (area - old).Magnitude > 0.5
		or math.abs(topbar.height - oldBar.height) > 0.5
		or math.abs(topbar.left - oldBar.left) > 0.5
		or math.abs(topbar.right - oldBar.right) > 0.5
	Layout.area = area
	Layout.topbar = topbar
	Layout.hud = LayoutMath.hud(Layout.class, area, topbar, Layout.tutorial, Layout.chipText())
	return changed
end

local function refresh()
	local cam = camera()
	local viewport = if cam then cam.ViewportSize else Layout.viewport
	local class = LayoutMath.classify(viewport, {
		touch = UserInputService.TouchEnabled,
		keyboard = UserInputService.KeyboardEnabled,
		gamepad = UserInputService.GamepadEnabled,
		preferred = preferredInput(),
	})
	local changed = class ~= Layout.class or viewport ~= Layout.viewport
	Layout.class = class
	Layout.viewport = viewport
	Layout.scale = LayoutMath.scale(class, viewport, Layout.textLevel)
	Layout.portrait = LayoutMath.isPortrait(viewport)
	for _, screen in screens do
		applyScreen(screen)
	end
	if remeasure() or changed then
		Layout.Changed:Fire(class)
	end
end

-- SETTINGS > Accessibility & HUD > Text size (LayoutMath.TEXT_LEVELS).
function Layout.setTextLevel(level: number)
	if level ~= Layout.textLevel then
		Layout.textLevel = level
		refresh()
		Layout.Changed:Fire(Layout.class)
	end
end

-- The tutorial's step card shows (or not): while it does, it takes the
-- toasts' place in the middle of the top and they move under it.
function Layout.setTutorial(on: boolean)
	if on ~= Layout.tutorial then
		Layout.tutorial = on
		Layout.hud = LayoutMath.hud(Layout.class, Layout.area, Layout.topbar, on, Layout.chipText())
		Layout.Changed:Fire(Layout.class)
	end
end

function Layout.isTouch(): boolean
	return LayoutMath.isTouch(Layout.class)
end

function Layout.screen(name: string, displayOrder: number): (ScreenGui, Frame)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.DisplayOrder = displayOrder
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = root
	local padding = Instance.new("UIPadding")
	padding.Parent = root
	local screen = { gui = gui, root = root, scale = scale, padding = padding }
	table.insert(screens, screen)
	applyScreen(screen)
	if not measure then
		local frame = Instance.new("Frame")
		frame.Name = "SafeArea"
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundTransparency = 1
		frame.Parent = root
		measure = frame
		local function moved()
			if remeasure() then
				Layout.Changed:Fire(Layout.class)
			end
		end
		frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(moved)
		frame:GetPropertyChangedSignal("AbsolutePosition"):Connect(moved)
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui, root
end

-- Watch what changes the class, the viewport or the top bar. Not the last
-- input type: that changes on every click in the emulator.
local watchedCamera: Camera? = nil
local function watchCamera()
	local cam = camera()
	if cam and cam ~= watchedCamera then
		watchedCamera = cam
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
	end
	refresh()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
UserInputService.GamepadConnected:Connect(refresh)
UserInputService.GamepadDisconnected:Connect(refresh)
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(function()
	if remeasure() then
		Layout.Changed:Fire(Layout.class)
	end
end)
pcall(function()
	UserInputService:GetPropertyChangedSignal("PreferredInput" :: any):Connect(refresh)
end)
watchCamera()

return Layout
