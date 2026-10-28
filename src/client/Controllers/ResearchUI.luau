--!strict
-- RESEARCH panel, two tabs:
--   * TEAM: a strip of Glints chips (one per zone tier, in that zone's
--     colour, with a gem drawn in UI; tap one to see where those Glints
--     come from and which promotions they pay for), then one compact card
--     per researcher: portrait, name · role with rank stars, level, perk
--     now and next, the data bar, a status line, and two buttons: "📍 POST"
--     (opens the post picker) and HIRE / PROMOTE. PROMOTE shows Glint
--     progress while it's short and needs two taps to confirm.
--   * LOG: the Storm Log collection book (Lib/StormLogTab). The tab shows
--     "(n)" when n rows can be claimed, and ResearchUI.ReadyChanged tells
--     the menu (the RESEARCH dot).
-- The post picker is one overlay inside the panel, shared by every card:
-- Office, then the zones under their world's name. It closes on a pick, a
-- tap outside it, or Esc / gamepad B (Shortcuts asks closePicker first),
-- without closing the panel.
-- Hiring, posting and promoting just ask the server, which re-checks
-- everything (including that you're standing in the Research Office).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Formulas = require(ReplicatedStorage.Shared.Util.Formulas)
local Net = require(ReplicatedStorage.Shared.Net)
local ResearchMath = require(ReplicatedStorage.Shared.Util.Research)
local ResearchSites = require(ReplicatedStorage.Shared.Util.ResearchSites)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Types = require(ReplicatedStorage.Shared.Types)
local ResearcherModels = require(script.Parent.Parent.Lib.ResearcherModels)
local Celebrate = require(script.Parent.Parent.Lib.Celebrate)
local Layout = require(script.Parent.Parent.Lib.Layout)
local RewardText = require(script.Parent.Parent.Lib.RewardText)
local Sfx = require(script.Parent.Parent.Lib.Sfx)
local StormLogTab = require(script.Parent.Parent.Lib.StormLogTab)
local UI = require(script.Parent.Parent.Lib.UI)
local ZoneColours = require(script.Parent.Parent.Lib.ZoneColours)
local Researchers = require(script.Parent.Researchers)
local State = require(script.Parent.State)

local COLORS = UI.COLORS

type Card = {
	def: Types.ResearcherDef,
	index: number,
	stroke: UIStroke,
	title: TextLabel,
	level: TextLabel,
	now: TextLabel,
	next: TextLabel,
	status: TextLabel,
	bar: UI.Bar,
	barText: TextLabel,
	post: TextButton,
	hire: TextButton,
	promote: TextButton,
}

type Chip = {
	tier: number,
	button: TextButton,
	stroke: UIStroke,
	gem: Frame,
	gemStroke: UIStroke,
	count: TextLabel,
	name: TextLabel,
}

type Tab = "team" | "log"

local CONFIRM_SECONDS = 4 -- a second PROMOTE tap within this confirms
local TIP_TEXT =
	"Your researchers can't work here yet: catch bolts here for Glints and promote them at the Research Office."
local DESIGN = Vector2.new(680, 560) -- the same as the REWARDS panel
local TAB_HEIGHT = 40
local STRIP = 80 -- the Glints strip
local GAP = 8
local CHIP_GAP = 6
local PICK_HEIGHT = 40 -- a post picker button

local ResearchUI = {}

-- Fires true when a Storm Log row can be claimed, false when none can.
ResearchUI.ReadyChanged = Signal.new() :: Signal.Signal<boolean>

local panel: Frame
local cards: { Card } = {}
local chips: { Chip } = {}
local hireRemote: RemoteEvent
local postRemote: RemoteEvent
local promoteRemote: RemoteEvent
local teamPage: Frame
local logList: ScrollingFrame
local teamTab: TextButton
local logTab: TextButton
local picker: TextButton -- the dim catcher over the panel (a tap on it closes the picker)
local pickerTitle: TextLabel
local pickerButtons: { [string]: TextButton } = {}
local pickerFor: Card? = nil
local postNames: { [string]: string } = { Office = "Office" }
local knownLevels: { [string]: number } = {}
local knownRanks: { [string]: number } = {} -- for the promotion moment
local knownGlints: { [number]: number } = {} -- for the chip pop
local confirmUntil: { [string]: number } = {} -- role id -> os.clock() the confirm tap runs out
local lastBottleTier: number? = nil
local rendered = false -- the first render is just loading in (no "hired" sound)
local tipShown = false
local logReady = false

local render: (snapshot: Types.Snapshot) -> ()

-- Shows the TEAM or LOG tab.
local function selectTab(tab: Tab)
	teamPage.Visible = tab == "team"
	logList.Visible = tab == "log"
	UI.setEnabled(teamTab, true, if tab == "team" then COLORS.storm else COLORS.panelDark)
	UI.setEnabled(logTab, true, if tab == "log" then COLORS.storm else COLORS.panelDark)
end

function ResearchUI.toggle()
	UI.togglePanel(panel)
end

function ResearchUI.open()
	UI.openPanel(panel)
end

-- Opens the panel on the LOG tab (the Storm Log's toasts use this).
function ResearchUI.openLog()
	selectTab("log")
	UI.openPanel(panel)
end

-- Can a Storm Log row be claimed? (The menu's RESEARCH dot.)
function ResearchUI.isReady(): boolean
	return logReady
end

-- Closes the post picker if it's open. True if it was (Esc / gamepad B
-- then leaves the panel open).
function ResearchUI.closePicker(): boolean
	if not picker or not picker.Visible then
		return false
	end
	picker.Visible = false
	pickerFor = nil
	UI.selectFirst(panel)
	return true
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

local function tierColour(tier: number): Color3
	return ZoneColours.of(ResearchMath.tierZone(tier), COLORS.storm)
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
	Sfx.play("level_up")
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

-- Where a tier's Glints come from and what they pay for, asked of the rules
-- (Util/Research.glintsFor) with one Glint of that tier.
local function chipInfo(tier: number): string
	local zones: { string } = {}
	for _, zone in Formulas.sortedZones() do
		if ResearchMath.zoneTier(zone) == tier then
			table.insert(zones, zone.displayName)
		end
	end
	local probe: { number } = {}
	for index = 0, ResearchMath.maxRank() do
		probe[index + 1] = if index == tier then 1 else 0
	end
	local ranks: { number } = {}
	for rank = 1, ResearchMath.maxRank() do
		if ResearchMath.glintsFor(probe, rank) > 0 then
			table.insert(ranks, rank)
		end
	end
	local from = `💎 {zoneName(tier)} Glints: one for every bolt you catch in {table.concat(
		zones,
		" or "
	)}.`
	if #ranks == 0 then
		return `{from} They don't pay for any promotion.`
	elseif #ranks == 1 then
		return `{from} They pay for promotion to rank {ranks[1]}.`
	end
	return `{from} They pay for promotions to rank {ranks[1]} to {ranks[#ranks]}.`
end

-- The Glints strip: each chip's count, colour and pop when it rises.
local function renderChips(glints: { number })
	for _, chip in chips do
		local count = ResearchMath.glintsOf(glints, chip.tier)
		local colour = tierColour(chip.tier)
		local has = count > 0
		chip.count.Text = if has then Format.abbreviate(count) else "?"
		chip.count.TextTransparency = if has then 0 else 0.4
		chip.name.TextTransparency = if has then 0 else 0.5
		chip.name.TextColor3 = colour:Lerp(Color3.new(1, 1, 1), 0.35)
		chip.gem.BackgroundColor3 = if has then colour else COLORS.disabled
		chip.gemStroke.Color = if has then colour:Lerp(Color3.new(1, 1, 1), 0.6) else COLORS.stroke
		chip.button.BackgroundColor3 = COLORS.panelDark:Lerp(colour, if has then 0.35 else 0.1)
		chip.stroke.Color = if has then colour else COLORS.stroke
		local before = knownGlints[chip.tier]
		knownGlints[chip.tier] = count
		if before and count > before and panel.Visible then
			UI.pop(chip.button, 1.15)
		end
	end
end

-- The picker's buttons for one researcher: locked zones show 🔒 and the
-- rank they need, the current post is volt.
local function renderPicker(snapshot: Types.Snapshot)
	local card = pickerFor
	if not card then
		return
	end
	local save = snapshot.researchers[card.def.id]
	local rank = if save then save.rank or 0 else 0
	pickerTitle.Text = `📍 POST {string.upper(card.def.name)}`
	for postId, button in pickerButtons do
		local zone = Config.ZONES[postId]
		local name = string.upper(postNames[postId])
		local locked = zone ~= nil and not ResearchMath.canPost(rank, zone)
		local current = save ~= nil and save.post == postId
		button.Text = if locked
			then `🔒 {name} · RANK {ResearchMath.zoneTier(zone :: Types.ZoneDef)}`
			elseif current then `✓ {name}`
			else name
		UI.setEnabled(button, not locked, if current then COLORS.volt else COLORS.storm)
	end
end

local function renderCard(
	card: Card,
	snapshot: Types.Snapshot,
	atOffice: boolean,
	wasRendered: boolean
)
	local def = card.def
	local glints = snapshot.glints or {}
	local now = workspace:GetServerTimeNow()
	local save = snapshot.researchers[def.id]
	local previous = Config.RESEARCHERS[card.index - 1]
	local unlocked = previous == nil or snapshot.researchers[previous.id] ~= nil

	local rank = if save then save.rank or 0 else 0
	card.title.Text = `{string.upper(`{def.name} · {def.role}`)}{stars(rank)}`
	local known = knownRanks[def.id]
	if save then
		if known == nil and wasRendered then
			Sfx.play("hired")
		end
		knownRanks[def.id] = rank
		if known and rank > known then
			celebrate(card, rank)
		end
	end
	card.stroke.Color = COLORS.stroke
	card.stroke.Thickness = 3

	if not save then
		card.level.Text = "Lv -"
		card.now.Text = perkText(def, 1, 0)
		card.next.Text = ""
		card.bar.setFraction(0)
		card.barText.Text = "Not hired"
		card.status.Text = if not unlocked
			then `Hire {previous.name} first`
			elseif snapshot.volts < def.price then `Need {Format.abbreviate(
				def.price - snapshot.volts
			)} more ⚡`
			elseif atOffice then "Ready to hire"
			else "Hire at the Research Center"
		card.post.Text = "📍 POST"
		UI.setEnabled(card.post, false, COLORS.storm)
		card.hire.Visible = true
		card.promote.Visible = false
		card.hire.Text = `HIRE {Format.abbreviate(def.price)} ⚡`
		UI.setEnabled(
			card.hire,
			unlocked and atOffice and snapshot.volts >= def.price,
			COLORS.green
		)
		return
	end

	local maxLevel = #Config.RESEARCH_LEVELS
	local nextAt = ResearchMath.nextThreshold(save.level, rank)
	card.level.Text = `Lv {save.level} / {maxLevel}`
	card.now.Text = perkText(def, save.level, rank)
	card.next.Text = if nextAt
		then `Next (Lv {save.level + 1}): {perkText(def, save.level + 1, rank)}`
		elseif rank < ResearchMath.maxRank() then `Promote for rank {rank + 1}`
		else "Max level and rank"
	card.bar.setFraction(if nextAt then save.data / nextAt else 1)
	card.barText.Text = if nextAt
		then `{Format.abbreviate(save.data)} / {Format.abbreviate(nextAt)} data`
		else `{Format.abbreviate(save.data)} data`
	local postName = postNames[save.post] or save.post
	local readyIn = (snapshot.setupUntil[def.id] or 0) - now
	card.status.Text = if save.post == "Office"
		then "At the Research Office"
		elseif readyIn > 0 then `Setting up in {postName}... {math.ceil(readyIn)}s`
		else `Working in {postName}`
	card.post.Text = `📍 {string.upper(postName)}`
	UI.setEnabled(card.post, true, COLORS.storm)

	if rank >= ResearchMath.maxRank() then
		card.hire.Visible = true
		card.promote.Visible = false
		card.hire.Text = "★ TOP RANK"
		UI.setEnabled(card.hire, false, COLORS.green)
		return
	end
	card.hire.Visible = false
	card.promote.Visible = true
	local target = rank + 1
	local cost = Config.RESEARCH_PRESTIGE.glintCost[target]
	local have = ResearchMath.glintsFor(glints, target)
	local confirming = (confirmUntil[def.id] or 0) > os.clock()
	local block = promoteBlock(save, glints, atOffice)
	if have < cost then
		card.promote.Text =
			`✨ {Format.abbreviate(have)}/{Format.abbreviate(cost)} {zoneName(target)}`
	elseif confirming then
		card.promote.Text = "TAP AGAIN"
		card.status.Text = `Promote: Lv 1, rank {target}, +{math.floor(
			Config.RESEARCH_PRESTIGE.perkBonusPerRank * 100 + 0.5
		)}% perk, works in {zoneName(target)}`
	else
		card.promote.Text = `PROMOTE ✨{Format.abbreviate(cost)}`
	end
	UI.setEnabled(card.promote, block == nil, COLORS.volt)
	if block == nil then
		card.stroke.Color = COLORS.volt
		card.stroke.Thickness = 5
	end
end

-- TEAM: the Glints strip, the cards and the picker (if it's open).
local function renderTeam(snapshot: Types.Snapshot)
	local atOffice = inOffice()
	renderChips(snapshot.glints or {})
	checkTip(snapshot)
	local wasRendered = rendered
	rendered = true
	for _, card in cards do
		renderCard(card, snapshot, atOffice, wasRendered)
	end
	renderPicker(snapshot)
end

-- LOG: the Storm Log, the tab's count and the menu's dot.
local function renderLog(snapshot: Types.Snapshot)
	local claimable = StormLogTab.render(snapshot, RewardText.describe)
	logTab.Text = if claimable > 0 then `📖 LOG ({claimable})` else "📖 LOG"
	local ready = claimable > 0
	if ready ~= logReady then
		logReady = ready
		ResearchUI.ReadyChanged:Fire(ready)
	end
end

render = function(snapshot: Types.Snapshot)
	renderTeam(snapshot)
	renderLog(snapshot)
end

local function openPicker(card: Card)
	local snapshot = State.current
	if not snapshot or not snapshot.researchers[card.def.id] then
		UI.toast(`Hire {card.def.name} first`, "info")
		return
	end
	pickerFor = card
	renderPicker(snapshot)
	picker.Visible = true
	UI.selectFirst(picker)
end

local function pick(postId: string)
	local card = pickerFor
	local snapshot = State.current
	local save = if card and snapshot then snapshot.researchers[card.def.id] else nil
	if not card or not save then
		ResearchUI.closePicker()
		return
	end
	local zone = Config.ZONES[postId]
	if zone and not ResearchMath.canPost(save.rank, zone) then
		local tier = ResearchMath.zoneTier(zone)
		UI.toast(`Needs rank {tier} to work in {zone.displayName}`, "info")
		return
	end
	if save.post ~= postId then
		postRemote:FireServer(card.def.id, postId)
	end
	ResearchUI.closePicker()
end

-- The one post picker, over the whole panel (above its tabs and cards).
local function buildPicker()
	picker = UI.make(Instance.new("TextButton"), {
		Name = "PostPicker",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 20,
		Parent = panel,
	})
	UI.corner(picker, UDim.new(0, 14))
	picker.Activated:Connect(function()
		ResearchUI.closePicker()
	end)
	local box = UI.panel({
		Name = "Box",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.7, 0, 0.86, 0),
		Parent = picker,
	})
	-- a tap on the box (between its buttons) isn't a tap outside it
	UI.make(Instance.new("TextButton"), {
		Name = "Absorb",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
		Parent = box,
	})
	UI.padding(box, 12)
	pickerTitle = UI.label({
		Title = true,
		Text = "📍 POST",
		Size = UDim2.new(1, 0, 0, 34),
		Parent = box,
	})
	UI.maxText(pickerTitle, 26)
	local list = UI.list(box, {
		Name = "Posts",
		Position = UDim2.fromOffset(0, 42),
		Size = UDim2.new(1, 0, 1, -42),
		gap = 6,
	})
	local order = 0
	local function button(postId: string)
		order += 1
		local item = UI.button({
			Name = postId,
			Text = string.upper(postNames[postId]),
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, PICK_HEIGHT),
			BackgroundColor3 = COLORS.storm,
			Parent = list,
		})
		UI.maxText(item, 20)
		item.Activated:Connect(function()
			UI.pop(item)
			pick(postId)
		end)
		pickerButtons[postId] = item
	end
	button("Office")
	for _, world in Config.WORLDS do
		local zones: { Types.ZoneDef } = {}
		for _, zone in Formulas.sortedZones() do
			if zone.world == world.id then
				table.insert(zones, zone)
			end
		end
		if #zones > 0 then
			order += 1
			local heading = UI.label({
				Title = true,
				Name = `{world.id}Heading`,
				LayoutOrder = order,
				Text = world.displayName,
				TextColor3 = COLORS.subtext,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Bottom,
				Size = UDim2.new(1, 0, 0, 28),
				Parent = list,
			})
			UI.maxText(heading, 20)
			for _, zone in zones do
				button(zone.id)
			end
		end
	end
	-- closing the panel closes the picker too
	panel:GetPropertyChangedSignal("Visible"):Connect(function()
		if not panel.Visible then
			picker.Visible = false
			pickerFor = nil
		end
	end)
end

-- One Glints chip: a gem (a square turned 45°, with a gradient and an
-- outline), the count and the zone's name.
local function buildChip(parent: Instance, tier: number, width: UDim)
	local button = UI.make(Instance.new("TextButton"), {
		Name = `Tier{tier}`,
		Text = "",
		AutoButtonColor = true,
		LayoutOrder = tier,
		BackgroundColor3 = COLORS.panelDark,
		Size = UDim2.new(width, UDim.new(1, 0)),
		Parent = parent,
	})
	UI.corner(button, UDim.new(0, 10))
	local stroke = UI.stroke(button, 3)
	UI.clickSound(button, true)
	local gem = UI.make(Instance.new("Frame"), {
		Name = "Gem",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 20),
		Size = UDim2.fromOffset(18, 18),
		Rotation = 45,
		BackgroundColor3 = COLORS.disabled,
		Parent = button,
	})
	UI.corner(gem, UDim.new(0, 3))
	UI.make(Instance.new("UIGradient"), {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(120, 120, 140)),
		Rotation = 45, -- lit from the top corner
		Parent = gem,
	})
	local gemStroke = UI.stroke(gem, 2)
	local count = UI.label({
		Title = true,
		Name = "Count",
		Text = "?",
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = button,
	})
	UI.maxText(count, 22)
	local name = UI.label({
		Name = "Zone",
		Text = zoneName(tier),
		Position = UDim2.new(0, 3, 0, 57),
		Size = UDim2.new(1, -6, 0, 18),
		Parent = button,
	})
	UI.maxText(name, 13)
	button.Activated:Connect(function()
		UI.pop(button)
		UI.toast(chipInfo(tier), "info", 7)
	end)
	table.insert(chips, {
		tier = tier,
		button = button,
		stroke = stroke,
		gem = gem,
		gemStroke = gemStroke,
		count = count,
		name = name,
	})
end

local function buildStrip(parent: Instance)
	local strip = UI.make(Instance.new("Frame"), {
		Name = "Glints",
		Size = UDim2.new(1, 0, 0, STRIP),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	UI.padding(strip, 3) -- room for the chip outlines
	UI.make(Instance.new("UIListLayout"), {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, CHIP_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = strip,
	})
	local tiers = ResearchMath.maxRank() + 1
	local width = UDim.new(1 / tiers, -CHIP_GAP * (tiers - 1) / tiers)
	for tier = 0, ResearchMath.maxRank() do
		buildChip(strip, tier, width)
	end
end

local function buildCard(list: Instance, index: number, def: Types.ResearcherDef)
	local frame, stroke = UI.card({
		Name = def.id,
		LayoutOrder = index,
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = list,
	})
	UI.make(Instance.new("UIListLayout"), {
		Padding = UDim.new(0, 6),
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

	-- the top: the portrait, and beside it the name, level, perk and next
	local top = row(1, 70)
	local portrait = UI.make(Instance.new("ViewportFrame"), {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = COLORS.stroke,
		BackgroundTransparency = 0.4,
		Ambient = Color3.fromRGB(190, 190, 200),
		LightColor = Color3.fromRGB(255, 250, 235),
		Parent = top,
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

	local title = text(top, {
		Title = true,
		Text = string.upper(`{def.name} · {def.role}`),
		RichText = true, -- the gold rank stars
		Position = UDim2.fromOffset(74, 0),
		Size = UDim2.new(1, -74 - 96, 0, 26),
	}, 22)
	local level = text(top, {
		Title = true,
		Text = "Lv -",
		TextColor3 = COLORS.volt,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(92, 26),
	}, 22)
	local now = text(top, {
		Text = "",
		Position = UDim2.fromOffset(74, 28),
		Size = UDim2.new(1, -74, 0, 22),
	}, 16)
	local next = text(top, {
		Text = "",
		TextColor3 = COLORS.subtext,
		Position = UDim2.fromOffset(74, 50),
		Size = UDim2.new(1, -74, 0, 20),
	}, 14)

	local dataBar = UI.bar(row(2, 18), {
		Name = "DataBar",
		Size = UDim2.fromScale(1, 1),
		color = COLORS.storm,
		text = 13,
	})
	local barText = dataBar.label :: TextLabel

	local status = text(row(3, 18), {
		Text = "",
		TextColor3 = COLORS.calm,
		Size = UDim2.fromScale(1, 1),
	}, 14)

	-- the bottom: POST and HIRE / PROMOTE side by side
	local buttons = row(4, 38)
	local post = UI.button({
		Name = "Post",
		Text = "📍 POST",
		Size = UDim2.new(0.5, -4, 1, 0),
		BackgroundColor3 = COLORS.storm,
		Parent = buttons,
	})
	UI.maxText(post, 18)
	local card: Card
	post.Activated:Connect(function()
		UI.pop(post)
		openPicker(card)
	end)

	local function right(name: string, color: Color3): TextButton
		local button = UI.button({
			Name = name,
			Text = "...",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0.5, -4, 1, 0),
			BackgroundColor3 = color,
			Parent = buttons,
		})
		UI.maxText(button, 18)
		return button
	end
	local hire = right("Hire", COLORS.green)
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

	-- in the hire button's place once they're hired (until the top rank)
	local promote = right("Promote", COLORS.volt)
	promote.Visible = false
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
			renderTeam(snapshot)
			task.delay(CONFIRM_SECONDS, function()
				if State.current then
					renderTeam(State.current)
				end
			end)
		end
	end)

	card = {
		def = def,
		index = index,
		stroke = stroke,
		title = title,
		level = level,
		now = now,
		next = next,
		status = status,
		bar = dataBar,
		barText = barText,
		post = post,
		hire = hire,
		promote = promote,
	}
	table.insert(cards, card)
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
				Sfx.play("level_up")
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
		postNames[zone.id] = zone.displayName
	end

	local _, root = Layout.screen("StormBottlerResearch", 6) -- above the shop if both are open
	local window = UI.window(root, "ResearchPanel", "🔬 RESEARCH", COLORS.storm, DESIGN)
	panel = window.panel

	-- the two tabs along the top
	local tabBar = UI.make(Instance.new("Frame"), {
		Name = "Tabs",
		Size = UDim2.new(1, 0, 0, TAB_HEIGHT),
		BackgroundTransparency = 1,
		Parent = window.body,
	})
	UI.make(Instance.new("UIGridLayout"), {
		CellSize = UDim2.new(1 / 2, -6, 1, 0),
		CellPadding = UDim2.fromOffset(6, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = tabBar,
	})
	local function tab(order: number, text: string, which: Tab): TextButton
		local button = UI.button({
			Name = if which == "team" then "TeamTab" else "LogTab",
			Text = text,
			LayoutOrder = order,
			BackgroundColor3 = COLORS.panelDark,
			Parent = tabBar,
		})
		UI.maxText(button, 18)
		button.Activated:Connect(function()
			local page: GuiObject = if which == "team" then teamPage else logList
			if not page.Visible then
				UI.pop(button)
				Sfx.play("tab")
				selectTab(which)
			end
		end)
		return button
	end
	teamTab = tab(1, "👥 TEAM", "team")
	logTab = tab(2, "📖 LOG", "log")

	-- TEAM: the Glints strip over the researcher cards
	teamPage = UI.make(Instance.new("Frame"), {
		Name = "Team",
		Position = UDim2.fromOffset(0, TAB_HEIGHT + GAP),
		Size = UDim2.new(1, 0, 1, -(TAB_HEIGHT + GAP)),
		BackgroundTransparency = 1,
		Parent = window.body,
	})
	buildStrip(teamPage)
	local list = UI.list(teamPage, {
		Name = "List",
		Position = UDim2.fromOffset(0, STRIP + 4),
		Size = UDim2.new(1, 0, 1, -(STRIP + 4)),
		gap = 10,
	})
	local hint = UI.label({
		Name = "Hint",
		LayoutOrder = 0,
		Text = "Hire researchers at the Research Center island, then post them at a zone.",
		TextColor3 = COLORS.subtext,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 22),
		Parent = list,
	})
	UI.maxText(hint, 15)
	for index, def in Config.RESEARCHERS do
		buildCard(list, index, def)
	end

	-- LOG: the Storm Log (Lib/StormLogTab)
	logList = UI.list(window.body, {
		Name = "Log",
		Position = UDim2.fromOffset(0, TAB_HEIGHT + GAP),
		Size = UDim2.new(1, 0, 1, -(TAB_HEIGHT + GAP)),
		gap = GAP,
	})
	StormLogTab.build(logList, ResearchUI.openLog)

	buildPicker()
	selectTab("team")
	watchLevels()
end

function ResearchUI.start()
	if State.current then
		render(State.current)
	end
	State.Changed:Connect(render)
	-- standing in the office and set-up countdowns change without a snapshot;
	-- stepping onto the Research Center doorstep opens the panel on TEAM
	local wasInOffice = false
	while true do
		task.wait(0.25)
		local here = inOffice()
		if here and not wasInOffice and not panel.Visible then
			selectTab("team")
			ResearchUI.open()
		end
		wasInOffice = here
		if panel.Visible and State.current then
			renderTeam(State.current)
		end
	end
end

return ResearchUI
