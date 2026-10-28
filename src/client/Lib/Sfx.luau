--!strict
-- The only code that plays sounds. Every sound is a SoundBank entry: a
-- region of one of a few uploaded sheets (tools/audio). Sfx.play is a 2D
-- sound (the UI, your own rewards), Sfx.playAt a 3D one at a point in the
-- world. Each sheet has a small pool of Sound instances that are reused, so
-- nothing is created per play.
--
-- Every sound plays in a SoundGroup (Music, Ambience, SFX, UI) whose volume
-- is Config.SOUND_MIX times the player's settings (the SETTINGS panel's
-- Sound tab, Lib/SettingsStore). Big moments (fanfares, a jackpot, a Server
-- Storm) duck the music for a moment.
-- Sfx.loop makes a long-lived looping Sound (ambience) for its caller to fade.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local SoundBank = require(ReplicatedStorage.Shared.SoundBank)
local SettingsStore = require(script.Parent.SettingsStore)

local POOL_2D = 6 -- Sounds per sheet for 2D sounds
local POOL_3D = 8 -- and for 3D sounds (each in its own Attachment)
local MIN_GAP = 0.05 -- seconds: the same sound plays at most this often
local GAPS: { [string]: number } = { volts_tick = 0.08 } -- per-sound minimum gaps
local VARY = 0.04 -- ±4% random pitch on repeated sounds
local ROLLOFF_MIN, ROLLOFF_MAX = 12, 450 -- studs, for 3D sounds
-- these duck the music (Config.MUSIC_DUCK) while they play
local DUCKERS: { [string]: boolean } = {
	unlock = true,
	level_up = true,
	daily = true,
	gift_received = true,
	jackpot = true,
	server_storm = true,
}
local SOUND_KEYS: { [string]: boolean } = {
	masterVolume = true,
	musicVolume = true,
	sfxVolume = true,
	ambienceVolume = true,
	uiVolume = true,
	muted = true,
}
local DUCK_IN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local DUCK_OUT = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

export type Options = {
	pitch: number?, -- playback speed (1 = as made)
	volume: number?, -- times the sound's default volume
	offset: number?, -- seconds into the sound to start from
	background: boolean?, -- ambience: doesn't count for Sfx.recent
}

type Pool = { sounds: { Sound }, next: number }

local Sfx = {}

local groups: { [string]: SoundGroup } = {}
local pools2D: { [string]: Pool } = {}
local pools3D: { [string]: Pool } = {}
local lastAt: { [string]: number } = {}
local lastAny = -math.huge
local random = Random.new()
local duck = Instance.new("NumberValue") -- the music's ducking (1 = none)
duck.Value = 1
local duckToken = 0

local function group(name: string): SoundGroup
	local existing = groups[name]
	if existing then
		return existing
	end
	local made = SoundService:FindFirstChild(name)
	if not (made and made:IsA("SoundGroup")) then
		made = Instance.new("SoundGroup")
		made.Name = name
		made.Parent = SoundService
	end
	local soundGroup = made :: SoundGroup
	groups[name] = soundGroup
	return soundGroup
end

-- The SoundGroup a group name plays in (Part C's music uses "Music").
function Sfx.group(name: string): SoundGroup
	return group(name)
end

local function pool(entry: SoundBank.Entry, positional: boolean): Pool
	local pools = if positional then pools3D else pools2D
	local key = `{entry.file}:{entry.group}`
	local existing = pools[key]
	if existing then
		return existing
	end
	local made: Pool = { sounds = {}, next = 1 }
	for index = 1, if positional then POOL_3D else POOL_2D do
		local sound = Instance.new("Sound")
		sound.Name = `{entry.file}_{index}`
		sound.SoundId = entry.id
		sound.SoundGroup = group(entry.group)
		if positional then
			sound.RollOffMode = Enum.RollOffMode.InverseTapered
			sound.RollOffMinDistance = ROLLOFF_MIN
			sound.RollOffMaxDistance = ROLLOFF_MAX
			local attachment = Instance.new("Attachment")
			attachment.Name = `Sfx_{entry.file}_{index}`
			attachment.Parent = workspace.Terrain
			sound.Parent = attachment
		else
			sound.Parent = SoundService
		end
		table.insert(made.sounds, sound)
	end
	pools[key] = made
	return made
end

-- Dips the music (about -6 dB) for a moment under a big sound.
function Sfx.duck()
	duckToken += 1
	local mine = duckToken
	TweenService:Create(duck, DUCK_IN, { Value = Config.MUSIC_DUCK }):Play()
	task.delay(Config.MUSIC_DUCK_SECONDS, function()
		if duckToken == mine then
			TweenService:Create(duck, DUCK_OUT, { Value = 1 }):Play()
		end
	end)
end

-- A looping Sound of its own (ambience), silent until its caller fades it in
-- (Sfx.volumeOf(name) is its full volume). `parent`: a part or attachment
-- for a 3D loop; nil plays it 2D.
function Sfx.loop(name: string, parent: Instance?): Sound?
	local entry = SoundBank[name]
	if not entry then
		warn(`[Sfx] no sound called {name}`)
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = entry.id
	sound.Looped = true
	sound.Volume = 0
	sound.SoundGroup = group(entry.group)
	sound.Parent = parent or SoundService
	return sound
end

-- A sound's default volume.
function Sfx.volumeOf(name: string): number
	local entry = SoundBank[name]
	return if entry then entry.volume else 0
end

-- The next Sound in the pool, ready to play `name` (nil: unknown name or
-- played too recently).
local function prepare(
	name: string,
	positional: boolean,
	opts: Options?
): (Sound?, SoundBank.Entry?)
	local entry = SoundBank[name]
	if not entry then
		warn(`[Sfx] no sound called {name}`)
		return nil, nil
	end
	local now = os.clock()
	if now - (lastAt[name] or -math.huge) < (GAPS[name] or MIN_GAP) then
		return nil, nil
	end
	lastAt[name] = now
	if not (opts and opts.background) then
		lastAny = now
	end
	if DUCKERS[name] then
		Sfx.duck()
	end
	local list = pool(entry, positional)
	local sound = list.sounds[list.next]
	list.next = list.next % #list.sounds + 1
	local pitch = (opts and opts.pitch or 1)
	if entry.vary then
		pitch *= 1 + random:NextNumber(-VARY, VARY)
	end
	sound:Stop()
	sound.Looped = entry.loop
	sound.PlaybackRegionsEnabled = not entry.loop
	if not entry.loop then
		sound.PlaybackRegion = NumberRange.new(entry.start, entry.start + entry.length)
	end
	sound.TimePosition = entry.start + math.clamp(opts and opts.offset or 0, 0, entry.length)
	sound.PlaybackSpeed = pitch
	sound.Volume = entry.volume * (opts and opts.volume or 1)
	return sound, entry
end

-- Plays a sound with no position (UI, your own rewards).
function Sfx.play(name: string, opts: Options?): Sound?
	local sound = prepare(name, false, opts)
	if sound then
		sound:Play()
	end
	return sound
end

-- Plays a sound at a point in the world (strikes, thunder).
function Sfx.playAt(name: string, position: Vector3, opts: Options?): Sound?
	local sound = prepare(name, true, opts)
	if sound then
		local attachment = sound.Parent
		if attachment and attachment:IsA("Attachment") then
			attachment.WorldPosition = position
		end
		sound:Play()
	end
	return sound
end

-- Did any sound start in the last `seconds`? (A toast stays quiet when the
-- event it reports already made its own sound.)
function Sfx.recent(seconds: number): boolean
	return os.clock() - lastAny < seconds
end

function Sfx.length(name: string): number
	local entry = SoundBank[name]
	return if entry then entry.length else 0
end

-- The SoundGroups' volumes: Config.SOUND_MIX times the player's sliders
-- (Master and the group's own; Lib/SettingsStore), 0 when muted, and the
-- music ducked under big moments.
function Sfx.apply()
	local get = SettingsStore.get
	local master = if get("muted") then 0 else get("masterVolume")
	local mix = Config.SOUND_MIX
	group("Music").Volume = mix.Music * master * get("musicVolume") * duck.Value
	group("Ambience").Volume = mix.Ambience * master * get("ambienceVolume")
	group("SFX").Volume = mix.SFX * master * get("sfxVolume")
	group("UI").Volume = mix.UI * master * get("uiVolume")
end

-- Starts loading the sheets so the first sounds aren't late.
function Sfx.preload()
	local seen: { [string]: boolean } = {}
	local sounds: { Instance } = {}
	for _, entry in SoundBank do
		if not seen[entry.file] then
			seen[entry.file] = true
			table.insert(sounds, pool(entry, false).sounds[1])
		end
	end
	task.spawn(function()
		ContentProvider:PreloadAsync(sounds)
	end)
end

Sfx.apply()
duck.Changed:Connect(Sfx.apply)
SettingsStore.Changed:Connect(function(key: string)
	if SOUND_KEYS[key] then
		Sfx.apply()
	end
end)

return Sfx
