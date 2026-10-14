--!strict
-- Bottle shop popup. One row per bottle tier; only the next tier can be
-- bought. Pressing Buy just asks the server, which checks the price itself.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local UI = require(script.Parent.Parent.Lib.UI)
local State = require(script.Parent.State)

local COLORS = UI.COLORS

type Row = { tier: number, bottle: Types.BottleDef, button: TextButton }

local ShopUI = {}

local panel: Frame
local panelScale: UIScale
local openTween: Tween?
local rows: { Row } = {}
local buyRemote: RemoteEvent

function ShopUI.toggle()
	if openTween then
		openTween:Cancel()
		openTween = nil
	end
	if panel.Visible then
		panel.Visible = false
		return
	end
	panel.Visible = true
	panelScale.Scale = 0.6
	local tween = TweenService:Create(panelScale, UI.TWEEN.open, { Scale = 1 })
	openTween = tween
	tween:Play()
end

local function render(snapshot: Types.Snapshot)
	for _, row in rows do
		if row.tier <= snapshot.bottleTier then
			row.button.Text = if row.tier == snapshot.bottleTier then "Equipped" else "Owned"
			UI.setEnabled(row.button, false, COLORS.green)
		elseif row.tier == snapshot.bottleTier + 1 then
			row.button.Text = `{Format.abbreviate(row.bottle.price)} Volts`
			UI.setEnabled(row.button, snapshot.volts >= row.bottle.price, COLORS.green)
		else
			row.button.Text = "Locked"
			UI.setEnabled(row.button, false, COLORS.green)
		end
	end
end

local function buildRow(list: Instance, tier: number, bottle: Types.BottleDef)
	local frame = UI.make(Instance.new("Frame"), {
		Name = bottle.name,
		LayoutOrder = tier,
		Size = UDim2.new(1, -10, 0, 0),
		BackgroundColor3 = COLORS.panelDark,
		Parent = list,
	})
	-- height follows width so rows keep their shape on any screen
	UI.make(Instance.new("UIAspectRatioConstraint"), { AspectRatio = 4.4, Parent = frame })
	UI.corner(frame, UDim.new(0.15, 0))

	local name = UI.label({
		Text = bottle.name,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromScale(0.04, 0.1),
		Size = UDim2.fromScale(0.58, 0.44),
		Parent = frame,
	})
	UI.maxText(name, 28)
	local capacity = UI.label({
		Text = `Holds {bottle.capacity} charges`,
		TextColor3 = COLORS.volt,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromScale(0.04, 0.58),
		Size = UDim2.fromScale(0.58, 0.3),
		Parent = frame,
	})
	UI.maxText(capacity, 20)

	local button = UI.button({
		Name = "Buy",
		Text = "...",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.96, 0.5),
		Size = UDim2.fromScale(0.33, 0.7),
		BackgroundColor3 = COLORS.green,
		Parent = frame,
	})
	UI.maxText(button, 24)
	button.Activated:Connect(function()
		UI.pop(button)
		buyRemote:FireServer(tier)
	end)

	table.insert(rows, { tier = tier, bottle = bottle, button = button })
end

function ShopUI.init()
	buyRemote = Net.get("BuyBottle")

	local screenGui = UI.make(Instance.new("ScreenGui"), {
		Name = "StormBottlerShop",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	panel = UI.make(Instance.new("Frame"), {
		Name = "ShopPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.42, 0.6),
		BackgroundColor3 = COLORS.panel,
		Visible = false,
		Parent = screenGui,
	})
	UI.corner(panel, UDim.new(0.05, 0))
	UI.stroke(panel, 4)
	UI.sizeLimits(panel, Vector2.new(300, 260), Vector2.new(560, 500))
	panelScale = UI.make(Instance.new("UIScale"), { Parent = panel })

	local header = UI.make(Instance.new("Frame"), {
		Name = "Header",
		Size = UDim2.fromScale(1, 0.16),
		BackgroundColor3 = COLORS.storm,
		Parent = panel,
	})
	UI.corner(header, UDim.new(0.3, 0))
	local title = UI.label({
		Text = "Bottles",
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromScale(0.05, 0.15),
		Size = UDim2.fromScale(0.7, 0.7),
		Parent = header,
	})
	UI.maxText(title, 34)
	local close = UI.button({
		Name = "Close",
		Text = "X",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.97, 0.5),
		Size = UDim2.fromScale(0.75, 0.75),
		BackgroundColor3 = COLORS.red,
		Parent = header,
	})
	UI.make(Instance.new("UIAspectRatioConstraint"), { Parent = close })
	close.Activated:Connect(ShopUI.toggle)

	local list = UI.make(Instance.new("ScrollingFrame"), {
		Name = "List",
		Position = UDim2.fromScale(0.04, 0.2),
		Size = UDim2.fromScale(0.92, 0.76),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = panel,
	})
	UI.make(Instance.new("UIListLayout"), {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
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
