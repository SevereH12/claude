--!strict
-- REWARDS panel (from the menu), in the store's card style:
--   * the 7-day login streak: claimed days ticked, today's glowing with
--     CLAIM, later days dimmed, and "Next reward in 5h 12m" (to the next UTC
--     day) once today's is claimed
--   * the 6 playtime gifts of today (UTC), each counting down ("in 3:41") or
--     showing CLAIM
-- Each card shows what this player would really get: Volts grow with their
-- best zone, and a boost for a pass they own says so and pays Volts instead
-- (Util/Rewards.resolve). CLAIM only asks (ClaimDaily, ClaimGift); the
-- server decides (Systems/Rewards) and Rewarded brings a celebration.
--   * the group card: members of the game's group (Config.GROUP_ID) get
--     +10% Volts. JOIN opens Roblox's group prompt (only from the tap), and
--     a join is reported (GroupJoined) for the server to check itself
--     (Systems/Group)
--   * the invite card: INVITE opens Roblox's invite window
--     (SocialService:PromptGameInvite, after CanSendGameInviteAsync). A
--     friend who's new to the game gets a welcome gift and you get a boost
--     (Systems/Invites); friends in your server add +5% Volts each
-- Cards size themselves to the screen (fitCards): a phone held upright gets
-- 4 days and 2 gifts a row, and on touch screens the cards grow to fit the
-- TAP_MIN-tall CLAIM button and the larger minimum text, instead of the
-- button covering the reward.
-- Four tabs: REWARDS (all of the above), QUESTS: today's daily quests
-- and this week's quest (Util/Quests), each a card with what to do, a
-- progress bar, the reward and a button: CLAIM when it's done, or REROLL
-- (today's one free reroll) while it isn't. A quest reaching 100% shows a
-- toast. Both only ask (ClaimQuest, RerollQuest); Systems/Quests decides.
-- And LOG: the Storm Log collection book (Lib/StormLogTab, Util/StormLog),
-- with CLAIM on each finished row. And TOP: the leaderboards
-- (Lib/LeaderboardTab, Systems/Leaderboards).
-- After the first daily claim the server may ask (NotifyOptIn) "Remind me
-- when my daily reward is ready?": a toast whose YES opens Roblox's own
-- notifications prompt (ExperienceNotificationService), if this player can
-- be asked. It's asked once, ever (Systems/Notifications).
-- RewardsUI.ReadyChanged tells the menu when something is ready to claim
-- (a quest or a Log row too).
-- Gentle nudges, as toasts with OPEN: the daily reward when you join (if
-- it's ready), each playtime gift once when it's ready, and the group card
-- once a visit after your first sale.

local ExperienceNotificationService = game:GetService("ExperienceNotificationService")
local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local BoostRules = require(ReplicatedStorage.Shared.Util.Boosts)
local PassRules = require(ReplicatedStorage.Shared.Util.Passes)
local QuestRules = require(ReplicatedStorage.Shared.Util.Quests)
local RewardRules = require(ReplicatedStorage.Shared.Util.Rewards)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local StatRules = require(ReplicatedStorage.Shared.Util.Stats)
local Store = require(ReplicatedStorage.Shared.Util.Store)
local Types = require(ReplicatedStorage.Shared.Types)
local Celebrate = require(script.Parent.Parent.Lib.Celebrate)
local Layout = require(script.Parent.Parent.Lib.Layout)
local LeaderboardTab = require(script.Parent.Parent.Lib.LeaderboardTab)
local LayoutMath = require(script.Parent.Parent.Lib.LayoutMath)
local SettingsStore = require(script.Parent.Parent.Lib.SettingsStore)
local Sfx = require(script.Parent.Parent.Lib.Sfx)
local StormLogTab = require(script.Parent.Parent.Lib.StormLogTab)
local UI = require(script.Parent.Parent.Lib.UI)
local State = require(script.Parent.State)

local COLORS = UI.COLORS
local PINK = Color3.fromRGB(255, 120, 170)
local GROUP_HEIGHT = 72
local NUDGE_SECONDS = 6
local HEADING = 36 -- section titles sit at the bottom, so sections have room between them
local GAP = 8
-- inside a card (design pixels)
local PAD = 4
local TITLE = 20
local ICON = 40
local BUTTON = 36 -- CLAIM's height; at least TAP_MIN points on touch
local TAB_HEIGHT = 40
local QUEST_HEIGHT = 92 -- a quest card, at least (taller when its button is)

-- `wide`: a gift card (the text beside the icon); otherwise a day card
-- (title, icon, text and CLAIM stacked)
type Card = {
	frame: Frame,
	image: ImageLabel,
	text: TextLabel,
	button: TextButton,
	stroke: UIStroke,
	wide: boolean,
}

type Grid = { frame: Frame, layout: UIGridLayout, count: number }

-- A quest card. `mode`: what its button does now.
type QuestCard = {
	frame: Frame,
	title: TextLabel,
	fill: Frame,
	count: TextLabel,
	reward: TextLabel,
	button: TextButton,
	stroke: UIStroke,
	mode: "claim" | "reroll" | nil,
}

local RewardsUI = {}

-- Fires true when something becomes ready to claim, false when nothing is.
RewardsUI.ReadyChanged = Signal.new() :: Signal.Signal<boolean>

local player = Players.LocalPlayer
local panel: Frame
local list: ScrollingFrame
local questList: ScrollingFrame
local logList: ScrollingFrame
local topList: ScrollingFrame
local rewardsTab: TextButton
local questsTab: TextButton
local logTab: TextButton
local topTab: TextButton
local dailyQuestCards: { QuestCard } = {}
local weeklyQuestCards: { QuestCard } = {}
local dailyNote: TextLabel
local weeklyNote: TextLabel
-- each quest's done-ness at the last render (for the 100% toast)
local questDone: { [string]: boolean } = {}
local dayCards: { Card } = {}
local giftCards: { Card } = {}
local dayGrid: Grid
local giftGrid: Grid
local nextLabel: TextLabel
local groupText: TextLabel
local groupButton: TextButton
local ready = false
local joining = false -- the group prompt is open
local joinTapped = false -- JOIN was tapped this visit
local requestPending = false -- the group needs approval and the request is in
-- nudges already shown this visit
local dailyNudged = false
local giftNudged: { [number]: boolean } = {}
local groupNudged = false

function RewardsUI.open()
	UI.openPanel(panel)
end

type Tab = "rewards" | "quests" | "log" | "top"

-- Shows the REWARDS, QUESTS, LOG or TOP tab.
local function selectTab(tab: Tab)
	list.Visible = tab == "rewards"
	questList.Visible = tab == "quests"
	logList.Visible = tab == "log"
	topList.Visible = tab == "top"
	UI.setEnabled(rewardsTab, true, if tab == "rewards" then PINK else COLORS.panelDark)
	UI.setEnabled(questsTab, true, if tab == "quests" then PINK else COLORS.panelDark)
	UI.setEnabled(logTab, true, if tab == "log" then PINK else COLORS.panelDark)
	UI.setEnabled(topTab, true, if tab == "top" then PINK else COLORS.panelDark)
end

-- Opens the panel on the TOP tab (the leaderboards).
function RewardsUI.openTop()
	selectTab("top")
	RewardsUI.open()
end

-- Opens the panel on the QUESTS tab.
function RewardsUI.openQuests()
	selectTab("quests")
	RewardsUI.open()
end

-- Opens the panel on the LOG tab (the Storm Log).
function RewardsUI.openLog()
	selectTab("log")
	RewardsUI.open()
end

-- Opens the panel scrolled down to the group card.
local function openAtGroup()
	selectTab("rewards")
	RewardsUI.open()
	task.spawn(function()
		RunService.Heartbeat:Wait()
		list.CanvasPosition = Vector2.new(0, list.AbsoluteCanvasSize.Y)
	end)
end

function RewardsUI.isReady(): boolean
	return ready
end

-- "5h 12m" or "12m".
local function hoursMinutes(seconds: number): string
	local minutes = math.ceil(seconds / 60)
	if minutes >= 60 then
		return `{minutes // 60}h {minutes % 60}m`
	end
	return `{minutes}m`
end

-- "3d 4h", or "5h 12m" under a day.
local function daysHours(seconds: number): string
	local hours = math.floor(seconds / 3600)
	if hours >= 24 then
		return `{hours // 24}d {hours % 24}h`
	end
	return hoursMinutes(seconds)
end

-- What a reward gives this player, as card text, and its icon: a boost's
-- pass art, or a Volts pack's (bigger reward, bigger pack).
local function describe(reward: Types.Reward, snapshot: Types.Snapshot): (string, number)
	local resolved = RewardRules.resolve(reward, snapshot.passes)
	local lines: { string } = {}
	if resolved.charges > 0 then
		table.insert(lines, `+{Format.abbreviate(Store.volts(resolved.charges, snapshot))} ⚡`)
	end
	for _, boost in resolved.boosts do
		local def = BoostRules.def(boost.key)
		if def then
			table.insert(lines, `{def.name} {boost.minutes}m`)
		end
	end
	for _, key in resolved.swapped do
		local def = BoostRules.def(key)
		local pass = if def then PassRules.def(def.pass) else nil
		if pass then
			table.insert(lines, `(you own {pass.name})`)
		end
	end
	local image = 0
	local first = resolved.boosts[1]
	if resolved.charges == 0 and first then
		local def = BoostRules.def(first.key)
		local pass = if def then PassRules.def(def.pass) else nil
		image = if pass then pass.image else 0
	else
		local size = if resolved.charges >= 1000 then 3 elseif resolved.charges >= 250 then 2 else 1
		image = Config.VOLT_PACKS[size].image
	end
	return table.concat(lines, "\n"), image
end

-- A day or gift card: a title, an icon, what it gives, and a button
-- (placed by fitCards).
local function buildCard(
	parent: Instance,
	order: number,
	title: string,
	wide: boolean,
	onClaim: () -> ()
): Card
	local frame = UI.make(Instance.new("Frame"), {
		Name = title,
		LayoutOrder = order,
		BackgroundColor3 = COLORS.panelDark,
		Parent = parent,
	})
	UI.corner(frame, UDim.new(0, 12))
	local stroke = UI.stroke(frame, 3)
	local heading = UI.label({
		Title = true,
		Text = title,
		Position = UDim2.fromOffset(PAD, PAD),
		Size = UDim2.new(1, -2 * PAD, 0, TITLE),
		Parent = frame,
	})
	UI.maxText(heading, 18)
	local image = UI.make(Instance.new("ImageLabel"), {
		Name = "Icon",
		Size = UDim2.fromOffset(ICON, ICON),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Parent = frame,
	})
	local text = UI.label({
		Text = "",
		TextColor3 = COLORS.subtext,
		TextWrapped = true,
		TextXAlignment = if wide then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
		Parent = frame,
	})
	UI.maxText(text, 16)
	local button = UI.button({
		Name = "Claim",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		BackgroundColor3 = COLORS.green,
		Parent = frame,
	})
	UI.maxText(button, 18)
	button.Activated:Connect(function()
		UI.pop(button)
		onClaim()
	end)
	return {
		frame = frame,
		image = image,
		text = text,
		button = button,
		stroke = stroke,
		wide = wide,
	}
end

-- Places a card's icon, text and CLAIM for a `button`-tall CLAIM and a
-- `textHeight`-tall text area: a day card stacks them under its title, a
-- gift card puts the text beside the icon. Returns the card's height.
local function placeCard(card: Card, button: number, textHeight: number): number
	local top = PAD + TITLE + 2
	card.button.Size = UDim2.new(1, -2 * PAD, 0, button)
	if card.wide then
		card.image.AnchorPoint = Vector2.zero
		card.image.Position = UDim2.fromOffset(PAD + 4, top + 2)
		local left = PAD + 4 + ICON + 8
		card.text.Position = UDim2.fromOffset(left, top)
		card.text.Size = UDim2.new(1, -(left + PAD), 0, textHeight)
		return math.max(top + 2 + ICON, top + textHeight) + 6 + button + 6
	end
	card.image.AnchorPoint = Vector2.new(0.5, 0)
	card.image.Position = UDim2.new(0.5, 0, 0, top)
	card.text.Position = UDim2.fromOffset(PAD, top + ICON + 4)
	card.text.Size = UDim2.new(1, -2 * PAD, 0, textHeight)
	return top + ICON + 4 + textHeight + 4 + button + 6
end

-- Sizes both grids for this screen: 7 days and 3 gifts a row (4 and 2 on a
-- phone held upright); on touch the CLAIM buttons are TAP_MIN points tall
-- and text can't shrink below 14 points, so the cards are taller there.
local function fitCards()
	local upright = Layout.class == "Phone" and Layout.portrait
	local touch = Layout.isTouch()
	local button = LayoutMath.tapMin(Layout.class, Layout.scale, Vector2.new(0, BUTTON)).Y
	local function fit(grid: Grid, cards: { Card }, columns: number, textHeight: number)
		local height = 0
		for _, card in cards do
			height = placeCard(card, button, textHeight)
		end
		local rows = math.ceil(grid.count / columns)
		grid.layout.CellSize = UDim2.new(1 / columns, -GAP, 0, height)
		grid.frame.Size = UDim2.new(1, -12, 0, rows * height + (rows - 1) * GAP)
	end
	fit(dayGrid, dayCards, if upright then 4 else 7, if touch then 84 else 60)
	fit(giftGrid, giftCards, if upright then 2 else 3, if touch then 52 else 44)
end

-- A quest card: what to do, a progress bar, the reward, and its button.
local function buildQuestCard(
	parent: Instance,
	order: number,
	period: QuestRules.Period,
	index: number
): QuestCard
	local frame = UI.make(Instance.new("Frame"), {
		Name = `Quest{index}`,
		LayoutOrder = order,
		BackgroundColor3 = COLORS.panelDark,
		Size = UDim2.new(1, -12, 0, QUEST_HEIGHT),
		Parent = parent,
	})
	UI.corner(frame, UDim.new(0, 12))
	local stroke = UI.stroke(frame, 3)
	local title = UI.label({
		Title = true,
		Name = "Title",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(0.7, -12, 0, 24),
		Parent = frame,
	})
	UI.maxText(title, 20)
	local bar = UI.make(Instance.new("Frame"), {
		Name = "Bar",
		Position = UDim2.fromOffset(12, 38),
		Size = UDim2.new(0.7, -12, 0, 20),
		BackgroundColor3 = COLORS.panelBottom,
		Parent = frame,
	})
	UI.corner(bar, UDim.new(0, 8))
	local fill = UI.make(Instance.new("Frame"), {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = COLORS.green,
		Parent = bar,
	})
	UI.corner(fill, UDim.new(0, 8))
	local count = UI.label({
		Name = "Count",
		Text = "",
		Size = UDim2.fromScale(1, 1),
		Parent = bar,
	})
	UI.maxText(count, 14)
	local reward = UI.label({
		Name = "Reward",
		Text = "",
		TextColor3 = COLORS.subtext,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(12, 62),
		Size = UDim2.new(0.7, -12, 0, 22),
		Parent = frame,
	})
	UI.maxText(reward, 16)
	local button = UI.button({
		Name = "Action",
		Text = "",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0.28, 0, 0, BUTTON),
		BackgroundColor3 = COLORS.green,
		Parent = frame,
	})
	UI.maxText(button, 18)
	local card: QuestCard = {
		frame = frame,
		title = title,
		fill = fill,
		count = count,
		reward = reward,
		button = button,
		stroke = stroke,
		mode = nil,
	}
	button.Activated:Connect(function()
		if card.mode == "claim" then
			UI.pop(button)
			Net.get("ClaimQuest"):FireServer(period, index)
		elseif card.mode == "reroll" then
			UI.pop(button)
			Net.get("RerollQuest"):FireServer(period, index)
		end
	end)
	return card
end

-- Quest buttons are TAP_MIN points tall on touch; the cards grow to fit.
local function fitQuests()
	local button = LayoutMath.tapMin(Layout.class, Layout.scale, Vector2.new(0, BUTTON)).Y
	local height = math.max(QUEST_HEIGHT, button + 20)
	for _, cards in { dailyQuestCards, weeklyQuestCards } do
		for _, card in cards do
			card.frame.Size = UDim2.new(1, -12, 0, height)
			card.button.Size = UDim2.new(0.28, 0, 0, button)
		end
	end
end

local function setCard(
	card: Card,
	image: number,
	text: string,
	buttonText: string?,
	canClaim: boolean,
	dim: boolean
)
	card.image.Image = if image ~= 0 then `rbxassetid://{image}` else ""
	card.image.ImageTransparency = if dim then 0.6 else 0
	card.text.Text = text
	card.text.TextTransparency = if dim then 0.5 else 0
	card.button.Visible = buttonText ~= nil
	card.button.Text = buttonText or ""
	UI.setEnabled(card.button, canClaim, COLORS.green)
	-- what's ready glows gold
	card.stroke.Color = if canClaim then COLORS.volt else COLORS.stroke
	card.stroke.Thickness = if canClaim then 5 else 3
end

-- The group card: active, a request sent, or JOIN.
local function renderGroup()
	local percent = math.round(Config.GROUP_BONUS * 100)
	if player:GetAttribute(PassRules.GROUP) == true then
		groupText.Text = `✓ Group bonus active: +{percent}% Volts`
		groupButton.Visible = false
	elseif requestPending then
		groupText.Text = "Join request sent"
		groupButton.Visible = true
		groupButton.Text = "SENT"
		UI.setEnabled(groupButton, false, COLORS.storm)
	else
		groupText.Text = `Join {Config.GROUP_NAME} for +{percent}% Volts forever`
		groupButton.Visible = true
		groupButton.Text = "JOIN"
		UI.setEnabled(groupButton, true, COLORS.storm)
	end
end

-- JOIN: Roblox's own group prompt (only ever from the tap). The server
-- checks the membership itself; Roblox may take a moment to agree.
local function joinGroup()
	if joining then
		return
	end
	joining = true
	joinTapped = true
	task.spawn(function()
		local ok, status = pcall(function()
			return GroupService:PromptJoinAsync(Config.GROUP_ID)
		end)
		joining = false
		if not ok then
			warn(`[RewardsUI] the group prompt failed: {status}`)
			UI.toast("Couldn't open the group window. Try again soon.", "warn")
			return
		end
		if
			status == Enum.GroupMembershipStatus.Joined
			or status == Enum.GroupMembershipStatus.AlreadyMember
		then
			Net.get("GroupJoined"):FireServer()
			if player:GetAttribute(PassRules.GROUP) ~= true then
				UI.toast("Your bonus will switch on in a moment", "info", 4)
			end
		elseif status == Enum.GroupMembershipStatus.JoinRequestPending then
			requestPending = true
		end
		renderGroup()
	end)
end

-- INVITE: Roblox's own invite window, if this player may send invites.
local inviting = false
local function invite()
	if inviting then
		return
	end
	inviting = true
	task.spawn(function()
		local ok, can = pcall(function()
			return SocialService:CanSendGameInviteAsync(player)
		end)
		if not ok or not can then
			print(`[RewardsUI] invites aren't available here ({if ok then "not allowed" else can})`)
			UI.toast("Invites aren't available right now", "warn")
		else
			local shown, err = pcall(function()
				SocialService:PromptGameInvite(player)
			end)
			if not shown then
				warn(`[RewardsUI] the invite window failed: {err}`)
				UI.toast("Couldn't open the invite window. Try again soon.", "warn")
			end
		end
		inviting = false
	end)
end

-- Everything from the snapshot and the clock. Returns whether anything is
-- ready to claim, whether that's the daily reward, and which gifts are.
local function render(): (boolean, boolean, { number })
	local snapshot = State.current
	local readyGifts: { number } = {}
	if not snapshot then
		return false, false, readyGifts
	end
	local now = workspace:GetServerTimeNow()
	local anyReady = false

	-- the streak: the day to claim, or the day claimed today
	local daily = snapshot.daily
	local today = RewardRules.today(now) + daily.dayOffset
	local canClaim, nextDay = RewardRules.daily(daily.lastDay, today, daily.streak)
	local current = if canClaim then nextDay else daily.streak
	for day, card in dayCards do
		local text, image = describe(Config.DAILY_REWARDS[day], snapshot)
		if day == current and canClaim then
			setCard(card, image, text, "CLAIM", true, false)
		elseif day < current or day == current then
			setCard(card, image, text, "✓", false, false)
		else
			setCard(card, image, text, nil, false, true)
		end
	end
	anyReady = canClaim
	nextLabel.Text = if canClaim
		then `Day {nextDay} is ready to claim!`
		else `Next reward in {hoursMinutes(RewardRules.untilNextDay(now))}`

	-- today's playtime gifts
	local elapsed = now - snapshot.gifts.startedAt
	for index, card in giftCards do
		local gift = Config.PLAYTIME_GIFTS[index]
		local text, image = describe(gift.reward, snapshot)
		if snapshot.gifts.claimed[index] then
			setCard(card, image, text, "✓", false, true)
		elseif RewardRules.giftReady(gift, elapsed, false) then
			setCard(card, image, text, "CLAIM", true, false)
			anyReady = true
			table.insert(readyGifts, index)
		else
			local left = math.ceil(gift.minutes * 60 - elapsed)
			setCard(
				card,
				image,
				text,
				string.format("in %d:%02d", left // 60, left % 60),
				false,
				false
			)
		end
	end

	-- quests: today's and this week's
	local quests = snapshot.quests
	local claimable = 0
	local function renderQuests(
		views: { Types.QuestView },
		cards: { QuestCard },
		period: QuestRules.Period
	)
		for index, card in cards do
			local view = views[index]
			card.frame.Visible = view ~= nil
			if not view then
				continue
			end
			local text = QuestRules.describe(view)
			local done = view.progress >= view.target
			card.title.Text = text
			card.fill.Size =
				UDim2.fromScale(if view.target > 0 then view.progress / view.target else 1, 1)
			card.count.Text =
				`{Format.abbreviate(view.progress)} / {Format.abbreviate(view.target)}`
			local rewardText = describe(QuestRules.reward(view.key, period), snapshot)
			card.reward.Text = "Reward: " .. (string.gsub(rewardText, "\n", " · "))
			local canClaimQuest = done and not view.claimed
			card.button.Visible = true
			if view.claimed then
				card.mode = nil
				card.button.Text = "✓ DONE"
				UI.setEnabled(card.button, false, COLORS.green)
			elseif canClaimQuest then
				card.mode = "claim"
				card.button.Text = "CLAIM"
				UI.setEnabled(card.button, true, COLORS.green)
				claimable += 1
			elseif quests.rerollReady then
				card.mode = "reroll"
				card.button.Text = "🎲 REROLL"
				UI.setEnabled(card.button, true, COLORS.storm)
			else
				card.mode = nil
				card.button.Visible = false
			end
			card.stroke.Color = if canClaimQuest then COLORS.volt else COLORS.stroke
			card.stroke.Thickness = if canClaimQuest then 5 else 3
			-- the 100% toast: only when it changes to done while you watch
			local id = `{period}{index}:{view.key}:{view.zone or ""}:{view.target}`
			if questDone[id] == false and canClaimQuest then
				UI.toast(`✅ Quest complete: {text}!`, "good", NUDGE_SECONDS, {
					text = "CLAIM",
					onTap = RewardsUI.openQuests,
				})
			end
			questDone[id] = done
		end
	end
	renderQuests(quests.daily, dailyQuestCards, "daily")
	renderQuests(quests.weekly, weeklyQuestCards, "weekly")
	dailyNote.Text = `New quests in {hoursMinutes(RewardRules.untilNextDay(now))}`
		.. if quests.rerollReady then "  ·  🎲 1 free reroll today" else ""
	weeklyNote.Text = `New weekly quest in {daysHours(StatRules.untilNextWeek(now))}`
	questsTab.Text = if claimable > 0 then `📋 QUESTS ({claimable})` else "📋 QUESTS"
	anyReady = anyReady or claimable > 0

	-- the Storm Log
	local logReady = StormLogTab.render(snapshot, describe)
	logTab.Text = if logReady > 0 then `📖 LOG ({logReady})` else "📖 LOG"
	anyReady = anyReady or logReady > 0
	return anyReady, canClaim, readyGifts
end

-- The toasts: the daily reward once when you join (if it's ready), each
-- gift once when it's ready.
local function nudge(dailyReady: boolean, readyGifts: { number })
	if not dailyNudged then
		dailyNudged = true
		if dailyReady then
			UI.toast("🎁 Your daily reward is ready!", "good", NUDGE_SECONDS, {
				text = "OPEN",
				onTap = RewardsUI.open,
			})
		end
	end
	for _, index in readyGifts do
		if not giftNudged[index] and SettingsStore.get("showGiftReminders") then
			giftNudged[index] = true
			local minutes = Config.PLAYTIME_GIFTS[index].minutes
			UI.toast(`🎁 Your {minutes}-minute gift is ready!`, "good", NUDGE_SECONDS, {
				text = "OPEN",
				onTap = RewardsUI.open,
			})
		end
	end
end

-- After the first sale of a visit, non-members hear about the group once.
local function onSold()
	if groupNudged or player:GetAttribute(PassRules.GROUP) == true then
		return
	end
	groupNudged = true
	local percent = math.round(Config.GROUP_BONUS * 100)
	UI.toast(`Join {Config.GROUP_NAME} for +{percent}% Volts forever!`, "volt", NUDGE_SECONDS, {
		text = "OPEN",
		onTap = openAtGroup,
	})
end

local function heading(parent: Instance, order: number, text: string): TextLabel
	local label = UI.label({
		Title = true,
		Name = "Heading",
		LayoutOrder = order,
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		Size = UDim2.new(1, -12, 0, HEADING),
		Parent = parent,
	})
	UI.maxText(label, 24)
	return label
end

-- A grid of `count` cards (fitCards sizes it).
local function grid(parent: Instance, order: number, name: string, count: number): Grid
	local frame = UI.make(Instance.new("Frame"), {
		Name = name,
		LayoutOrder = order,
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local layout = UI.make(Instance.new("UIGridLayout"), {
		CellPadding = UDim2.fromOffset(GAP, GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = frame,
	})
	return { frame = frame, layout = layout, count = count }
end

-- The server asks once, after a daily claim: "Remind me when my daily
-- reward is ready?" Only shown if Roblox lets this player be asked (13+,
-- not already on, not asked in the last 30 days); YES opens Roblox's own
-- prompt, which is the real yes or no.
local function askAboutReminders()
	local ok, canAsk = pcall(function()
		return ExperienceNotificationService:CanPromptOptInAsync()
	end)
	if not ok or not canAsk then
		print(`[RewardsUI] not asking about reminders ({if ok then "Roblox says no" else canAsk})`)
		return
	end
	UI.toast("🔔 Remind me when my daily reward is ready?", "info", 12, {
		text = "YES",
		onTap = function()
			Net.get("NotifyOptIn"):FireServer() -- the server only queues reminders after a YES
			local shown, err = pcall(function()
				ExperienceNotificationService:PromptOptIn()
			end)
			if not shown then
				warn(`[RewardsUI] the notifications prompt failed: {err}`)
			end
		end,
	})
end

-- "Got +1.2K Volts and 2x Volts for 10 min!"
local function onRewarded(rewarded: Types.Rewarded)
	local parts: { string } = {}
	if rewarded.volts > 0 then
		table.insert(parts, `+{Format.abbreviate(rewarded.volts)} ⚡ Volts`)
	end
	for _, boost in rewarded.boosts do
		local def = BoostRules.def(boost.key)
		if def then
			table.insert(parts, `{def.name} for {boost.minutes} min`)
		end
	end
	Sfx.play("daily")
	Celebrate.sparks()
	UI.toast(`🎁 You got {table.concat(parts, " and ")}!`, "good", 5)
	if #rewarded.swapped > 0 then
		UI.toast("You already own that boost's pass, so it paid Volts instead", "info", 5)
	end
end

function RewardsUI.init()
	local _, root = Layout.screen("StormBottlerRewards", 5)
	local window = UI.window(root, "RewardsPanel", "🎁 REWARDS", PINK, Vector2.new(680, 560))
	panel = window.panel
	-- the four tabs along the top
	local tabBar = UI.make(Instance.new("Frame"), {
		Name = "Tabs",
		Size = UDim2.new(1, 0, 0, TAB_HEIGHT),
		BackgroundTransparency = 1,
		Parent = window.body,
	})
	UI.make(Instance.new("UIGridLayout"), {
		CellSize = UDim2.new(1 / 4, -6, 1, 0),
		CellPadding = UDim2.fromOffset(6, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = tabBar,
	})
	-- each tab is one scrolling column: it all fits on a monitor, and
	-- scrolls on a phone
	local function page(name: string): ScrollingFrame
		local frame = UI.make(Instance.new("ScrollingFrame"), {
			Name = name,
			Position = UDim2.fromOffset(0, TAB_HEIGHT + 8),
			Size = UDim2.new(1, 0, 1, -(TAB_HEIGHT + 8)),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 6,
			Parent = window.body,
		})
		UI.make(Instance.new("UIListLayout"), {
			Padding = UDim.new(0, GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = frame,
		})
		-- room under the last card when scrolled to the bottom
		UI.make(Instance.new("UIPadding"), {
			PaddingTop = UDim.new(0, 2),
			PaddingBottom = UDim.new(0, 12),
			PaddingLeft = UDim.new(0, 2),
			Parent = frame,
		})
		return frame
	end
	list = page("List")
	questList = page("Quests")
	logList = page("Log")
	topList = page("Top")
	local pages: { [Tab]: ScrollingFrame } =
		{ rewards = list, quests = questList, log = logList, top = topList }
	local function tab(order: number, text: string, which: Tab): TextButton
		local names: { [Tab]: string } =
			{ rewards = "RewardsTab", quests = "QuestsTab", log = "LogTab", top = "TopTab" }
		local button = UI.button({
			Name = names[which],
			Text = text,
			LayoutOrder = order,
			BackgroundColor3 = COLORS.panelDark,
			Parent = tabBar,
		})
		UI.maxText(button, 18)
		button.Activated:Connect(function()
			if not pages[which].Visible then
				UI.pop(button)
				Sfx.play("tab")
				selectTab(which)
			end
		end)
		return button
	end
	rewardsTab = tab(1, "🎁 REWARDS", "rewards")
	questsTab = tab(2, "📋 QUESTS", "quests")
	logTab = tab(3, "📖 LOG", "log")
	topTab = tab(4, "🏆 TOP", "top")

	-- the TOP tab (Lib/LeaderboardTab)
	LeaderboardTab.build(topList)

	-- the LOG tab (Lib/StormLogTab)
	StormLogTab.build(logList, RewardsUI.openLog)

	-- the QUESTS tab
	heading(questList, 1, "📋 DAILY QUESTS")
	for index = 1, Config.QUESTS.daily do
		table.insert(dailyQuestCards, buildQuestCard(questList, 1 + index, "daily", index))
	end
	dailyNote = UI.label({
		Name = "DailyNote",
		LayoutOrder = 10,
		Text = "",
		TextColor3 = COLORS.volt,
		Size = UDim2.new(1, -12, 0, 22),
		Parent = questList,
	})
	UI.maxText(dailyNote, 18)
	heading(questList, 11, "🏆 WEEKLY QUEST")
	for index = 1, Config.QUESTS.weekly do
		table.insert(weeklyQuestCards, buildQuestCard(questList, 11 + index, "weekly", index))
	end
	weeklyNote = UI.label({
		Name = "WeeklyNote",
		LayoutOrder = 20,
		Text = "",
		TextColor3 = COLORS.volt,
		Size = UDim2.new(1, -12, 0, 22),
		Parent = questList,
	})
	UI.maxText(weeklyNote, 18)
	UI.onLayout(fitQuests)
	selectTab("rewards")

	heading(list, 1, "📅 DAILY STREAK")
	dayGrid = grid(list, 2, "Days", #Config.DAILY_REWARDS)
	local claimDaily = Net.get("ClaimDaily")
	for day = 1, #Config.DAILY_REWARDS do
		table.insert(
			dayCards,
			buildCard(dayGrid.frame, day, `DAY {day}`, false, function()
				claimDaily:FireServer()
			end)
		)
	end
	nextLabel = UI.label({
		Name = "Next",
		LayoutOrder = 3,
		Text = "",
		TextColor3 = COLORS.volt,
		Size = UDim2.new(1, -12, 0, 22),
		Parent = list,
	})
	UI.maxText(nextLabel, 18)

	heading(list, 4, "⏱ PLAYTIME GIFTS (today)")
	giftGrid = grid(list, 5, "Gifts", #Config.PLAYTIME_GIFTS)
	local claimGift = Net.get("ClaimGift")
	for index, gift in Config.PLAYTIME_GIFTS do
		table.insert(
			giftCards,
			buildCard(giftGrid.frame, index, `{gift.minutes} MIN`, true, function()
				claimGift:FireServer(index)
			end)
		)
	end
	UI.onLayout(fitCards)

	heading(list, 6, `👥 {string.upper(Config.GROUP_NAME)} GROUP`)
	local groupCard = UI.make(Instance.new("Frame"), {
		Name = "Group",
		LayoutOrder = 7,
		BackgroundColor3 = COLORS.panelDark,
		Size = UDim2.new(1, -12, 0, GROUP_HEIGHT),
		Parent = list,
	})
	UI.corner(groupCard, UDim.new(0, 12))
	UI.stroke(groupCard, 3, Config.GROUP_COLOR)
	groupText = UI.label({
		Title = true,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Position = UDim2.new(0, 14, 0, 8),
		Size = UDim2.new(0.68, -14, 1, -16),
		Parent = groupCard,
	})
	UI.maxText(groupText, 22)
	groupButton = UI.button({
		Name = "Join",
		Text = "JOIN",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0.28, 0, 0, 48),
		BackgroundColor3 = COLORS.storm,
		Parent = groupCard,
	})
	UI.maxText(groupButton, 24)
	groupButton.Activated:Connect(function()
		UI.pop(groupButton)
		joinGroup()
	end)
	renderGroup()

	heading(list, 8, "✉️ INVITE FRIENDS")
	local inviteCard = UI.make(Instance.new("Frame"), {
		Name = "Invite",
		LayoutOrder = 9,
		BackgroundColor3 = COLORS.panelDark,
		Size = UDim2.new(1, -12, 0, GROUP_HEIGHT),
		Parent = list,
	})
	UI.corner(inviteCard, UDim.new(0, 12))
	UI.stroke(inviteCard, 3, PINK)
	local reward = Config.BOOST_PRODUCTS[1]
	for _, product in Config.BOOST_PRODUCTS do
		if product.key == Config.INVITES.inviterReward then
			reward = product
		end
	end
	local inviteText = UI.label({
		Title = true,
		Text = `New players you invite get a welcome gift, you get a {reward.name} once they've played {Config.INVITES.playMinutes} min. Friends here: +{math.round(
			Config.FRIENDS.perFriend * 100
		)}% Volts each`,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Position = UDim2.new(0, 14, 0, 8),
		Size = UDim2.new(0.68, -14, 1, -16),
		Parent = inviteCard,
	})
	UI.maxText(inviteText, 18)
	local inviteButton = UI.button({
		Name = "InviteButton",
		Text = "INVITE",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0.28, 0, 0, 48),
		BackgroundColor3 = PINK,
		Parent = inviteCard,
	})
	UI.maxText(inviteButton, 24)
	inviteButton.Activated:Connect(function()
		UI.pop(inviteButton)
		invite()
	end)
	player:GetAttributeChangedSignal(PassRules.GROUP):Connect(function()
		renderGroup()
		local percent = math.round(Config.GROUP_BONUS * 100)
		if joinTapped and player:GetAttribute(PassRules.GROUP) == true then
			Sfx.play("purchase")
			Celebrate.sparks()
			UI.toast(`Group bonus active: +{percent}% Volts!`, "good", 5)
		end
	end)
end

function RewardsUI.start()
	Net.get("Rewarded").OnClientEvent:Connect(onRewarded)
	Net.get("Sold").OnClientEvent:Connect(onSold)
	Net.get("NotifyOptIn").OnClientEvent:Connect(function()
		task.delay(3, askAboutReminders) -- after the reward's celebration
	end)
	State.Changed:Connect(function()
		render()
	end)
	-- countdowns, the menu's dot and the nudges
	while true do
		local nowReady, dailyReady, readyGifts = render()
		if State.current then
			nudge(dailyReady, readyGifts)
		end
		if nowReady ~= ready then
			ready = nowReady
			if ready then
				Sfx.play("gift_ready")
			end
			RewardsUI.ReadyChanged:Fire(ready)
		end
		task.wait(1)
	end
end

return RewardsUI
