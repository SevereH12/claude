--!strict
-- The TOP tab of the REWARDS panel (Controllers/RewardsUI builds it with
-- LeaderboardTab.build): the leaderboards (Systems/Leaderboards sends
-- them on the Leaderboards remote; the rules are Util/Leaderboards).
--   * a row of buttons, one per board (All-time Volts, Bolts caught,
--     Ascension, Longest streak)
--   * "You: #7 · 1.2M ⚡" (or "You: not in the top 50 · 1.2K ⚡")
--   * the top 50: rank, avatar, name and score; your own row glows
-- The boards are read every 2 minutes, so a new score shows up within a
-- few minutes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local LeaderboardRules = require(ReplicatedStorage.Shared.Util.Leaderboards)
local Types = require(ReplicatedStorage.Shared.Types)
local Layout = require(script.Parent.Layout)
local LayoutMath = require(script.Parent.LayoutMath)
local Sfx = require(script.Parent.Sfx)
local UI = require(script.Parent.UI)

local COLORS = UI.COLORS
local BUTTON = 36
local ROW = 40
local AVATAR = 32
local RANK_COLORS = {
	Color3.fromRGB(255, 205, 60), -- gold
	Color3.fromRGB(205, 215, 230), -- silver
	Color3.fromRGB(225, 150, 90), -- bronze
}

type Row = {
	frame: Frame,
	rank: TextLabel,
	avatar: ImageLabel,
	name: TextLabel,
	value: TextLabel,
	stroke: UIStroke,
}

local LeaderboardTab = {}

local player = Players.LocalPlayer
local selected = Config.LEADERBOARDS.boards[1].key
local view: Types.LeaderboardView? = nil
local boardButtons: { [string]: TextButton } = {}
local buttonBar: Frame
local youLabel: TextLabel
local noteLabel: TextLabel
local rows: { Row } = {}

local function render()
	for key, button in boardButtons do
		UI.setEnabled(button, true, if key == selected then COLORS.volt else COLORS.panelDark)
	end
	local entries = if view then view.boards[selected] or {} else {}
	local mine = if view then view.mine[selected] or 0 else 0
	youLabel.Text = if view
		then LeaderboardRules.youText(entries, player.UserId, selected, mine)
		else "Loading the leaderboards..."
	noteLabel.Text = if view and view.test
		then "TEST DATA (Studio)"
		elseif #entries == 0 and view then "No scores yet: be the first!"
		else "Updates every few minutes"
	for index, row in rows do
		local entry = entries[index]
		row.frame.Visible = entry ~= nil
		if not entry then
			continue
		end
		row.rank.Text = `#{index}`
		row.rank.TextColor3 = RANK_COLORS[index] or COLORS.text
		row.avatar.Image = if entry.userId > 0
			then `rbxthumb://type=AvatarHeadShot&id={entry.userId}&w=48&h=48`
			else ""
		row.name.Text = entry.name
		row.value.Text = LeaderboardRules.format(selected, entry.value)
		local isMe = entry.userId == player.UserId
		row.stroke.Color = if isMe then COLORS.volt else COLORS.stroke
		row.stroke.Thickness = if isMe then 4 else 2
	end
end

local function buildRow(parent: Instance, index: number): Row
	local frame = UI.make(Instance.new("Frame"), {
		Name = `Rank{index}`,
		LayoutOrder = 10 + index,
		BackgroundColor3 = COLORS.panelDark,
		Size = UDim2.new(1, -12, 0, ROW),
		Visible = false,
		Parent = parent,
	})
	UI.corner(frame, UDim.new(0, 10))
	local stroke = UI.stroke(frame, 2)
	local rank = UI.label({
		Title = true,
		Name = "Rank",
		Text = "",
		Position = UDim2.fromOffset(6, 4),
		Size = UDim2.new(0, 44, 1, -8),
		Parent = frame,
	})
	UI.maxText(rank, 18)
	local avatar = UI.make(Instance.new("ImageLabel"), {
		Name = "Avatar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 56, 0.5, 0),
		Size = UDim2.fromOffset(AVATAR, AVATAR),
		BackgroundColor3 = COLORS.panelBottom,
		Parent = frame,
	})
	UI.corner(avatar, UDim.new(1, 0))
	local name = UI.label({
		Name = "PlayerName",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(56 + AVATAR + 8, 6),
		Size = UDim2.new(0.62, -(56 + AVATAR + 8), 1, -12),
		Parent = frame,
	})
	UI.maxText(name, 18)
	local value = UI.label({
		Title = true,
		Name = "Score",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 6),
		Size = UDim2.new(0.36, -10, 1, -12),
		Parent = frame,
	})
	UI.maxText(value, 18)
	return {
		frame = frame,
		rank = rank,
		avatar = avatar,
		name = name,
		value = value,
		stroke = stroke,
	}
end

-- The board buttons are TAP_MIN points tall on touch screens.
local function fit()
	local height = LayoutMath.tapMin(Layout.class, Layout.scale, Vector2.new(0, BUTTON)).Y
	buttonBar.Size = UDim2.new(1, -12, 0, height)
end

function LeaderboardTab.build(parent: ScrollingFrame)
	buttonBar = UI.make(Instance.new("Frame"), {
		Name = "Boards",
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -12, 0, BUTTON),
		Parent = parent,
	})
	local count = #Config.LEADERBOARDS.boards
	UI.make(Instance.new("UIGridLayout"), {
		CellSize = UDim2.new(1 / count, -6, 1, 0),
		CellPadding = UDim2.fromOffset(6, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = buttonBar,
	})
	for index, board in Config.LEADERBOARDS.boards do
		local button = UI.button({
			Name = `{board.key}Board`,
			LayoutOrder = index,
			Text = `{board.icon} {board.title}`,
			BackgroundColor3 = COLORS.panelDark,
			Parent = buttonBar,
		})
		UI.maxText(button, 16)
		button.Activated:Connect(function()
			if selected ~= board.key then
				UI.pop(button)
				Sfx.play("tab")
				selected = board.key
				render()
			end
		end)
		boardButtons[board.key] = button
	end
	UI.onLayout(fit)
	youLabel = UI.label({
		Title = true,
		Name = "You",
		LayoutOrder = 2,
		Text = "",
		TextColor3 = COLORS.volt,
		Size = UDim2.new(1, -12, 0, 30),
		Parent = parent,
	})
	UI.maxText(youLabel, 22)
	noteLabel = UI.label({
		Name = "Note",
		LayoutOrder = 3,
		Text = "",
		TextColor3 = COLORS.subtext,
		Size = UDim2.new(1, -12, 0, 20),
		Parent = parent,
	})
	UI.maxText(noteLabel, 16)
	for index = 1, Config.LEADERBOARDS.top do
		table.insert(rows, buildRow(parent, index))
	end
	render()
	Net.get("Leaderboards").OnClientEvent:Connect(function(newView: Types.LeaderboardView)
		view = newView
		render()
	end)
end

return LeaderboardTab
