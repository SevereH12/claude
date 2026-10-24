--!strict
-- Keyboard and gamepad shortcuts, as the player has bound them (SETTINGS >
-- Controls; Util/Settings.ACTIONS has the defaults: M menu, B shop, R
-- research, T teleport, P boosts, G rewards, V Remote Sell, Comma settings;
-- Y menu and L1 Remote Sell on a gamepad). Esc and gamepad B always close.
-- Small chips on the buttons name them (UI.padHint), nothing on touch.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Rules = require(ReplicatedStorage.Shared.Util.Settings)
local SettingsStore = require(script.Parent.Parent.Lib.SettingsStore)
local UI = require(script.Parent.Parent.Lib.UI)
local BoostsUI = require(script.Parent.BoostsUI)
local HUD = require(script.Parent.HUD)
local Menu = require(script.Parent.Menu)
local ResearchUI = require(script.Parent.ResearchUI)
local RewardsUI = require(script.Parent.RewardsUI)
local SettingsUI = require(script.Parent.SettingsUI)
local ShopUI = require(script.Parent.ShopUI)
local TeleportUI = require(script.Parent.TeleportUI)

local Shortcuts = {}

-- Esc / gamepad B: the open panel first, then the menu card.
local function back()
	if not UI.closePanels() then
		Menu.close()
	end
end

-- Opens a panel straight from a shortcut (closing the menu card).
local function openFrom(open: () -> ())
	return function()
		Menu.close()
		open()
	end
end

local ACTIONS: { [string]: () -> () } = {
	Menu = Menu.toggle,
	Shop = openFrom(ShopUI.open),
	Research = openFrom(ResearchUI.open),
	Teleport = openFrom(TeleportUI.open),
	Boosts = openFrom(BoostsUI.open),
	Rewards = openFrom(RewardsUI.open),
	RemoteSell = HUD.remoteSell, -- does nothing without the Remote Sell pass
	Settings = openFrom(SettingsUI.open),
}

function Shortcuts.start()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if SettingsUI.isCapturing() then
			return -- the next key is a new binding, not a shortcut
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.ButtonB or key == Enum.KeyCode.Escape then
			back()
			return
		end
		local isPad = input.UserInputType.Name:sub(1, 7) == "Gamepad"
		-- letters typed into chat or a text box are not shortcuts (gamepad
		-- buttons always are)
		if processed and not isPad then
			return
		end
		local values = SettingsStore.all()
		local action = Rules.actionFor(values, if isPad then "Controller" else "Keyboard", key.Name)
		local run = action and ACTIONS[action]
		if run then
			run()
		end
	end)
end

return Shortcuts
