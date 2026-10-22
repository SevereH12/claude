--!strict
-- Offers at the right moment, the free 2x Volts trial, and purchase thanks.
--
-- Fair play: an offer is a small card (the pass's icon, one line, SEE and
-- ✕) that never blocks play, hides itself after a while, and never opens a
-- purchase window: SEE opens the store at that pass (BoostsUI.openAt), and
-- only the store's BUY prompts. When one may show is Util/Store.canOffer:
-- never in a session's first 3 minutes, at most one every 5 minutes, each
-- once a session, never over the menu or a panel, never for an owned pass.
--
--   Triggers: a full bottle far from a sell station (Remote Sell, or Big
--   Bottles for Remote Sell owners; the locked SELL by the bottle bar shows
--   then too), a sale without 2x Volts (what 2x would really have added,
--   from the server), hiring a researcher or a level-up (Lab Grant), an
--   Analyst assay (Lucky Charges).
--   The free trial: from the 3rd sale of a session, once ever; TRY starts it
--   (StartTrial, checked by Systems/Store: a 2x Volts boost). When any 2x
--   Volts boost ends (the trial, a reward), a card says what it earned.
--   Thanks: when anyone buys a pass, a chat line for everyone; the buyer
--   (of a pass, a Volts pack, a boost or a Server Storm) gets sparks and a
--   toast.
-- Offers shown and tapped are reported for the stats (StoreEvent).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BoostRules = require(ReplicatedStorage.Shared.Util.Boosts)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local PassRules = require(ReplicatedStorage.Shared.Util.Passes)
local Store = require(ReplicatedStorage.Shared.Util.Store)
local Types = require(ReplicatedStorage.Shared.Types)
local Celebrate = require(script.Parent.Parent.Lib.Celebrate)
local Layout = require(script.Parent.Parent.Lib.Layout)
local UI = require(script.Parent.Parent.Lib.UI)
local BoostsUI = require(script.Parent.BoostsUI)
local HUD = require(script.Parent.HUD)
local Menu = require(script.Parent.Menu)
local State = require(script.Parent.State)

local COLORS = UI.COLORS
local CARD_HEIGHT = 112
local SLIDE = 30 -- design pixels the card slides in from
local OFFER_SECONDS = 20 -- an offer hides itself after this
local SUMMARY_SECONDS = 12
local CHECK_INTERVAL = 0.5
local SELL_TAG = "SellArea"

local Offers = {}

local player = Players.LocalPlayer
local storeEvent: RemoteEvent
local card: Frame
local cardImage: ImageLabel
local cardEmoji: TextLabel
local cardText: TextLabel
local cardAction: TextButton
local onAction: (() -> ())? = nil
local token = 0 -- bumped whenever the card changes, so old timers leave it alone

local offerState: Store.OfferState = { sessionStart = os.clock(), lastOfferAt = nil, shown = {} }
local sales = 0
local lastTrialUsed: boolean? = nil -- nil until the first snapshot
local doubleBaseline: number? = nil -- store.boostEarned when the running 2x boost began
local researchLevels: { [string]: number }? = nil -- role -> level, to spot hires and level-ups

local function uiOpen(): boolean
	return Menu.isOpen() or UI.anyPanelOpen()
end

-- Does the player already have what this offer sells? ("Trial": used, or
-- they own 2x Volts.) True until the first snapshot, so nothing shows early.
local function owns(key: string): boolean
	local snapshot = State.current
	if not snapshot then
		return true
	end
	if key == "Trial" then
		return snapshot.trialUsed or snapshot.passes.DoubleVolts == true
	end
	return snapshot.passes[key] == true
end

-- Where the card goes: the top of the menu card's place (free whenever the
-- menu is closed, and offers never show while it's open).
local function slot(): (number, number, number)
	local rect = Layout.hud.card
	return rect.x, rect.y, rect.w
end

local function hide()
	if not card.Visible then
		return
	end
	token += 1
	local mine = token
	onAction = nil
	local x, y = slot()
	local out = TweenService:Create(card, UI.TWEEN.fast, {
		Position = UDim2.fromOffset(x - SLIDE, y),
	})
	out.Completed:Once(function()
		if token == mine then
			card.Visible = false
		end
	end)
	out:Play()
end

-- Shows the card with `iconKey`'s icon (a pass key), a line of text and an
-- action button; it hides itself after `seconds`.
local function show(
	iconKey: string,
	text: string,
	actionText: string,
	action: () -> (),
	seconds: number
)
	token += 1
	local mine = token
	local pass = PassRules.def(iconKey)
	local image = if pass then pass.image else 0
	cardImage.Visible = image ~= 0
	cardImage.Image = if image ~= 0 then `rbxassetid://{image}` else ""
	cardEmoji.Visible = image == 0
	cardEmoji.Text = if pass then pass.icon else "⚡"
	cardText.Text = text
	cardAction.Text = actionText
	onAction = action
	local x, y, w = slot()
	card.Size = UDim2.fromOffset(w, CARD_HEIGHT)
	card.Position = UDim2.fromOffset(x - SLIDE, y)
	card.Visible = true
	TweenService:Create(card, UI.TWEEN.open, { Position = UDim2.fromOffset(x, y) }):Play()
	task.delay(seconds, function()
		if token == mine then
			hide()
		end
	end)
end

-- Counts an offer as shown (canOffer's once-a-session and 5-minute rules).
local function mark(key: string)
	offerState.shown[key] = true
	offerState.lastOfferAt = os.clock()
	storeEvent:FireServer("offerShown", key)
end

local function allowed(key: string): boolean
	return not card.Visible and Store.canOffer(offerState, key, os.clock(), uiOpen(), owns(key))
end

-- Offers a pass if the rules allow it now: SEE opens the store at it.
local function offer(key: string, text: string)
	if not allowed(key) then
		return
	end
	mark(key)
	show(key, text, "SEE", function()
		storeEvent:FireServer("offerTapped", key)
		BoostsUI.openAt(key)
	end, OFFER_SECONDS)
end

-- The free 2x Volts trial: TRY asks the server to start it. True if shown.
local function offerTrial(): boolean
	if not allowed("Trial") then
		return false
	end
	mark("Trial")
	local minutes = math.round(Config.STORE.trialSeconds / 60)
	show("DoubleVolts", `Try 2x Volts free for {minutes} minutes of play!`, "TRY", function()
		storeEvent:FireServer("offerTapped", "Trial")
		Net.get("StartTrial"):FireServer()
	end, OFFER_SECONDS)
	return true
end

-- The locked SELL by the bottle bar opens the Remote Sell card.
local function openRemoteSell()
	storeEvent:FireServer("offerTapped", "RemoteSell")
	BoostsUI.openAt("RemoteSell")
end

-- How far the player is from the nearest sell station (nil if none is
-- loaded or they have no character).
local function distanceToSell(): number?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local nearest: number? = nil
	for _, area in CollectionService:GetTagged(SELL_TAG) do
		if area:IsA("BasePart") then
			local flat = (area.Position - root.Position) * Vector3.new(1, 0, 1)
			local distance = math.max(0, flat.Magnitude - math.max(area.Size.X, area.Size.Z) / 2)
			nearest = if nearest then math.min(nearest, distance) else distance
		end
	end
	return nearest
end

-- Every CHECK_INTERVAL: the full-bottle nudge, the trial's summary, and no
-- offer over the menu or a panel.
local function check()
	if card.Visible and uiOpen() then
		hide()
	end
	local snapshot = State.current
	if not snapshot then
		return
	end
	local full = snapshot.capacity > 0 and snapshot.chargeCount >= snapshot.capacity
	local distance = if full then distanceToSell() else nil
	local far = distance ~= nil and distance > Config.STORE.offerFarFromSell
	HUD.setSellNudge(if far and not snapshot.passes.RemoteSell then openRemoteSell else nil)
	if far then
		if snapshot.passes.RemoteSell then
			offer("BigBottles", "Bottle full again? Big Bottles hold 50% more")
		else
			offer("RemoteSell", "Bottle full! Remote Sell sells it from right here")
		end
	end

	-- a 2x Volts boost (the trial, a reward) is over: what it earned (not an
	-- offer: once per boost, when nothing's open, and only if it paid)
	local doubleEnds = snapshot.boosts.DoubleVolts
	local doubling = doubleEnds ~= nil
		and doubleEnds > workspace:GetServerTimeNow()
		and not snapshot.passes.DoubleVolts
	local baseline = doubleBaseline
	if doubling and not baseline then
		doubleBaseline = snapshot.store.boostEarned
	elseif not doubling and baseline and not uiOpen() then
		doubleBaseline = nil
		local earned = snapshot.store.boostEarned - baseline
		if earned > 0 then
			show(
				"DoubleVolts",
				`Your 2x Volts boost earned you +{Format.abbreviate(earned)} Volts!`,
				"SEE",
				function()
					BoostsUI.openAt("DoubleVolts")
				end,
				SUMMARY_SECONDS
			)
		end
	end
end

local function onSold(_earned: number, _count: number, missed: number?)
	sales += 1
	if sales >= Config.STORE.trialAfterSales and offerTrial() then
		return
	end
	if missed and missed > 0 then
		offer("DoubleVolts", `That sale would have paid +{Format.abbreviate(missed)} with 2x Volts`)
	end
end

local function onLanded(landed: Types.StrikeLanded)
	if table.find(landed.assayed, player.UserId) then
		local percent = math.round(Config.PASS_VALUES.luckyChance * 100)
		offer("LuckyCharges", `Like doubles? {percent}% of catches with Lucky Charges`)
	end
end

local function onState(snapshot: Types.Snapshot)
	-- a researcher hired or levelled up
	local levels: { [string]: number } = {}
	local grew = false
	for role, save in snapshot.researchers do
		levels[role] = save.level
		local before = if researchLevels then researchLevels[role] else save.level
		if before == nil or save.level > before then
			grew = true
		end
	end
	researchLevels = levels
	if grew then
		offer("LabGrant", "Lab Grant: researchers set up instantly and learn 2x faster")
	end

	-- the trial just started
	if lastTrialUsed == false and snapshot.trialUsed then
		hide()
		UI.toast("Free 2x Volts trial: every sale pays double!", "good", 4)
	end
	lastTrialUsed = snapshot.trialUsed
end

-- Someone bought a pass (everyone hears), or the local player a Volts
-- pack, a boost or a Server Storm.
local function onPurchased(userId: number, key: string, volts: number)
	local buyer = Players:GetPlayerByUserId(userId)
	local pass = PassRules.def(key)
	if pass and buyer then
		UI.chatLine(`⚡ {buyer.DisplayName} got {pass.name}!`)
	end
	if userId ~= player.UserId then
		return
	end
	Celebrate.sparks()
	if pass then
		UI.toast(`Thank you! {pass.name} is yours`, "good", 5)
		return
	end
	-- a boost for yourself (FOR ME) or a Server Storm
	local boost = BoostRules.product(key)
	if boost then
		UI.toast(
			if boost.serverStorm
				then "Thank you! Your Server Storm is on for everyone here"
				else `Thank you! {boost.name} is on`,
			"good",
			5
		)
		return
	end
	for _, pack in Config.VOLT_PACKS do
		if pack.key == key then
			UI.toast(`Thank you! +{Format.abbreviate(volts)} ⚡ Volts from {pack.name}`, "good", 5)
		end
	end
end

local function buildCard()
	local _, root = Layout.screen("StormBottlerOffers", 3)
	card = UI.panel({
		Name = "OfferCard",
		Visible = false,
		Parent = root,
	})
	cardImage = UI.make(Instance.new("ImageLabel"), {
		Name = "Icon",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(56, 56),
		Parent = card,
	})
	UI.corner(cardImage, UDim.new(0, 10))
	cardEmoji = UI.label({
		Title = true,
		Text = "",
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(56, 56),
		Parent = card,
	})
	UI.maxText(cardEmoji, 44)
	cardText = UI.label({
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Position = UDim2.fromOffset(76, 10),
		Size = UDim2.new(1, -122, 0, 56),
		Parent = card,
	})
	UI.maxText(cardText, 20)
	local close = UI.button({
		Name = "Close",
		Text = "✕",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(36, 36),
		BackgroundColor3 = COLORS.panelDark,
		Parent = card,
	})
	close.Activated:Connect(function()
		UI.pop(close)
		hide()
	end)
	cardAction = UI.button({
		Name = "Action",
		Text = "SEE",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, -10),
		Size = UDim2.fromOffset(120, 36),
		BackgroundColor3 = COLORS.green,
		Parent = card,
	})
	UI.maxText(cardAction, 20)
	cardAction.Activated:Connect(function()
		local action = onAction
		UI.pop(cardAction)
		hide()
		if action then
			action()
		end
	end)
	Layout.Changed:Connect(function()
		if card.Visible then
			local x, y, w = slot()
			card.Size = UDim2.fromOffset(w, CARD_HEIGHT)
			card.Position = UDim2.fromOffset(x, y)
		end
	end)
end

function Offers.init()
	storeEvent = Net.get("StoreEvent")
	buildCard()
end

function Offers.start()
	Net.get("Sold").OnClientEvent:Connect(onSold)
	Net.get("StrikeLanded").OnClientEvent:Connect(onLanded)
	Net.get("Purchased").OnClientEvent:Connect(onPurchased)
	if State.current then
		onState(State.current)
	end
	State.Changed:Connect(onState)
	while true do
		task.wait(CHECK_INTERVAL)
		check()
	end
end

return Offers
