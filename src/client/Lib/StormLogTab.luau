--!strict
-- The LOG tab of the REWARDS panel (Controllers/RewardsUI builds it with
-- StormLogTab.build and calls StormLogTab.render): the Storm Log, a
-- collection book (the rules are Util/StormLog).
--   * a line at the top: the Volts bonus from finished pages
--   * each page: its heading, a progress bar ("12 / 36") and its rows
--   * each row: a card with its name, its reward and CLAIM once every entry
--     is found, over a grid of entry tiles. A found entry shows its icon; a
--     missing one shows a grey "?" (tap any tile to see how to find it)
-- CLAIM only asks (ClaimLogRow); Systems/StormLog decides. A new entry and
-- a finished row each bring a toast.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local StormLogRules = require(ReplicatedStorage.Shared.Util.StormLog)
local Types = require(ReplicatedStorage.Shared.Types)
local Layout = require(script.Parent.Layout)
local LayoutMath = require(script.Parent.LayoutMath)
local UI = require(script.Parent.UI)

local COLORS = UI.COLORS
local HEADING = 36
local BAR = 22
local HEADER = 44 -- a row card's top line, at least (taller when CLAIM is)
local BUTTON = 36
local TILE = Vector2.new(84, 80)
local TOAST_SECONDS = 6

-- What a reward gives this player, as text (RewardsUI's describe, so the
-- LOG tab says the same as the other tabs).
export type Describe = (reward: Types.Reward, snapshot: Types.Snapshot) -> (string, number)

type Tile = {
	entry: StormLogRules.Entry,
	button: TextButton,
	icon: TextLabel,
	caption: TextLabel,
	stroke: UIStroke,
}

type RowCard = {
	row: StormLogRules.Row,
	frame: Frame,
	header: Frame,
	title: TextLabel,
	reward: TextLabel,
	button: TextButton,
	stroke: UIStroke,
	tiles: { Tile },
}

type PageView = {
	page: StormLogRules.Page,
	heading: TextLabel,
	bar: UI.Bar,
	count: TextLabel,
	rows: { RowCard },
}

local StormLogTab = {}

local bonusLabel: TextLabel
local pageViews: { PageView } = {}
local rowCards: { RowCard } = {}
local openTab: () -> () = function() end
-- what was found and finished at the last render (for the toasts)
local lastFound: StormLogRules.Found? = nil
local lastDone: { [string]: boolean } = {}

-- How to find an entry (or what it is, once found), as a toast.
local function showHint(tile: Tile, found: boolean)
	local entry = tile.entry
	if found then
		UI.toast(`{entry.icon} {entry.label}: found!`, "good", 3)
	else
		UI.toast(`❓ {entry.hint}`, "info", 4)
	end
end

local foundNow: StormLogRules.Found = {}

local function buildTile(parent: Instance, order: number, entry: StormLogRules.Entry): Tile
	local button = UI.make(Instance.new("TextButton"), {
		Name = entry.id,
		LayoutOrder = order,
		Text = "",
		AutoButtonColor = true,
		BackgroundColor3 = COLORS.panelBottom,
		Parent = parent,
	})
	UI.corner(button, UDim.new(0, 10))
	local stroke = UI.stroke(button, 2)
	local icon = UI.label({
		Name = "Icon",
		Text = "?",
		Position = UDim2.fromScale(0.1, 0.06),
		Size = UDim2.fromScale(0.8, 0.56),
		Parent = button,
	})
	local caption = UI.label({
		Name = "Caption",
		Text = entry.label,
		TextColor3 = COLORS.subtext,
		Position = UDim2.fromScale(0.05, 0.64),
		Size = UDim2.fromScale(0.9, 0.32),
		Parent = button,
	})
	UI.maxText(caption, 14)
	local tile: Tile = {
		entry = entry,
		button = button,
		icon = icon,
		caption = caption,
		stroke = stroke,
	}
	UI.clickSound(button, true)
	button.Activated:Connect(function()
		UI.pop(button)
		showHint(tile, foundNow[entry.id] == true)
	end)
	return tile
end

local function buildRow(parent: Instance, order: number, row: StormLogRules.Row): RowCard
	local frame, stroke = UI.card({
		Name = row.id,
		LayoutOrder = order,
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	})
	UI.make(Instance.new("UIListLayout"), {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = frame,
	})
	local header = UI.make(Instance.new("Frame"), {
		Name = "Header",
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, HEADER),
		Parent = frame,
	})
	local title = UI.label({
		Title = true,
		Name = "Title",
		Text = row.label,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.36, 0, 0, 24),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Parent = header,
	})
	UI.maxText(title, 20)
	local reward = UI.label({
		Name = "Reward",
		Text = "",
		TextColor3 = COLORS.subtext,
		TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.37, 0, 0.5, 0),
		Size = UDim2.new(0.35, 0, 0, 22),
		Parent = header,
	})
	UI.maxText(reward, 15)
	local button = UI.button({
		Name = "Claim",
		Text = "CLAIM",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.new(0.26, 0, 0, BUTTON),
		BackgroundColor3 = COLORS.green,
		Parent = header,
	})
	UI.maxText(button, 18)
	button.Activated:Connect(function()
		if button.AutoButtonColor then
			UI.pop(button)
			Net.get("ClaimLogRow"):FireServer(row.id)
		end
	end)
	local grid = UI.make(Instance.new("Frame"), {
		Name = "Entries",
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = frame,
	})
	UI.make(Instance.new("UIGridLayout"), {
		CellSize = UDim2.fromOffset(TILE.X, TILE.Y),
		CellPadding = UDim2.fromOffset(6, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	local tiles: { Tile } = {}
	for index, entry in row.entries do
		table.insert(tiles, buildTile(grid, index, entry))
	end
	return {
		row = row,
		frame = frame,
		header = header,
		title = title,
		reward = reward,
		button = button,
		stroke = stroke,
		tiles = tiles,
	}
end

-- CLAIM is TAP_MIN points tall on touch; the row's top line grows to fit.
local function fit()
	local button = LayoutMath.tapMin(Layout.class, Layout.scale, Vector2.new(0, BUTTON)).Y
	for _, card in rowCards do
		card.header.Size = UDim2.new(1, 0, 0, math.max(HEADER, button + 8))
		card.button.Size = UDim2.new(0.26, 0, 0, button)
	end
end

-- Builds the tab into `parent` (a scrolling column with a UIListLayout).
-- `onOpen` shows the LOG tab (a toast's OPEN / CLAIM).
function StormLogTab.build(parent: ScrollingFrame, onOpen: () -> ())
	openTab = onOpen
	bonusLabel = UI.label({
		Name = "Bonus",
		LayoutOrder = 1,
		Text = "",
		TextColor3 = COLORS.volt,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 44),
		Parent = parent,
	})
	UI.maxText(bonusLabel, 18)
	local order = 1
	for _, page in StormLogRules.pages() do
		order += 1
		local heading = UI.label({
			Title = true,
			Name = `{page.id}Heading`,
			LayoutOrder = order,
			Text = `{page.icon} {page.title}`,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Bottom,
			Size = UDim2.new(1, 0, 0, HEADING),
			Parent = parent,
		})
		UI.maxText(heading, 24)
		order += 1
		local bar = UI.bar(parent, {
			Name = `{page.id}Progress`,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, BAR),
			color = COLORS.volt,
			text = 15,
		})
		local view: PageView = {
			page = page,
			heading = heading,
			bar = bar,
			count = bar.label :: TextLabel,
			rows = {},
		}
		for _, row in page.rows do
			order += 1
			local card = buildRow(parent, order, row)
			table.insert(view.rows, card)
			table.insert(rowCards, card)
		end
		table.insert(pageViews, view)
	end
	UI.onLayout(fit)
end

-- The toasts: new entries (one toast, however many) and finished rows.
local function toasts(found: StormLogRules.Found, claimed: { [string]: boolean })
	local previous = lastFound
	lastFound = found
	if not previous then
		-- the first render: what was found before this visit isn't news
		for _, card in rowCards do
			lastDone[card.row.id] = StormLogRules.rowDone(card.row, found)
		end
		return
	end
	local newEntries: { StormLogRules.Entry } = {}
	for _, card in rowCards do
		for _, tile in card.tiles do
			if found[tile.entry.id] and not previous[tile.entry.id] then
				table.insert(newEntries, tile.entry)
			end
		end
	end
	if #newEntries == 1 then
		local entry = newEntries[1]
		UI.toast(`📖 New Storm Log entry: {entry.icon} {entry.label}`, "good", TOAST_SECONDS, {
			text = "OPEN",
			onTap = openTab,
		})
	elseif #newEntries > 1 then
		UI.toast(`📖 {#newEntries} new Storm Log entries`, "good", TOAST_SECONDS, {
			text = "OPEN",
			onTap = openTab,
		})
	end
	for _, card in rowCards do
		local done = StormLogRules.rowDone(card.row, found)
		if done and not lastDone[card.row.id] and not claimed[card.row.id] then
			UI.toast(`📖 Storm Log row complete: {card.row.label}!`, "good", TOAST_SECONDS, {
				text = "CLAIM",
				onTap = openTab,
			})
		end
		lastDone[card.row.id] = done
	end
end

-- Draws the tab from the snapshot. Returns how many rows can be claimed.
function StormLogTab.render(snapshot: Types.Snapshot, describe: Describe): number
	local found, claimed = StormLogRules.fromView(snapshot.log)
	foundNow = found
	toasts(found, claimed)
	local claimable = 0
	local pagesDone = 0
	for _, view in pageViews do
		local count, total = StormLogRules.pageProgress(view.page, found)
		local done = total > 0 and count == total
		if done then
			pagesDone += 1
		end
		view.bar.setFraction(if total > 0 then count / total else 1)
		view.bar.fill.BackgroundColor3 = if done then COLORS.green else COLORS.volt
		view.count.Text = if done
			then `✓ {count} / {total}  ·  +{math.round(Config.STORM_LOG.pageBonus * 100)}% Volts`
			else `{count} / {total}`
		for _, card in view.rows do
			local rowDone = StormLogRules.rowDone(card.row, found)
			local canClaim = rowDone and not claimed[card.row.id]
			local rewardText = describe(view.page.reward, snapshot)
			card.reward.Text = (string.gsub(rewardText, "\n", " · "))
			if claimed[card.row.id] then
				card.button.Text = "✓ DONE"
				UI.setEnabled(card.button, false, COLORS.green)
			elseif canClaim then
				card.button.Text = "CLAIM"
				UI.setEnabled(card.button, true, COLORS.green)
				claimable += 1
			else
				local have, need = StormLogRules.rowProgress(card.row, found)
				card.button.Text = `{have} / {need}`
				UI.setEnabled(card.button, false, COLORS.green)
			end
			card.stroke.Color = if canClaim then COLORS.volt else COLORS.stroke
			card.stroke.Thickness = if canClaim then 5 else 3
			for _, tile in card.tiles do
				local isFound = found[tile.entry.id] == true
				tile.icon.Text = if isFound then tile.entry.icon else "?"
				tile.icon.TextColor3 = if isFound then COLORS.text else COLORS.disabled
				tile.caption.TextTransparency = if isFound then 0 else 0.45
				tile.button.BackgroundColor3 = if isFound
					then COLORS.panelTop
					else COLORS.panelBottom
				tile.stroke.Color = if isFound then COLORS.volt else COLORS.stroke
			end
		end
	end
	local bonus = StormLogRules.bonus(pagesDone)
	local each = math.round(Config.STORM_LOG.pageBonus * 100)
	bonusLabel.Text = if pagesDone > 0
		then `📖 Log bonus: +{math.round(bonus * 100)}% Volts for good ({pagesDone} of {#pageViews} pages done)`
		else `📖 Finish a page for +{each}% Volts for good. Tap a "?" to see how to find it.`
	return claimable
end

return StormLogTab
