--!strict
-- Bottle shop popup. One row per bottle tier; only the next tier can be
-- bought. Pressing Buy just asks the server, which checks the price itself.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local UI = require(script.Parent.Parent.Lib.UI)
local State = require(script.Parent.State)

local COLORS = UI.COLORS

type Row = { tier: number, bottle: Types.BottleDef, frame: Frame, button: TextButton }

local ShopUI = {}

local panel: Frame
local rows: { Row } = {}
local buyRemote: RemoteEvent

function ShopUI.toggle()
	UI.togglePanel(panel)
end

local function render(snapshot: Types.Snapshot)
	for _, row in rows do
		local owned = row.tier <= snapshot.bottleTier
		local isNext = row.tier == snapshot.bottleTier + 1
		if owned then
			row.button.Text = if row.tier == snapshot.bottleTier then "EQUIPPED" else "OWNED"
			UI.setEnabled(row.button, false, COLORS.green)
		elseif isNext then
			row.button.Text = `{Format.abbreviate(row.bottle.price)} ⚡`
			UI.setEnabled(row.button, snapshot.volts >= row.bottle.price, COLORS.green)
		else
			row.button.Text = "LOCKED"
			UI.setEnabled(row.button, false, COLORS.green)
		end
		-- highlight the bottle you're carrying
		local stroke = row.frame:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if row.tier == snapshot.bottleTier then COLORS.volt else COLORS.stroke
		end
	end
end

local function buildRow(list: Instance, tier: number, bottle: Types.BottleDef)
	local frame = UI.make(Instance.new("Frame"), {
		Name = bottle.name,
		LayoutOrder = tier,
		Size = UDim2.new(1, -12, 0, 0),
		BackgroundColor3 = COLORS.panelDark,
		Parent = list,
	})
	-- height follows width so rows keep their shape on any screen
	UI.make(Instance.new("UIAspectRatioConstraint"), { AspectRatio = 4.2, Parent = frame })
	UI.corner(frame, UDim.new(0.2, 0))
	UI.stroke(frame, 3)

	-- capacity badge
	local badge = UI.make(Instance.new("Frame"), {
		Name = "Badge",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.03, 0.5),
		Size = UDim2.fromScale(0.75, 0.75),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = frame,
	})
	UI.corner(badge, UDim.new(0.5, 0))
	UI.stroke(badge, 3)
	UI.gradient(badge, COLORS.storm, COLORS.stormDeep)
	local capacityText = UI.label({
		Title = true,
		Text = tostring(bottle.capacity),
		Position = UDim2.fromScale(0.12, 0.15),
		Size = UDim2.fromScale(0.76, 0.7),
		Parent = badge,
	})
	UI.maxText(capacityText, 30)

	local name = UI.label({
		Title = true,
		Text = string.upper(bottle.name),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromScale(0.25, 0.12),
		Size = UDim2.fromScale(0.42, 0.42),
		Parent = frame,
	})
	UI.maxText(name, 28)
	local capacity = UI.label({
		Text = `Holds {bottle.capacity} charges`,
		TextColor3 = COLORS.subtext,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromScale(0.25, 0.56),
		Size = UDim2.fromScale(0.42, 0.3),
		Parent = frame,
	})
	UI.maxText(capacity, 20)

	local button = UI.button({
		Name = "Buy",
		Text = "...",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.97, 0.5),
		Size = UDim2.fromScale(0.29, 0.66),
		BackgroundColor3 = COLORS.green,
		Parent = frame,
	})
	UI.maxText(button, 24)
	button.Activated:Connect(function()
		UI.pop(button)
		buyRemote:FireServer(tier)
	end)

	table.insert(rows, { tier = tier, bottle = bottle, frame = frame, button = button })
end

function ShopUI.init()
	buyRemote = Net.get("BuyBottle")

	local screenGui = UI.make(Instance.new("ScreenGui"), {
		Name = "StormBottlerShop",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	panel = UI.panel({
		Name = "ShopPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.44, 0.62),
		Visible = false,
		Parent = screenGui,
	})
	UI.sizeLimits(panel, Vector2.new(320, 280), Vector2.new(580, 520))

	local header = UI.make(Instance.new("Frame"), {
		Name = "Header",
		Size = UDim2.fromScale(1, 0.15),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = panel,
	})
	UI.corner(header, UDim.new(0, 14))
	UI.gradient(header, COLORS.storm, COLORS.stormDeep)
	local title = UI.label({
		Title = true,
		Text = "⚡ BOTTLES",
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromScale(0.05, 0.15),
		Size = UDim2.fromScale(0.7, 0.7),
		Parent = header,
	})
	UI.maxText(title, 36)
	local close = UI.button({
		Name = "Close",
		Text = "X",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.975, 0.5),
		Size = UDim2.fromScale(0.75, 0.75),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundColor3 = COLORS.red,
		Parent = header,
	})
	close.Activated:Connect(ShopUI.toggle)

	local hint = UI.label({
		Text = "Bigger bottles hold more charges before you need to sell.",
		TextColor3 = COLORS.subtext,
		Position = UDim2.fromScale(0.05, 0.17),
		Size = UDim2.fromScale(0.9, 0.06),
		Parent = panel,
	})
	UI.maxText(hint, 18)

	local list = UI.make(Instance.new("ScrollingFrame"), {
		Name = "List",
		Position = UDim2.fromScale(0.04, 0.25),
		Size = UDim2.fromScale(0.92, 0.72),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = panel,
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
	for tier, bottle in Config.BOTTLES do
		buildRow(list, tier, bottle)
	end
end

function ShopUI.start()
	if State.current then
		render(State.current)
	end
	State.Changed:Connect(render)
end

return ShopUI
