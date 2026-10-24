--!strict
-- Research panel: one card per researcher with their rank stars, perk, field
-- data, a post picker, a Hire button and (at level 5) a Promote button, under
-- a line of Glints per zone tier. Hiring, posting and promoting just ask the
-- server, which re-checks everything (including that you're standing in the
-- Research Office).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Formulas = require(ReplicatedStorage.Shared.Util.Formulas)
local Net = require(ReplicatedStorage.Shared.Net)
local ResearchMath = require(ReplicatedStorage.Shared.Util.Research)
local ResearchSites = require(ReplicatedStorage.Shared.Util.ResearchSites)
local Types = require(ReplicatedStorage.Shared.Types)
local ResearcherModels = require(script.Parent.Parent.Lib.ResearcherModels)
local Celebrate = require(script.Parent.Parent.Lib.Celebrate)
local Layout = require(script.Parent.Parent.Lib.Layout)
local UI = require(script.Parent.Parent.Lib.UI)
local Researchers = require(script.Parent.Researchers)
local State = require(script.Parent.State)

local COLORS = UI.COLORS

type Card = {
	def: Types.ResearcherDef,
	index: number,
	title: TextLabel,
	level: TextLabel,
	now: TextLabel,
	next: TextLabel,
	status: TextLabel,
	fill: Frame,
	barText: TextLabel,
	hire: TextButton,
	promote: TextButton,
	posts: { [string]: TextButton },
}

local CONFIRM_SECONDS = 4 -- a second PROMOTE tap within this confirms
local TIP_TEXT =
	"Your researchers can't work here yet: catch bolts here for Glints and promote them at the Research Office."

local ResearchUI = {}

local screenGui: Frame -- the panel's Layout root
local panel: Frame
local cards: { Card } = {}
local hireRemote: RemoteEvent
local postRemote: RemoteEvent
local promoteRemote: RemoteEvent
local glintsLabel: TextLabel
local postIds: { string } = { "Office" }
local postNames: { [string]: string } = { Office = "Office" }
local knownLevels: { [string]: number } = {}
local knownRanks: { [string]: number } = {} -- for the promotion moment
local confirmUntil: { [string]: number } = {} -- role id -> os.clock() the confirm tap runs out
local lastBottleTier: number? = nil
local tipShown = false

function ResearchUI.toggle()
	UI.togglePanel(panel)
end

function ResearchUI.open()
	UI.openPanel(panel)
end

-- 2.75, 12, 0.5: at most two decimals, no trailing zeros
local function number(value: number): string
	return string.format("%g", math.floor(value * 100 + 0.5) / 100)
end

local function perkText(def: Types.ResearcherDef, level: number, rank: number): string
	local text = string.gsub(def.perk, "{v}", number(ResearchMath.perkValue(def.id, level, rank)))
	if rank > 0 then
		local percent = math.floor((ResearchMath.rankBonus(rank) - 1) * 100 + 0.5)
		text ..= ` (+{percent}% from rank {rank})`
	end
	return text
end

local function stars(rank: number): string
	return if rank > 0 then ` <font color="#FFD23C">{string.rep("★", rank)}</font>` else ""
end

local function zoneName(tier: number): string
	local zone = ResearchMath.tierZone(tier)
	return if zone then zone.displayName else `Tier {tier}`
end

-- "Shoreline Glints: 12 · Mesa Glints: 37": every tier you have any of.
local function glintsText(glints: { number }): string
	local parts = {}
	for tier = 0, ResearchMath.maxRank() do
		local count = ResearchMath.glintsOf(glints, tier)
		if count > 0 then
			table.insert(parts, `{zoneName(tier)} Glints: {Format.abbreviate(count)}`)
		end
	end
	return if #parts > 0
		then `✨ {table.concat(parts, " · ")}`
		else "✨ Glints: catch bolts in a zone to earn its Glints"
end

-- Why this researcher can't be promoted right now (nil = they can).
local function promoteBlock(
	save: Types.ResearcherSave,
	glints: { number },
	atOffice: boolean
): string?
	local ok, reason = ResearchMath.canPromote(save, glints)
	if not ok then
		return reason
	end
	return if atOffice then nil else "Visit the Research Office"
end

-- A promotion: the stars pop in, sparks, and the researcher jumps.
local function celebrate(card: Card, rank: number)
	UI.pop(card.title, 1.25)
	UI.pop(card.level, 1.25)
	Celebrate.sparks()
	Researchers.celebrate(card.def.id)
	UI.toast(`{card.def.name} is now rank {rank}! {string.rep("★", rank)}`, "volt")
end

-- The best non-premium zone your bottle opens, and whether any hired
-- researcher can work there. The first time a new bottle opens a zone none of
-- them can enter, explain Glints (once per session).
local function checkTip(snapshot: Types.Snapshot)
	local before = lastBottleTier
	lastBottleTier = snapshot.bottleTier
	if tipShown or before == nil or snapshot.bottleTier <= before then
		return
	end
	local topRank = -1
	for _, save in snapshot.researchers do
		topRank = math.max(topRank, save.rank or 0)
	end
	if topRank < 0 then
		return -- no team yet
	end
	for _, zone in Config.ZONES do
		if
			not zone.premium
			and zone.requiresBottle > before
			and zone.requiresBottle <= snapshot.bottleTier
			and ResearchMath.zoneTier(zone) > topRank
		then
			tipShown = true
			UI.toast(TIP_TEXT, "info", 8)
			return
		end
	end
end

local function inOffice(): boolean
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and root:IsA("BasePart") and ResearchSites.inOffice(root.Position)
end

local function render(snapshot: Types.Snapshot)
	local atOffice = inOffice()
	local now = workspace:GetServerTimeNow()
	local glints = snapshot.glints or {}
	glintsLabel.Text = glintsText(glints)
	checkTip(snapshot)
	for _, card in cards do
		local def = card.def
		local save = snapshot.researchers[def.id]
		local previous = Config.RESEARCHERS[card.index - 1]
		local unlocked = previous == nil or snapshot.researchers[previous.id] ~= nil

		local rank = if save then save.rank or 0 else 0
		card.title.Text = `{string.upper(`{def.name} · {def.role}`)}{stars(rank)}`
		local known = knownRanks[def.id]
		if save then
			knownRanks[def.id] = rank
			if known and rank > known then
				celebrate(card, rank)
			end
		end

		if save then
			local maxLevel = #Config.RESEARCH_LEVELS
			local nextAt = ResearchMath.nextThreshold(save.level, rank)
			card.level.Text = `Lv {save.level} / {maxLevel}`
			card.now.Text = perkText(def, save.level, rank)
			card.next.Text = if nextAt
				then `Next (Lv {save.level + 1}): {perkText(def, save.level + 1, rank)}`
				elseif rank < ResearchMath.maxRank() then `Promote for rank {rank + 1}`
				else "Max level and rank"
			card.fill.Size =
				UDim2.fromScale(if nextAt then math.clamp(save.data / nextAt, 0, 1) else 1, 1)
			card.barText.Text = if nextAt
				then `{Format.abbreviate(save.data)} / {Format.abbreviate(nextAt)} data`
				else `{Format.abbreviate(save.data)} data`
			local readyIn = (snapshot.setupUntil[def.id] or 0) - now
			card.status.Text = if save.post == "Office"
				then "At the Research Office"
				elseif
					readyIn > 0
				then `Setting up in {postNames[save.post] or save.post}... {math.ceil(
					readyIn
				)}s`
				else `Working in {postNames[save.post] or save.post}`
			card.hire.Text = "HIRED"
			UI.setEnabled(card.hire, false, COLORS.green)
			card.hire.Visible = save.level < maxLevel or rank >= ResearchMath.maxRank()
			card.promote.Visible = not card.hire.Visible
			if card.promote.Visible then
				local cost = Config.RESEARCH_PRESTIGE.glintCost[rank + 1]
				local confirming = (confirmUntil[def.id] or 0) > os.clock()
				card.promote.Text = if confirming
					then `TAP AGAIN: Lv 1, rank {rank + 1}, +{math.floor(
						Config.RESEARCH_PRESTIGE.perkBonusPerRank * 100 + 0.5
					)}% perk, works in {zoneName(rank + 1)}`
					else `PROMOTE: {cost} Glints`
				UI.setEnabled(
					card.promote,
					promoteBlock(save, glints, atOffice) == nil,
					COLORS.volt
				)
			end
		else
			card.hire.Visible = true
			card.promote.Visible = false
			card.level.Text = "Lv -"
			card.now.Text = perkText(def, 1, 0)
			card.next.Text = ""
			card.fill.Size = UDim2.fromScale(0, 1)
			card.barText.Text = "Not hired"
			card.status.Text = if not unlocked
				then `Hire {previous.name} first`
				elseif snapshot.volts < def.price then `Need {Format.abbreviate(
					def.price - snapshot.volts
				)} more ⚡`
				elseif atOffice then "Ready to hire"
				else "Hire at the Research Center"
			card.hire.Text = `{Format.abbreviate(def.price)} ⚡`
			UI.setEnabled(
				card.hire,
				unlocked and atOffice and snapshot.volts >= def.price,
				COLORS.green
			)
		end

		for postId, button in card.posts do
			local selected = save ~= nil and save.post == postId
			local zone = Config.ZONES[postId]
			local locked = zone ~= nil and not ResearchMath.canPost(rank, zone)
			button.Text = if locked
				then `🔒 {string.upper(postNames[postId])}`
				else string.upper(postNames[postId])
			UI.setEnabled(button, save ~= nil and not selected and not locked, COLORS.storm)
			if selected then
				button.BackgroundColor3 = COLORS.volt
			end
		end
	end
end

local function buildCard(list: Instance, index: number, def: Types.ResearcherDef)
	local frame = UI.make(Instance.new("Frame"), {
		Name = def.id,
		LayoutOrder = index,
		Size = UDim2.new(1, -12, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = COLORS.panelDark,
		Parent = list,
	})
	UI.corner(frame, UDim.new(0, 12))
	UI.stroke(frame, 3)
	UI.padding(frame, 8)
	UI.make(Instance.new("UIListLayout"), {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = frame,
	})

	local function row(order: number, height: number): Frame
		return UI.make(Instance.new("Frame"), {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, height),
			BackgroundTransparency = 1,
			Parent = frame,
		})
	end
	local function text(parent: Instance, props: { [string]: any }, max: number): TextLabel
		props.Parent = parent
		props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
		local label = UI.label(props)
		UI.maxText(label, max)
		return label
	end

	local titleRow = row(1, 28)
	local title = text(titleRow, {
		Title = true,
		Text = string.upper(`{def.name} · {def.role}`),
		RichText = true, -- the gold rank stars
		Size = UDim2.fromScale(0.72, 1),
	}, 24)
	local level = text(titleRow, {
		Title = true,
		Text = "Lv -",
		TextColor3 = COLORS.volt,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.26, 1),
	}, 24)

	-- portrait on the left, perk and next-level text beside it
	local portraitRow = row(2, 64)
	local portrait = UI.make(Instance.new("ViewportFrame"), {
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = COLORS.stroke,
		BackgroundTransparency = 0.4,
		Ambient = Color3.fromRGB(190, 190, 200),
		LightColor = Color3.fromRGB(255, 250, 235),
		Parent = portraitRow,
	})
	UI.corner(portrait, UDim.new(0, 8))
	local model = ResearcherModels.build(def.id)
	model.Parent = portrait
	local camera = Instance.new("Camera")
	local box, extent = model:GetBoundingBox()
	local fov = 35
	local reach = math.max(extent.X, extent.Y) / (2 * math.tan(math.rad(fov / 2)))
	camera.FieldOfView = fov
	camera.CFrame =
		CFrame.lookAt(box.Position + Vector3.new(0, 0, -(reach * 1.1 + extent.Z / 2)), box.Position)
	camera.Parent = portrait
	portrait.CurrentCamera = camera

	local now = text(portraitRow, {
		Text = "",
		Position = UDim2.new(0, 72, 0, 0),
		Size = UDim2.new(1, -72, 0.55, 0),
	}, 16)
	local next = text(portraitRow, {
		Text = "",
		TextColor3 = COLORS.subtext,
		Position = UDim2.new(0, 72, 0.55, 0),
		Size = UDim2.new(1, -72, 0.45, 0),
	}, 14)

	local bar = row(4, 18)
	bar.BackgroundTransparency = 0
	bar.BackgroundColor3 = COLORS.stroke
	UI.corner(bar, UDim.new(0.5, 0))
	local clip = UI.make(Instance.new("CanvasGroup"), {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = bar,
	})
	UI.corner(clip, UDim.new(0.5, 0))
	local fill = UI.make(Instance.new("Frame"), {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = COLORS.storm,
		BorderSizePixel = 0,
		Parent = clip,
	})
	local barText = text(bar, {
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
	}, 13)

	local status = text(row(5, 18), {
		Text = "",
		TextColor3 = COLORS.calm,
		Size = UDim2.fromScale(1, 1),
	}, 14)

	-- post picker: Office plus each zone in Config order
	local picker = UI.make(Instance.new("Frame"), {
		LayoutOrder = 6,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = frame,
	})
	UI.make(Instance.new("UIGridLayout"), {
		CellSize = UDim2.new(0.32, 0, 0, 28),
		CellPadding = UDim2.fromOffset(4, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = picker,
	})
	local posts: { [string]: TextButton } = {}
	for order, postId in postIds do
		local button = UI.button({
			Name = postId,
			Text = string.upper(postNames[postId]),
			LayoutOrder = order,
			BackgroundColor3 = COLORS.storm,
			Parent = picker,
		})
		UI.maxText(button, 16)
		button.Activated:Connect(function()
			local save = if State.current then State.current.researchers[def.id] else nil
			local zone = Config.ZONES[postId]
			if save and zone and not ResearchMath.canPost(save.rank, zone) then
				local tier = ResearchMath.zoneTier(zone)
				UI.toast(`Needs rank {tier} to work in {zone.displayName}`, "info")
			elseif save and save.post ~= postId then
				UI.pop(button)
				postRemote:FireServer(def.id, postId)
			end
		end)
		posts[postId] = button
	end

	local hire = UI.button({
		Name = "Hire",
		Text = "...",
		LayoutOrder = 7,
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = COLORS.green,
		Parent = frame,
	})
	UI.maxText(hire, 22)
	hire.Activated:Connect(function()
		local snapshot = State.current
		if snapshot and not snapshot.researchers[def.id] then
			if inOffice() then
				UI.pop(hire)
				hireRemote:FireServer(def.id)
			else
				UI.toast("Visit the Research Office to hire", "info")
			end
		end
	end)

	-- in the hire button's place once they reach level 5
	local promote = UI.button({
		Name = "Promote",
		Text = "PROMOTE",
		LayoutOrder = 8,
		Visible = false,
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = COLORS.volt,
		Parent = frame,
	})
	UI.maxText(promote, 20)
	promote.Activated:Connect(function()
		local snapshot = State.current
		local save = if snapshot then snapshot.researchers[def.id] else nil
		if not snapshot or not save then
			return
		end
		local reason = promoteBlock(save, snapshot.glints or {}, inOffice())
		if reason then
			UI.toast(reason, "info")
			return
		end
		UI.pop(promote)
		if (confirmUntil[def.id] or 0) > os.clock() then
			confirmUntil[def.id] = nil
			promoteRemote:FireServer(def.id)
		else
			confirmUntil[def.id] = os.clock() + CONFIRM_SECONDS
			render(snapshot)
			task.delay(CONFIRM_SECONDS, function()
				if State.current then
					render(State.current)
				end
			end)
		end
	end)

	table.insert(cards, {
		def = def,
		index = index,
		title = title,
		level = level,
		now = now,
		next = next,
		status = status,
		fill = fill,
		barText = barText,
		hire = hire,
		promote = promote,
		posts = posts,
	})
end

-- The server publishes "<post>:<level>:<rank>" in Research_<RoleId> on the
-- player; a rising level is a level-up (the first value we see is just
-- loading in, and a promotion's drop back to 1 is handled by render).
local function watchLevels()
	local player = Players.LocalPlayer
	for _, def in Config.RESEARCHERS do
		local name = `Research_{def.id}`
		local function check()
			local value = player:GetAttribute(name)
			local level = if typeof(value) == "string"
				then tonumber(string.match(value, "^[^:]+:(%d+)"))
				else nil
			if not level then
				return
			end
			local before = knownLevels[def.id]
			knownLevels[def.id] = level
			if before and level > before then
				UI.toast(`{def.name} reached LV {level}!`, "volt")
			end
		end
		check()
		player:GetAttributeChangedSignal(name):Connect(check)
	end
end

function ResearchUI.init()
	hireRemote = Net.get("HireResearcher")
	postRemote = Net.get("PostResearcher")
	promoteRemote = Net.get("PromoteResearcher")
	for _, zone in Formulas.sortedZones() do
		table.insert(postIds, zone.id)
		postNames[zone.id] = zone.displayName
	end

	local _, root = Layout.screen("StormBottlerResearch", 6) -- above the shop if both are open
	screenGui = root
	local window = UI.window(
		screenGui,
		"ResearchPanel",
		"🔬 STORM SOCIETY",
		COLORS.storm,
		Vector2.new(640, 560)
	)
	panel = window.panel
	local hint = UI.label({
		Text = "Hire researchers at the Research Center island, then post them at a zone.",
		TextColor3 = COLORS.subtext,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 34),
		Parent = window.body,
	})
	UI.maxText(hint, 16)
	glintsLabel = UI.label({
		Name = "Glints",
		Text = "",
		TextColor3 = COLORS.volt,
		TextWrapped = true,
		Position = UDim2.fromOffset(0, 38),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = window.body,
	})
	UI.maxText(glintsLabel, 16)

	local list = UI.make(Instance.new("ScrollingFrame"), {
		Name = "List",
		Position = UDim2.fromOffset(0, 66),
		Size = UDim2.new(1, 0, 1, -66),
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
	for index, def in Config.RESEARCHERS do
		buildCard(list, index, def)
	end
	watchLevels()
end

function ResearchUI.start()
	if State.current then
		render(State.current)
	end
	State.Changed:Connect(render)
	-- standing in the office and set-up countdowns change without a snapshot;
	-- stepping onto the Research Center doorstep opens the panel
	local wasInOffice = false
	while true do
		task.wait(0.25)
		local here = inOffice()
		if here and not wasInOffice and not panel.Visible then
			ResearchUI.toggle()
		end
		wasInOffice = here
		if panel.Visible and State.current then
			render(State.current)
		end
	end
end

return ResearchUI
