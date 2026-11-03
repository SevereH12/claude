--!strict
-- The LOG tab of the Research panel (Controllers/ResearchUI builds it with
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
local UI = require(script.Parent.UI)

local COLORS = UI.COLORS
local HEADING = 36
local BAR = 22
local HEADER = 44 -- a row card's top line, at least (taller when CLAIM is)
local BUTTON = 36
local TILE = Vector2.new(84, 80)
local TILE_GAP = 6
local TOAST_SECONDS = 6
local NARROW = 560 -- a page narrower than this puts a row's reward under its name

-- What a reward gives this player, as text (Lib/RewardText.describe, so
-- the LOG tab says the same as the REWARDS panel).
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
	cells: UIGridLayout,
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
local pageWidth = 0 -- the page's width at the last StormLogTab.fit
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
	-- a name of any length: two lines that shrink to fit the tile
	local caption = UI.label({
		Name = "Caption",
		Text = entry.label,
		TextColor3 = COLORS.subtext,
		TextWrapped = true,
		Position = UDim2.fromScale(0.04, 0.62),
		Size = UDim2.fromScale(0.92, 0.36),
		Parent = button,
	})
	UI.maxText(caption, 15, 9)
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
		Parent = header,
	})
	UI.maxText(title, 20, 12)
	-- what it pays can be long: two lines that shrink to fit
	local reward = UI.label({
		Name = "Reward",
		Text = "",
		TextColor3 = COLORS.subtext,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Parent = header,
	})
	UI.maxText(reward, 16, 10)
	local button = UI.button({
		Name = "Claim",
		Text = "CLAIM",
		BackgroundColor3 = COLORS.green,
		Parent = header,
	})
	UI.maxText(button, 18, 11)
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
	local cells = UI.make(Instance.new("UIGridLayout"), {
		CellSize = UDim2.fromOffset(TILE.X, TILE.Y),
		CellPadding = UDim2.fromOffset(TILE_GAP, TILE_GAP),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
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
		cells = cells,
		tiles = tiles,
	}
end

-- Lays the tab out for a page `width` wide (design pixels, the whole
-- scrolling list). Each row's top line is the name, the reward and CLAIM
-- side by side, or on a narrow page the name over the reward with CLAIM
-- beside them; CLAIM is TAP_MIN points tall on touch and the line grows to
-- fit. The entry tiles fill the card in as many columns as fit.
function StormLogTab.fit(width: number)
	pageWidth = width
	local inner = UI.listWidth(width) - 20 -- less the card's padding
	local narrow = width < NARROW
	local button = UI.tall(BUTTON)
	local _, tile = UI.columns(inner, TILE.X, TILE_GAP)
	for _, card in rowCards do
		if narrow then
			local claim = math.clamp(math.floor(inner * 0.3), 96, 150)
			local room = inner - claim - 10
			card.header.Size = UDim2.new(1, 0, 0, math.max(72, button + 8))
			card.title.AnchorPoint = Vector2.zero
			card.title.Position = UDim2.fromOffset(0, 0)
			card.title.Size = UDim2.fromOffset(room, 26)
			card.reward.TextYAlignment = Enum.TextYAlignment.Top
			card.reward.AnchorPoint = Vector2.zero
			card.reward.Position = UDim2.fromOffset(0, 28)
			card.reward.Size = UDim2.fromOffset(room, 40)
			card.button.Size = UDim2.fromOffset(claim, button)
		else
			card.header.Size = UDim2.new(1, 0, 0, math.max(HEADER, button + 8))
			card.title.AnchorPoint = Vector2.new(0, 0.5)
			card.title.Position = UDim2.fromScale(0, 0.5)
			card.title.Size = UDim2.new(0.36, 0, 0, 24)
			card.reward.TextYAlignment = Enum.TextYAlignment.Center
			card.reward.AnchorPoint = Vector2.new(0, 0.5)
			card.reward.Position = UDim2.fromScale(0.37, 0.5)
			card.reward.Size = UDim2.new(0.35, 0, 0, 36)
			card.button.Size = UDim2.new(0.26, 0, 0, button)
		end
		card.button.AnchorPoint = Vector2.new(1, 0.5)
		card.button.Position = UDim2.fromScale(1, 0.5)
		card.cells.CellSize = UDim2.fromOffset(tile, TILE.Y)
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
	UI.maxText(bonusLabel, 18, 11)
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
		UI.maxText(heading, 24, 14)
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
	if pageWidth > 0 then
		StormLogTab.fit(pageWidth)
	end
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
			then `✅ {count} / {total}  ·  +{math.round(Config.STORM_LOG.pageBonus * 100)}% Volts`
			else `{count} / {total}`
		for _, card in view.rows do
			local rowDone = StormLogRules.rowDone(card.row, found)
			local canClaim = rowDone and not claimed[card.row.id]
			local rewardText = describe(view.page.reward, snapshot)
			card.reward.Text = (string.gsub(rewardText, "\n", " · "))
			if claimed[card.row.id] then
				card.button.Text = "✅ DONE"
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
