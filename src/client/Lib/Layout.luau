--!strict
-- One layout system for every screen (the maths is in Lib/LayoutMath).
--   * Layout.class: "Phone", "Tablet", "Desktop" or "Console", from the
--     viewport and the input; Layout.Changed fires when it or the viewport
--     changes (rotate, resize, plug in a gamepad).
--   * Layout.screen(name, order): a ScreenGui inside the device safe area
--     with one UIScale, and a full-size `root` frame to build into. The root
--     keeps clear of Roblox's top bar and, on a console, of the outer 5% of
--     the TV.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local LayoutMath = require(script.Parent.LayoutMath)

export type DeviceClass = LayoutMath.DeviceClass

type Screen = { gui: ScreenGui, scale: UIScale, padding: UIPadding, clearTop: boolean }

local Layout = {}

Layout.class = "Desktop" :: DeviceClass
Layout.viewport = Vector2.new(1920, 1080)
Layout.scale = 1
Layout.portrait = false
Layout.Changed = Signal.new() :: Signal.Signal<DeviceClass>

local screens: { Screen } = {}

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
	screen.scale.Scale = Layout.scale
	local edge = LayoutMath.edgePadding(Layout.class)
	-- the top bar's bottom edge is measured from the top of the screen, but
	-- this gui starts below the device's own inset (a notch); both are real
	-- pixels, and the root's padding is in scaled units
	local top = 0
	if screen.clearTop then
		local below = GuiService.TopbarInset.Max.Y - screen.gui.AbsolutePosition.Y
		top = math.max(0, below) / Layout.scale
	end
	screen.padding.PaddingTop = UDim.new(edge, top)
	screen.padding.PaddingBottom = UDim.new(edge, 0)
	screen.padding.PaddingLeft = UDim.new(edge, 0)
	screen.padding.PaddingRight = UDim.new(edge, 0)
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
	Layout.scale = LayoutMath.scale(class, viewport)
	Layout.portrait = LayoutMath.isPortrait(viewport)
	for _, screen in screens do
		applyScreen(screen)
	end
	if changed then
		Layout.Changed:Fire(class)
	end
end

function Layout.isTouch(): boolean
	return LayoutMath.isTouch(Layout.class)
end

-- `clearTop` (default true): keep the root below Roblox's top bar buttons.
function Layout.screen(name: string, displayOrder: number, clearTop: boolean?): (ScreenGui, Frame)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.DisplayOrder = displayOrder
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.Parent = root
	local screen = { gui = gui, scale = scale, padding = padding, clearTop = clearTop ~= false }
	table.insert(screens, screen)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	applyScreen(screen)
	-- the safe-area offset is only known once it's on screen (and on rotate)
	gui:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
		applyScreen(screen)
	end)
	return gui, root
end

-- Watch everything that changes the class or the viewport.
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
UserInputService.LastInputTypeChanged:Connect(refresh)
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(refresh)
pcall(function()
	UserInputService:GetPropertyChangedSignal("PreferredInput" :: any):Connect(refresh)
end)
watchCamera()

return Layout
