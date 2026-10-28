--!strict
-- Gameplay tips, as the player sees them (the list, triggers and texts:
-- Config.HINTS; the rules: Util/Hints; saving: Systems/Hints).
-- Once the new-player tutorial is over, every second this works out the
-- facts (from the snapshot and what happened this visit) and asks
-- Hints.pick for a tip. A tip shows as a small toast ("💡 ...", tap it to
-- open the right panel when it has one) and a gentle glow on its button
-- (the MENU button, then its tile once the menu is open, or a HUD piece).
-- Then it tells the server (HintSeen), which saves it so it never shows
-- again. Never during the tutorial, with "Gameplay tips" off in SETTINGS,
-- with a panel or the menu open, while catching in a storm, or AFK.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AscensionRules = require(ReplicatedStorage.Shared.Util.Ascension)
local Config = require(ReplicatedStorage.Shared.Config)
local HintRules = require(ReplicatedStorage.Shared.Util.Hints)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local TutorialRules = require(ReplicatedStorage.Shared.Util.Tutorial)
local Weather = require(ReplicatedStorage.Shared.Util.Weather)
local Zones = require(ReplicatedStorage.Shared.Util.Zones)
local SettingsStore = require(script.Parent.Parent.Lib.SettingsStore)
local UI = require(script.Parent.Parent.Lib.UI)
local BoostsUI = require(script.Parent.BoostsUI)
local HUD = require(script.Parent.HUD)
local Menu = require(script.Parent.Menu)
local ResearchUI = require(script.Parent.ResearchUI)
local RewardsUI = require(script.Parent.RewardsUI)
local SettingsUI = require(script.Parent.SettingsUI)
local ShopUI = require(script.Parent.ShopUI)
local State = require(script.Parent.State)
local Storm = require(script.Parent.Storm)
local TeleportUI = require(script.Parent.TeleportUI)

local SETTINGS = Config.HINTS
local TICK = 1 -- seconds between checks
local PULSE = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local RARE_RANGE = 2500 -- studs: a rare bolt this near counts as "seen" (same world)

local Hints = {}

local player = Players.LocalPlayer
local seenRemote: RemoteEvent
local joinedAt = os.clock()
local lastShown = -math.huge
local quietUntil = os.clock() + SETTINGS.firstDelay
local shown: { [string]: boolean } = {} -- shown this visit (before the server's snapshot says so)
local wasTutorial = false
local lastCatch = -math.huge
local lastCharges = -1
local sold = false
local sawRareBolt = false
local sawSupercell = false

-- the glow on the tip's button
local glow: Frame? = nil
local glowName: string? = nil
local glowUntil = 0

-- What tapping a tip opens (Config.HINTS list's `open`).
local OPENERS: { [string]: () -> () } = {
	shop = ShopUI.open,
	shopBoots = ShopUI.openBoots,
	research = ResearchUI.open,
	researchLog = ResearchUI.openLog,
	rewards = RewardsUI.open,
	quests = RewardsUI.openQuests,
	top = RewardsUI.openTop,
	boosts = BoostsUI.open,
	teleport = TeleportUI.open,
	settings = SettingsUI.open,
	sell = HUD.remoteSell,
}

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- A HUD piece by name ("RemoteSell", "ServerGoal"), if it's showing.
local function hudPiece(name: string): GuiObject?
	local gui = player:FindFirstChildOfClass("PlayerGui")
	local found = gui and gui:FindFirstChild(name, true)
	return if found and found:IsA("GuiObject") and found.Visible then found else nil
end

-- What should glow for `name` now: a menu tile glows on the MENU button
-- until the menu is open.
local function glowTarget(name: string): GuiObject?
	local tile = Menu.tile(name)
	if tile then
		return if Menu.isOpen() then tile else Menu.button()
	end
	return hudPiece(name)
end

local function clearGlow()
	if glow then
		glow:Destroy()
	end
	glow, glowName = nil, nil
end

-- Puts the glow on `target` (a soft pulsing outline over the whole button).
local function glowOn(target: GuiObject)
	if glow and glow.Parent == target then
		return
	end
	if glow then
		glow:Destroy()
	end
	local frame = UI.make(Instance.new("Frame"), {
		Name = "HintGlow",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 40,
	})
	-- cover the whole button: UI.button pads its contents
	local padding = target:FindFirstChildOfClass("UIPadding")
	if padding then
		local w = 1 - padding.PaddingLeft.Scale - padding.PaddingRight.Scale
		local h = 1 - padding.PaddingTop.Scale - padding.PaddingBottom.Scale
		frame.Position = UDim2.new(
			-padding.PaddingLeft.Scale / w,
			-padding.PaddingLeft.Offset,
			-padding.PaddingTop.Scale / h,
			-padding.PaddingTop.Offset
		)
		frame.Size = UDim2.fromScale(1 / w, 1 / h)
	end
	UI.corner(frame, UDim.new(0, 14))
	local stroke = UI.stroke(frame, 3, UI.COLORS.volt)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Transparency = 0.15
	TweenService:Create(stroke, PULSE, { Transparency = 0.75 }):Play()
	frame.Parent = target
	glow = frame
end

local function updateGlow()
	if not glowName or os.clock() > glowUntil then
		clearGlow()
		return
	end
	local target = glowTarget(glowName)
	if target then
		glowOn(target)
	elseif glow then
		glow:Destroy()
		glow = nil
	end
end

-- Is the player busy (no tip now)?
local function isBusy(snapshot: Types.Snapshot): boolean
	if UI.anyPanelOpen() or Menu.isOpen() or snapshot.afk ~= nil then
		return true
	end
	if os.clock() - lastCatch < SETTINGS.quietAfterCatch then
		return true
	end
	-- in a storm zone while it storms: they're catching
	local state = Storm.current
	local root = rootPart()
	return state ~= nil
		and state.phase == "Storm"
		and root ~= nil
		and Zones.at(root.Position) ~= nil
end

local function show(def: Types.HintDef)
	shown[def.id] = true
	lastShown = os.clock()
	seenRemote:FireServer(def.id)
	local opener = if def.open then OPENERS[def.open] else nil
	UI.toast(
		`💡 {HintRules.text(def)}`,
		"info",
		SETTINGS.showSeconds,
		if opener
			then { text = if def.open == "sell" then "SELL" else "OPEN", onTap = opener }
			else nil,
		true
	)
	if def.glow then
		glowName = def.glow
		glowUntil = os.clock() + SETTINGS.glowSeconds
	end
end

local function update()
	updateGlow()
	local snapshot = State.current
	if not snapshot then
		return
	end
	-- a catch (the bottle or the tank got more charges) keeps tips away a while
	local charges = snapshot.chargeCount + snapshot.tankCount
	if lastCharges >= 0 and charges > lastCharges then
		lastCatch = os.clock()
	end
	lastCharges = charges
	if Storm.current and Storm.current.supercell then
		sawSupercell = true
	end
	-- the tutorial running: wait until a while after it ends
	local tutorial = TutorialRules.isActive(snapshot.tutorialStep)
	if wasTutorial and not tutorial then
		quietUntil = os.clock() + SETTINGS.firstDelay
	end
	wasTutorial = tutorial

	local seen = table.clone(snapshot.hintsSeen or {})
	for id in shown do
		seen[id] = true
	end
	local session: HintRules.Session = {
		minutes = (os.clock() - joinedAt) / 60,
		canAscend = (AscensionRules.canAscend(snapshot)),
		groupMember = player:GetAttribute("GroupMember") == true,
		sold = sold,
		sawRareBolt = sawRareBolt,
		sawSupercell = sawSupercell,
		eventOn = #Weather.liveEvents() > 0,
	}
	local facts = HintRules.facts(snapshot, session)
	local def = HintRules.pick(seen, facts, {
		now = os.clock(),
		lastShown = lastShown,
		quietUntil = quietUntil,
		busy = isBusy(snapshot),
		enabled = SettingsStore.get("showTips") ~= false,
	})
	if def then
		show(def)
	end
end

function Hints.init()
	seenRemote = Net.get("HintSeen")
end

function Hints.start()
	Net.get("Sold").OnClientEvent:Connect(function()
		sold = true
	end)
	Net.get("StrikeWarning").OnClientEvent:Connect(function(warning: Types.StrikeWarning)
		local root = rootPart()
		if
			typeof(warning) == "table"
			and warning.boltType ~= nil
			and warning.boltType ~= "Normal"
			and root
			and (warning.position - root.Position).Magnitude < RARE_RANGE
		then
			sawRareBolt = true
		end
	end)
	while true do
		local ok, err = pcall(update)
		if not ok then
			warn(`[Hints] {err}`)
		end
		task.wait(TICK)
	end
end

return Hints
