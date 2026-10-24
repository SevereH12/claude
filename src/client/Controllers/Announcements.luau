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
-- Joining while a storm is on brings a toast saying so.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoostRules = require(ReplicatedStorage.Shared.Util.Boosts)
local Net = require(ReplicatedStorage.Shared.Net)
local SettingsStore = require(script.Parent.Parent.Lib.SettingsStore)
local Sfx = require(script.Parent.Parent.Lib.Sfx)
local UI = require(script.Parent.Parent.Lib.UI)
local ZoneBanner = require(script.Parent.ZoneBanner)

local STORM_COLOR = Color3.fromRGB(190, 140, 255)
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
	elseif kind == "giftSent" and typeof(a) == "string" then
		chat(`🎁 {a} sent a gift!`)
	end
end

function Announcements.init()
	Net.get("Announcement").OnClientEvent:Connect(onAnnouncement)
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
end

return Announcements
