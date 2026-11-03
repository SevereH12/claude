--!strict
-- Teleport panel (from the menu): one row per world. GO takes you to that
-- world's hub; a world you haven't unlocked shows what it needs, the one
-- you're in says YOU ARE HERE (and can't be picked), and after a trip every
-- GO counts down the cooldown (Config.TELEPORT_COOLDOWN). The rule is
-- Util/Portals.teleportRefusal; the server checks every teleport
-- (Systems/Travel). Under the worlds, an AFK Lounge row goes to the lounge
-- in the first world on the same cooldown (Portals.loungeRefusal).

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
local NARROW_ROW = 108 -- a row on a phone: the status gets two lines
local NARROW = 500 -- a body narrower than this (a phone held upright)

local player = Players.LocalPlayer

type Row = { world: Types.WorldDef?, status: TextLabel, button: TextButton }
-- a row's parts, for fit
type View = {
	frame: Frame,
	name: TextLabel,
	line: TextLabel,
	status: TextLabel,
	button: TextButton,
}

local TeleportUI = {}

local panel: Frame
local rows: { Row } = {}
local views: { View } = {}
local hint: TextLabel
local rowList: ScrollingFrame

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
		if not world then
			-- the AFK Lounge row
			local inLounge = snapshot ~= nil and snapshot.afk ~= nil
			UI.setEnabled(row.button, not inLounge and wait == 0, PURPLE)
			row.button.Text = if inLounge then "HERE" elseif wait > 0 then `{wait}s` else "GO"
			row.status.Text = if inLounge
				then "YOU ARE HERE"
				elseif wait > 0 then `Teleport ready in {wait}s`
				else `In {Config.WORLDS[1].displayName}`
			row.status.TextColor3 = if inLounge then COLORS.calm else COLORS.subtext
			continue
		end
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

-- A row's frame, stripe, name, tagline, status line and GO button (fit
-- places them).
local function rowFrame(
	parent: Instance,
	index: number,
	id: string,
	title: string,
	tagline: string,
	color: Color3
): (TextLabel, TextButton)
	local frame = UI.make(Instance.new("Frame"), {
		Name = id,
		LayoutOrder = index,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		BackgroundColor3 = COLORS.panelDark,
		Parent = parent,
	})
	UI.corner(frame, UDim.new(0, 12))
	UI.stroke(frame, 3)
	local stripe = UI.make(Instance.new("Frame"), {
		Name = "Stripe",
		Position = UDim2.fromOffset(8, 10),
		Size = UDim2.new(0, 8, 1, -20),
		BackgroundColor3 = color,
		Parent = frame,
	})
	UI.corner(stripe, UDim.new(0.5, 0))
	local name = UI.label({
		Title = true,
		Text = title,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	UI.maxText(name, 28, 14)
	local line = UI.label({
		Text = tagline,
		TextColor3 = COLORS.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	UI.maxText(line, 18, 11)
	-- the status can be a sentence (what a locked world needs): it wraps
	-- and shrinks to fit
	local status = UI.label({
		Text = "",
		TextColor3 = COLORS.subtext,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Parent = frame,
	})
	UI.maxText(status, 16, 10)
	local button = UI.button({
		Name = "Go",
		Text = "GO",
		BackgroundColor3 = PURPLE,
		Parent = frame,
	})
	UI.maxText(button, 26, 12)
	table.insert(views, {
		frame = frame,
		name = name,
		line = line,
		status = status,
		button = button,
	})
	return status, button
end

-- Lays the panel out for a body `size`: rows tall enough for their text
-- (two lines of status on a narrow panel), GO touch-sized at the right.
local function fit(size: Vector2)
	local narrow = size.X < NARROW
	local width = UI.listWidth(size.X)
	-- a touch screen's text can't shrink below the smallest legible size, so
	-- its status gets two lines whatever the width
	local height = if narrow or Layout.isTouch() then NARROW_ROW else ROW_HEIGHT
	local goHeight = math.min(UI.tall(52), height - 16)
	local goWidth = math.clamp(math.floor(width * 0.26), 90, 140)
	local room = width - 26 - goWidth - 24
	local hintHeight = if narrow then 2 * (math.max(UI.textSize(), 16) + 3) else 22
	hint.Size = UDim2.new(1, 0, 0, hintHeight)
	rowList.Position = UDim2.fromOffset(0, hintHeight + 8)
	rowList.Size = UDim2.new(1, 0, 1, -(hintHeight + 8))
	for _, view in views do
		view.frame.Size = UDim2.new(1, 0, 0, height)
		view.name.Position = UDim2.fromOffset(26, 8)
		view.name.Size = UDim2.fromOffset(room, 30)
		view.line.Position = UDim2.fromOffset(26, 40)
		view.line.Size = UDim2.fromOffset(room, 22)
		view.status.Position = UDim2.fromOffset(26, 62)
		view.status.Size = UDim2.fromOffset(room, height - 62 - 6)
		view.button.AnchorPoint = Vector2.new(1, 0.5)
		view.button.Position = UDim2.new(1, -12, 0.5, 0)
		view.button.Size = UDim2.fromOffset(goWidth, goHeight)
	end
end

-- The AFK Lounge row, under the worlds.
local function buildLoungeRow(list: Instance, index: number)
	local status, button = rowFrame(
		list,
		index,
		Portals.AFK_LOUNGE,
		"💤 AFK LOUNGE",
		"Earn Volts while you rest",
		Color3.fromRGB(150, 140, 255)
	)
	local remote = Net.get("Teleport")
	button.Activated:Connect(function()
		local snapshot = State.current
		if not snapshot then
			return
		end
		local refusal =
			Portals.loungeRefusal(snapshot.afk ~= nil, workspace:GetServerTimeNow(), readyAt())
		if refusal then
			UI.toast(`⏱️ {refusal}`, "info")
			return
		end
		UI.pop(button)
		remote:FireServer(Portals.AFK_LOUNGE)
		UI.closePanels()
	end)
	table.insert(rows, { world = nil, status = status, button = button })
end

local function buildRow(list: Instance, index: number, world: Types.WorldDef)
	local status, button =
		rowFrame(list, index, world.id, string.upper(world.displayName), world.tagline, world.color)
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
			UI.toast(`⏱️ {refusal}`, "info")
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
	hint = UI.label({
		Text = "Jump to the hub of any world you've unlocked.",
		TextColor3 = COLORS.subtext,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 22),
		Parent = window.body,
	})
	UI.maxText(hint, 18, 11)
	rowList = UI.list(window.body, {
		Name = "List",
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 1, -30),
		gap = 10,
	})
	for index, world in Config.WORLDS do
		buildRow(rowList, index, world)
	end
	buildLoungeRow(rowList, #Config.WORLDS + 1)
	window.onResize(fit)
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
