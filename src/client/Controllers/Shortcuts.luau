--!strict
-- Keyboard and gamepad shortcuts. Only gamepad players see a hint (the "Y"
-- chip on the MENU button); PC keys just work.
--   PC:      M menu, B shop, R research, T teleport, Esc closes
--   Gamepad: Y menu (the first tile is selected), B closes

local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent.Parent.Lib.UI)
local Menu = require(script.Parent.Menu)
local ResearchUI = require(script.Parent.ResearchUI)
local ShopUI = require(script.Parent.ShopUI)
local TeleportUI = require(script.Parent.TeleportUI)

local Shortcuts = {}

-- Esc / gamepad B: the open panel first, then the menu card.
local function back()
	if not UI.closePanels() then
		Menu.close()
	end
end

-- Opens a panel straight from the keyboard (closing the menu card).
local function openFrom(open: () -> ())
	Menu.close()
	open()
end

function Shortcuts.start()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		local key = input.KeyCode
		-- letters typed into chat or a text box are not shortcuts
		local typed = if processed then nil else key
		if key == Enum.KeyCode.ButtonY or typed == Enum.KeyCode.M then
			Menu.toggle()
		elseif key == Enum.KeyCode.ButtonB or key == Enum.KeyCode.Escape then
			back()
		elseif typed == Enum.KeyCode.B then
			openFrom(ShopUI.open)
		elseif typed == Enum.KeyCode.R then
			openFrom(ResearchUI.open)
		elseif typed == Enum.KeyCode.T then
			openFrom(TeleportUI.open)
		end
	end)
end

return Shortcuts
