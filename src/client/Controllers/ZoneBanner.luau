--!strict
-- Big title card when you walk into a zone ("SHORELINE - everyone in the
-- circle catches"), and a short note when you leave it (speed boost).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Types = require(ReplicatedStorage.Shared.Types)
local Zones = require(ReplicatedStorage.Shared.Util.Zones)
local UI = require(script.Parent.Parent.Lib.UI)

local SHOW_TIME = 2.2
local FADE = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local player = Players.LocalPlayer

local ZoneBanner = {}

local banner: CanvasGroup
local title: TextLabel
local subtitle: TextLabel
local showToken = 0

local function show(text: string, subtext: string, color: Color3)
	showToken += 1
	local token = showToken
	title.Text = text
	title.TextColor3 = color
	subtitle.Text = subtext
	banner.GroupTransparency = 1
	banner.Visible = true
	TweenService:Create(banner, FADE, { GroupTransparency = 0 }):Play()
	UI.pop(banner, 1.15)
	task.delay(SHOW_TIME, function()
		if showToken == token then
			TweenService:Create(banner, FADE, { GroupTransparency = 1 }):Play()
		end
	end)
end

function ZoneBanner.init()
	local screenGui = UI.make(Instance.new("ScreenGui"), {
		Name = "ZoneBanner",
		ResetOnSpawn = false,
		DisplayOrder = 3,
		Parent = player:WaitForChild("PlayerGui"),
	})
	banner = UI.make(Instance.new("CanvasGroup"), {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.27),
		Size = UDim2.fromScale(0.5, 0.13),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screenGui,
	})
	UI.make(Instance.new("UIScale"), { Parent = banner })
	title = UI.label({
		Title = true,
		Size = UDim2.fromScale(1, 0.65),
		Parent = banner,
	})
	UI.maxText(title, 72)
	subtitle = UI.label({
		Position = UDim2.fromScale(0, 0.65),
		Size = UDim2.fromScale(1, 0.33),
		Parent = banner,
	})
	UI.maxText(subtitle, 30)
end

function ZoneBanner.start()
	local current: Types.ZoneDef? = nil
	while true do
		task.wait(0.2)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local zone = Zones.at(root.Position)
			if zone ~= current then
				if zone then
					show(string.upper(zone.displayName), zone.tagline, zone.color)
				elseif current then
					show("SPEED BOOST", "Running fast outside storm zones", UI.COLORS.calm)
				end
				current = zone
			end
		end
	end
end

return ZoneBanner
