--!strict
-- TEMPORARY test button: sets your Volts to 1 trillion. Only shown in
-- Studio or to the place's owner; the server (Systems/DevCommands) checks
-- again. To remove it: delete this file and Systems/DevCommands.luau, and
-- take "DevCommand" out of Shared/Remotes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
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
end

return DevCommands
