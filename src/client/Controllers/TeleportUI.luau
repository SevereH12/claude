--!strict
-- Teleport panel (from the menu): one row per world. GO takes you to that
-- world's hub; a world you haven't unlocked shows what it needs, the one
-- you're in says YOU ARE HERE (and can't be picked), and after a trip every
-- GO counts down the cooldown (Config.TELEPORT_COOLDOWN). The rule is
-- Util/Portals.teleportRefusal; the server checks every teleport
-- (Systems/Travel).

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

-- When the server says the next teleport can go (server time; 0 = now).
local function readyAt(): number
	local value = player:GetAttribute(Portals.READY_ATTRIBUTE)
	return if typeof(value) == "number" then value else 0
end

local function render()
	local snapshot = State.current
	local here = Portals.worldOf(player).id
	local wait = Portals.cooldownLeft(workspace:GetServerTimeNow(), readyAt())
	for _, row in rows do
		local world = row.world
		local isHere = world.id == here
		local locked = if snapshot
			then Progression.worldLockReason(snapshot, world)
			else Progression.worldRequirement(world)
		UI.setEnabled(row.button, not isHere and not locked and wait == 0, PURPLE)
		row.button.Selectable = not isHere
		row.button.Text = if isHere
			then "HERE"
			elseif locked then "🔒"
			elseif wait > 0 then `{wait}s`
			else "GO"
		row.status.Text = if isHere
			then "YOU ARE HERE"
			elseif locked then locked
			elseif wait > 0 then `Teleport ready in {wait}s`
			else "Unlocked"
		row.status.TextColor3 = if isHere
			then COLORS.calm
			elseif locked then COLORS.red
			else COLORS.subtext
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
		local here = Portals.worldOf(player).id
		if not snapshot or world.id == here then
			return -- YOU ARE HERE can't be picked
		end
		local now = workspace:GetServerTimeNow()
		local refusal = Portals.teleportRefusal(snapshot, world.id, here, now, readyAt())
		if refusal and Progression.worldLockReason(snapshot, world) then
			UI.toast(`🔒 {world.displayName}: {refusal}`, "warn")
		elseif refusal then
			UI.toast(`⏱ {refusal}`, "info")
		else
			UI.pop(button)
			remote:FireServer(world.id)
			UI.closePanels()
		end
	end)
	table.insert(rows, { world = world, status = status, button = button })
end

function TeleportUI.init()
	local _, root = Layout.screen("StormBottlerTeleport", 5)
	local window = UI.window(root, "TeleportPanel", "🌀 TELEPORT", PURPLE, Vector2.new(560, 440))
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
	player:GetAttributeChangedSignal(Portals.READY_ATTRIBUTE):Connect(render)
	-- the cooldown counts down while the panel is open
	while true do
		task.wait(0.5)
		if panel.Visible then
			render()
		end
	end
end

return TeleportUI
