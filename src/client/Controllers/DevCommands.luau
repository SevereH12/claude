--!strict
-- TEMPORARY test buttons: one sets your Volts to 1 trillion (shown in
-- Studio or to the place's owner), one turns Pretend Premium on and off
-- (Studio only). The server (Systems/DevCommands) checks again. To remove it: delete this file and Systems/DevCommands.luau, and
-- take "DevCommand" out of Shared/Remotes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local Layout = require(script.Parent.Parent.Lib.Layout)
local LayoutMath = require(script.Parent.Parent.Lib.LayoutMath)
local UI = require(script.Parent.Parent.Lib.UI)

local DevCommands = {}

local function isOwner(): boolean
	return RunService:IsStudio()
		or (
			game.CreatorType == Enum.CreatorType.User
			and Players.LocalPlayer.UserId == game.CreatorId
		)
end

function DevCommands.init()
	if not isOwner() then
		return
	end
	local devRemote = Net.get("DevCommand")
	local _, screenGui = Layout.screen("StormBottlerTest", 1)
	-- under the MENU button (LayoutMath.hud.test: two rows)
	local button = UI.button({
		Name = "TestVolts",
		Text = "TEST: 1T ⚡",
		BackgroundColor3 = UI.COLORS.volt,
		Parent = screenGui,
	})
	UI.maxText(button, 22)
	button.Activated:Connect(function()
		UI.pop(button)
		devRemote:FireServer("volts")
	end)
	local function row(index: number): LayoutMath.Rect
		local area = Layout.hud.test
		local height = (area.h - LayoutMath.GAP) / 2
		return {
			x = area.x,
			y = area.y + (index - 1) * (height + LayoutMath.GAP),
			w = area.w,
			h = height,
		}
	end
	UI.onLayout(function()
		UI.place(button, row(1))
	end)

	if not RunService:IsStudio() then
		return
	end
	local player = Players.LocalPlayer
	local premium = UI.button({
		Name = "PretendPremium",
		Text = "",
		BackgroundColor3 = UI.COLORS.storm,
		Parent = screenGui,
	})
	UI.onLayout(function()
		UI.place(premium, row(2))
	end)
	UI.maxText(premium, 16)
	local function pretending(): boolean
		return player:GetAttribute(Progression.PRETEND_PREMIUM) == true
	end
	local function refresh()
		local state = if pretending() then "ON" else "OFF"
		premium.Text = `{Progression.PREMIUM_ICON} PRETEND: {state}`
	end
	refresh()
	player:GetAttributeChangedSignal(Progression.PRETEND_PREMIUM):Connect(refresh)
	premium.Activated:Connect(function()
		UI.pop(premium)
		devRemote:FireServer("premium", not pretending())
	end)
end

return DevCommands
