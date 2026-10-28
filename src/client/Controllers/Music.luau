--!strict
-- Background music that follows the weather: the playlist for the world
-- you're in and the storm phase (Config.MUSIC[world].Calm / .Storm),
-- shuffled with no repeats until the list is used up. A phase or world
-- change crossfades over Config.MUSIC_FADE seconds. Everything plays in the
-- Music SoundGroup, so the SETTINGS slider and Sfx's ducking apply.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Portals = require(ReplicatedStorage.Shared.Util.Portals)
local Types = require(ReplicatedStorage.Shared.Types)
local Sfx = require(script.Parent.Parent.Lib.Sfx)
local Storm = require(script.Parent.Storm)

local player = Players.LocalPlayer
local LOAD_TIMEOUT = 10 -- seconds: a track that won't load is skipped

local Music = {}

local decks: { Sound } = {} -- two Sounds, crossfaded
local active = 1
local playlist = "" -- "<world>:<phase>" now playing
local bags: { [string]: { number } } = {} -- what's left of each shuffled list
local lastPlayed: { [string]: number } = {}
local token = 0 -- bumps on every track change, so an old track's end is ignored
local random = Random.new()

local function list(key: string): { number }
	local world, phase = string.match(key, "^(.-):(.+)$")
	local worlds = Config.MUSIC :: any
	local lists = worlds[world or ""] or worlds[Config.WORLDS[1].id]
	return (lists and lists[phase or "Calm"]) or {}
end

-- The next track of a playlist: shuffled, no repeats until all have played
-- (and not the one that just played, when a new round starts).
local function nextTrack(key: string): number?
	local bag = bags[key]
	if not bag or #bag == 0 then
		bag = table.clone(list(key))
		for i = #bag, 2, -1 do
			local j = random:NextInteger(1, i)
			bag[i], bag[j] = bag[j], bag[i]
		end
		if #bag > 1 and bag[#bag] == lastPlayed[key] then
			bag[1], bag[#bag] = bag[#bag], bag[1]
		end
		bags[key] = bag
	end
	local id = table.remove(bag)
	if id then
		lastPlayed[key] = id
	end
	return id
end

local function fade(sound: Sound, to: number, seconds: number, stopAfter: boolean)
	local tween =
		TweenService:Create(sound, TweenInfo.new(seconds, Enum.EasingStyle.Sine), { Volume = to })
	if stopAfter then
		tween.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed and sound.Volume <= 0.001 then
				sound:Stop()
			end
		end)
	end
	tween:Play()
end

local play: (key: string, seconds: number) -> ()

-- Starts the next track of `key` on the other deck, crossfading over
-- `seconds`. When it ends, the playlist moves on.
function play(key: string, seconds: number)
	token += 1
	local mine = token
	playlist = key
	local id = nextTrack(key)
	local old = decks[active]
	fade(old, 0, seconds, true)
	if not id then
		return
	end
	active = 3 - active
	local deck = decks[active]
	deck:Stop()
	deck.SoundId = `rbxassetid://{id}`
	deck.TimePosition = 0
	deck.Volume = 0
	deck:Play()
	fade(deck, 1, seconds, false)
	-- a track that never loads (removed, not allowed) is skipped
	task.delay(LOAD_TIMEOUT, function()
		if token == mine and not deck.IsLoaded then
			warn(`[Music] track {id} didn't load: skipping it`)
			play(key, 1)
		end
	end)
end

-- What should be playing now: this world's list for this weather.
local function wanted(): string
	local state: Types.StormState? = Storm.current
	local phase = if state and state.phase == "Storm" then "Storm" else "Calm"
	return `{Portals.worldOf(player).id}:{phase}`
end

local function update()
	local key = wanted()
	if key ~= playlist then
		play(key, Config.MUSIC_FADE)
	end
end

function Music.init()
	for index = 1, 2 do
		local deck = Instance.new("Sound")
		deck.Name = `MusicDeck{index}`
		deck.Volume = 0
		deck.SoundGroup = Sfx.group("Music")
		deck.Parent = game:GetService("SoundService")
		deck.Ended:Connect(function()
			-- the track finished: the next one of the same list
			if decks[active] == deck then
				play(playlist, 1)
			end
		end)
		decks[index] = deck
	end
end

function Music.start()
	Storm.Changed:Connect(update)
	player:GetAttributeChangedSignal(Portals.WORLD_ATTRIBUTE):Connect(update)
	update()
end

return Music
