--!strict
-- Asked once, before the player's first storm (or on join if one is on):
-- "Lightning flashes a lot in this game. Reduce flashing?" YES turns on
-- SETTINGS > Accessibility & HUD > Reduce flashing; either answer is saved
-- (flashAsked), and the setting can be changed any time.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Layout = require(script.Parent.Parent.Lib.Layout)
local SettingsStore = require(script.Parent.Parent.Lib.SettingsStore)
local UI = require(script.Parent.Parent.Lib.UI)
local Storm = require(script.Parent.Storm)

local COLORS = UI.COLORS

local FlashPrompt = {}

local panel: Frame
local asking = false

local function answer(reduce: boolean)
	SettingsStore.set("reduceFlashing", reduce)
	SettingsStore.set("flashAsked", true)
	asking = false
	UI.closePanels()
	UI.toast(
		if reduce
			then "Flashing reduced. Change it any time in SETTINGS"
			else "You can reduce flashing any time in SETTINGS",
		"info",
		4
	)
end

local function ask()
	if asking or SettingsStore.get("flashAsked") or not SettingsStore.loaded then
		return
	end
	asking = true
	UI.openPanel(panel)
end

local function onStorm(state: Types.StormState?)
	if state and state.phase == "Storm" then
		ask()
	end
end

function FlashPrompt.init()
	local _, root = Layout.screen("StormBottlerFlashPrompt", 8)
	local window =
		UI.window(root, "FlashPrompt", "⚡ BEFORE THE STORM", COLORS.storm, Vector2.new(460, 260))
	panel = window.panel
	window.close.Visible = false -- it needs an answer
	local text = UI.label({
		Text = "Lightning flashes a lot in this game. Reduce flashing?",
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 80),
		Parent = window.body,
	})
	UI.maxText(text, 24)
	for index, choice in { { "YES", true, COLORS.green }, { "NO", false, COLORS.panelTop } } do
		local button = UI.button({
			Name = choice[1],
			Text = choice[1] :: string,
			AnchorPoint = Vector2.new(if index == 1 then 0 else 1, 1),
			Position = UDim2.fromScale(if index == 1 then 0 else 1, 1),
			Size = UDim2.new(0.48, 0, 0, 56),
			BackgroundColor3 = choice[3] :: Color3,
			Parent = window.body,
		})
		UI.maxText(button, 28)
		button.Activated:Connect(function()
			answer(choice[2] :: boolean)
		end)
	end
	-- closed another way (Esc, the backdrop): ask again next storm
	panel:GetPropertyChangedSignal("Visible"):Connect(function()
		if not panel.Visible then
			asking = false
		end
	end)
end

function FlashPrompt.start()
	Storm.Changed:Connect(onStorm)
	local function check()
		onStorm(Storm.current)
	end
	if SettingsStore.loaded then
		check()
	else
		SettingsStore.Loaded:Connect(check)
	end
end

return FlashPrompt
