--!strict
-- Keyboard and gamepad shortcuts for the panels (the HUD buttons show them
-- as key hints, UI.keyHint):
--   PC:      B shop, R research, Esc closes an open panel
--   Gamepad: Y shop, X research, B closes an open panel

local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent.Parent.Lib.UI)
local ResearchUI = require(script.Parent.ResearchUI)
local ShopUI = require(script.Parent.ShopUI)

local Shortcuts = {}

function Shortcuts.start()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		local key = input.KeyCode
		-- letters typed into chat or a text box are not shortcuts
		if key == Enum.KeyCode.B and not processed or key == Enum.KeyCode.ButtonY then
			ShopUI.toggle()
		elseif key == Enum.KeyCode.R and not processed or key == Enum.KeyCode.ButtonX then
			ResearchUI.toggle()
		elseif key == Enum.KeyCode.Escape or key == Enum.KeyCode.ButtonB then
			UI.closePanels()
		end
	end)
end

return Shortcuts
