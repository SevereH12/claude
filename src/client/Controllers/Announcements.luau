--!strict
-- News for everyone in the server (the Announcement remote):
--   "storm" (buyer, seconds left, started): someone started a Server Storm
--     or added to one (Systems/Boosts): a big banner and a chat line, "⚡
--     Alex started a SERVER STORM! 2x Volts for everyone, 15:00". The HUD's
--     chip shows it while it lasts.
--   "gifted" (giver, what, receiver): a gift arrived in this server: "🎁
--     Alex gifted VIP to Sam" in the chat (Systems/Gifts).
--   "giftSent" (giver): someone here sent a gift to a player in another
--     server, or offline: "🎁 Alex sent a gift!" in the chat.
--   "surge" (top contributor or "", seconds left): the server goal was
--     filled (Systems/ServerGoal): a big "SERVER SURGE!" banner and a chat
--     line. The HUD's server goal meter shows its time left.
--   "rainbow" (catcher, boost): someone caught a Rainbow bolt
--     (Systems/Strikes): "🌈 Alex caught a RAINBOW bolt! x25 + 5 min Lucky"
--     in the chat.
-- Joining while a storm is on brings a toast saying so.
-- Also banners for the weather (Controllers/Storm, Util/Weather): a
-- Supercell's 30 s warning and its start, and a scheduled event starting
-- (or already on when you join).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoostRules = require(ReplicatedStorage.Shared.Util.Boosts)
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local Weather = require(ReplicatedStorage.Shared.Util.Weather)
local SettingsStore = require(script.Parent.Parent.Lib.SettingsStore)
local Sfx = require(script.Parent.Parent.Lib.Sfx)
local UI = require(script.Parent.Parent.Lib.UI)
local Storm = require(script.Parent.Storm)
local ZoneBanner = require(script.Parent.ZoneBanner)

local STORM_COLOR = Color3.fromRGB(190, 140, 255)
local SUPERCELL_COLOR = Color3.fromRGB(160, 90, 255)
local EVENT_COLOR = Color3.fromRGB(255, 200, 40)
local SURGE_COLOR = Color3.fromRGB(90, 220, 255)
local BANNER_SECONDS = 4
local JOIN_DELAY = 4 -- seconds after joining before the "storm is on" toast

local Announcements = {}

local function clock(seconds: number): string
	local whole = math.ceil(seconds)
	return string.format("%d:%02d", whole // 60, whole % 60)
end

-- Gift and Server Storm lines in the chat (unless SETTINGS > Accessibility &
-- HUD > Chat announcements is off).
local function chat(text: string)
	if SettingsStore.get("showAnnouncements") then
		UI.chatLine(text)
	end
end

local function onAnnouncement(kind: unknown, a: unknown, b: unknown, c: unknown)
	if kind == "storm" and typeof(a) == "string" and typeof(b) == "number" then
		local started = c == true
		local left = clock(b)
		Sfx.play(if started then "server_storm" else "boost_start")
		local what = if started then "started a" else "added to the"
		chat(`⚡ {a} {what} SERVER STORM! 2x Volts for everyone, {left}`)
		local how = if started then "started it" else "added more"
		ZoneBanner.show(
			"⚡ SERVER STORM!",
			`{a} {how}: 2x Volts for everyone, {left}`,
			STORM_COLOR,
			BANNER_SECONDS
		)
	elseif
		kind == "gifted"
		and typeof(a) == "string"
		and typeof(b) == "string"
		and typeof(c) == "string"
	then
		chat(`🎁 {a} gifted {b} to {c}`)
	elseif kind == "surge" and typeof(a) == "string" and typeof(b) == "number" then
		local multiplier = Config.SERVER_GOAL.multiplier
		Sfx.play("server_storm")
		local thanks = if a ~= "" then ` Top helper: {a}.` else ""
		chat(`⚡ SERVER GOAL REACHED! SERVER SURGE: {multiplier}x Volts for everyone, {clock(b)}`)
		ZoneBanner.show(
			"⚡ SERVER SURGE!",
			`Server goal reached: {multiplier}x Volts for everyone, {clock(b)}.{thanks}`,
			SURGE_COLOR,
			BANNER_SECONDS
		)
	elseif kind == "giftSent" and typeof(a) == "string" then
		chat(`🎁 {a} sent a gift!`)
	elseif kind == "rainbow" and typeof(a) == "string" and typeof(b) == "string" then
		local rainbow = Weather.boltDef("Rainbow")
		local times = if rainbow then rainbow.multiplier else 25
		local minutes = if rainbow then rainbow.boostMinutes or 5 else 5
		chat(`🌈 {a} caught a RAINBOW bolt! x{times} + {minutes} min {b}`)
	end
end

-- Supercell banners: the warning (once per Supercell) and its start.
local warnedFor: number? = nil
local lastSupercell = false
local function onStorm(state: Types.StormState)
	if state.supercellAt and warnedFor ~= state.supercellAt then
		warnedFor = state.supercellAt
		local seconds = math.max(0, math.ceil(state.supercellAt - workspace:GetServerTimeNow()))
		Sfx.play("boost_start")
		ZoneBanner.show(
			"⛈️ SUPERCELL INCOMING",
			`Get into a storm zone! It hits in {seconds}s`,
			SUPERCELL_COLOR,
			BANNER_SECONDS
		)
	end
	local supercell = state.phase == "Storm" and state.supercell == true
	if supercell and not lastSupercell then
		Sfx.play("server_storm")
		ZoneBanner.show(
			"⛈️ SUPERCELL!",
			`Twice the strikes and {Config.SUPERCELL.goldenMultiplier}x the golden bolts`,
			SUPERCELL_COLOR,
			BANNER_SECONDS
		)
	end
	lastSupercell = supercell
end

-- A banner when a scheduled event starts (or is on when you join).
local function watchEvents()
	local shown: { [string]: boolean } = {}
	while true do
		local on: { [string]: boolean } = {}
		for _, active in Weather.liveEvents() do
			local name = active.event.name
			on[name] = true
			if not shown[name] then
				ZoneBanner.show(
					`🎉 {string.upper(name)}`,
					active.event.banner,
					EVENT_COLOR,
					BANNER_SECONDS
				)
				UI.toast(`🎉 {name}: {active.event.banner}`, "good", 6)
			end
		end
		shown = on
		task.wait(5)
	end
end

function Announcements.init()
	Net.get("Announcement").OnClientEvent:Connect(onAnnouncement)
	Storm.Changed:Connect(onStorm)
end

function Announcements.start()
	task.wait(JOIN_DELAY)
	local left = BoostRules.stormLeft(
		workspace:GetAttribute(BoostRules.STORM_ENDS),
		workspace:GetServerTimeNow()
	)
	if left > 0 then
		UI.toast(
			`🌩️ A SERVER STORM is on: 2x Volts for everyone for {clock(left)}!`,
			"good",
			6
		)
	end
	watchEvents()
end

return Announcements
