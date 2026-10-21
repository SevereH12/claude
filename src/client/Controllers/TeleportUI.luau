--!strict
-- Teleport panel (from the menu): one row per world. GO takes you to that
-- world's hub; a world you haven't unlocked shows what it needs. The
-- server checks every teleport (Systems/Travel).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Portals = require(ReplicatedStorage.Shared.Util.Portals)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local Types = require(ReplicatedStorage.Shared.Types)
local Layout = require(script.Parent.Parent.Lib.Layout)
local UI = require(script.Parent.Parent.Lib.UI)
local State = require(script.Parent.State)

local COLORS = UI.COLORS
local PURPLE = Color3.fromRGB(165, 110, 255)
local ROW_HEIGHT = 86

local player = Players.LocalPlayer

type Row = { world: Types.WorldDef, status: TextLabel, button: TextButton }

local TeleportUI = {}

local panel: Frame
local rows: { Row } = {}

function TeleportUI.open()
	UI.openPanel(panel)
end

local function render()
	local snapshot = State.current
	local here = Portals.worldOf(player).id
	for _, row in rows do
		local open = snapshot ~= nil and Progression.canEnterWorld(snapshot, row.world)
		UI.setEnabled(row.button, open, PURPLE)
		row.button.Text = if open then "GO" else "🔒"
		row.status.Text = if row.world.id == here
			then "You're here"
			elseif open then "Unlocked"
			else Progression.worldRequirement(row.world) or ""
		row.status.TextColor3 = if row.world.id == here
			then COLORS.calm
			elseif open then COLORS.subtext
			else COLORS.red
	end
end

local function buildRow(list: Instance, index: number, world: Types.WorldDef)
	local frame = UI.make(Instance.new("Frame"), {
		Name = world.id,
		LayoutOrder = index,
		Size = UDim2.new(1, -12, 0, ROW_HEIGHT),
		BackgroundColor3 = COLORS.panelDark,
		Parent = list,
	})
	UI.corner(frame, UDim.new(0, 12))
	UI.stroke(frame, 3)
	local stripe = UI.make(Instance.new("Frame"), {
		Name = "Stripe",
		Position = UDim2.fromOffset(8, 10),
		Size = UDim2.new(0, 8, 1, -20),
		BackgroundColor3 = world.color,
		Parent = frame,
	})
	UI.corner(stripe, UDim.new(0.5, 0))
	local name = UI.label({
		Title = true,
		Text = string.upper(world.displayName),
		TextColor3 = world.color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0, 26, 0, 8),
		Size = UDim2.new(0.68, -26, 0, 30),
		Parent = frame,
	})
	UI.maxText(name, 28)
	local tagline = UI.label({
		Text = world.tagline,
		TextColor3 = COLORS.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0, 26, 0, 40),
		Size = UDim2.new(0.68, -26, 0, 20),
		Parent = frame,
	})
	UI.maxText(tagline, 18)
	local status = UI.label({
		Text = "",
		TextColor3 = COLORS.subtext,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0, 26, 0, 61),
		Size = UDim2.new(0.68, -26, 0, 18),
		Parent = frame,
	})
	UI.maxText(status, 16)
	local button = UI.button({
		Name = "Go",
		Text = "GO",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.new(0.26, 0, 0, 52),
		BackgroundColor3 = PURPLE,
		Parent = frame,
	})
	UI.maxText(button, 26)
	local remote = Net.get("Teleport")
	button.Activated:Connect(function()
		local snapshot = State.current
		if snapshot and Progression.canEnterWorld(snapshot, world) then
			UI.pop(button)
			remote:FireServer(world.id)
			UI.closePanels()
			if Portals.worldOf(player).id == world.id then
				UI.toast(`Back to the {world.displayName} hub`, "good")
			end
		else
			UI.toast(
				`🔒 {world.displayName}: {Progression.worldRequirement(world) or "Locked"}`,
				"warn"
			)
		end
	end)
	table.insert(rows, { world = world, status = status, button = button })
end

function TeleportUI.init()
	local _, root = Layout.screen("StormBottlerTeleport", 5)
	local window = UI.window(
		root,
		"TeleportPanel",
		"🌀 TELEPORT",
		PURPLE,
		UDim2.fromScale(0.42, 0.6),
		Vector2.new(560, 520)
	)
	panel = window.panel
	local hint = UI.label({
		Text = "Jump to the hub of any world you've unlocked.",
		TextColor3 = COLORS.subtext,
		Size = UDim2.new(1, 0, 0, 22),
		Parent = window.body,
	})
	UI.maxText(hint, 18)
	local list = UI.make(Instance.new("ScrollingFrame"), {
		Name = "List",
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 1, -30),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = window.body,
	})
	UI.make(Instance.new("UIListLayout"), {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})
	UI.make(Instance.new("UIPadding"), {
		PaddingTop = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4),
		Parent = list,
	})
	for index, world in Config.WORLDS do
		buildRow(list, index, world)
	end
end

function TeleportUI.start()
	render()
	State.Changed:Connect(render)
	player:GetAttributeChangedSignal(Portals.WORLD_ATTRIBUTE):Connect(render)
end

return TeleportUI
