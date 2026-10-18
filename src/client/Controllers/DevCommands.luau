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
	local screenGui = UI.make(Instance.new("ScreenGui"), {
		Name = "StormBottlerTest",
		ResetOnSpawn = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	-- under the SHOP and RESEARCH buttons
	local button = UI.button({
		Name = "TestVolts",
		Text = "TEST: 1T ⚡",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.015, 0.69),
		Size = UDim2.fromScale(0.1, 0.075),
		BackgroundColor3 = UI.COLORS.volt,
		Parent = screenGui,
	})
	UI.sizeLimits(button, Vector2.new(96, 46), Vector2.new(150, 62))
	UI.maxText(button, 22)
	button.Activated:Connect(function()
		UI.pop(button)
		devRemote:FireServer("volts")
	end)

	if not RunService:IsStudio() then
		return
	end
	local player = Players.LocalPlayer
	local premium = UI.button({
		Name = "PretendPremium",
		Text = "",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.015, 0.785),
		Size = UDim2.fromScale(0.1, 0.075),
		BackgroundColor3 = UI.COLORS.storm,
		Parent = screenGui,
	})
	UI.sizeLimits(premium, Vector2.new(96, 46), Vector2.new(150, 62))
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
