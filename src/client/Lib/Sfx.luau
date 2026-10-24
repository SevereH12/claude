--!strict
-- The only code that plays sounds. Every sound is a SoundBank entry: a
-- region of one of a few uploaded sheets (tools/audio). Sfx.play is a 2D
-- sound (the UI, your own rewards), Sfx.playAt a 3D one at a point in the
-- world. Each sheet has a small pool of Sound instances that are reused, so
-- nothing is created per play.
--
-- Every sound plays in a SoundGroup (Music, Ambience, SFX, UI) whose volume
-- is Config.SOUND_MIX times the player's setting (the SETTINGS panel).

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)
local SoundBank = require(ReplicatedStorage.Shared.SoundBank)
local Types = require(ReplicatedStorage.Shared.Types)

local POOL_2D = 6 -- Sounds per sheet for 2D sounds
local POOL_3D = 8 -- and for 3D sounds (each in its own Attachment)
local MIN_GAP = 0.05 -- seconds: the same sound plays at most this often
local GAPS: { [string]: number } = { volts_tick = 0.08 } -- per-sound minimum gaps
local VARY = 0.04 -- ±4% random pitch on repeated sounds
local ROLLOFF_MIN, ROLLOFF_MAX = 12, 450 -- studs, for 3D sounds

export type Options = {
	pitch: number?, -- playback speed (1 = as made)
	volume: number?, -- times the sound's default volume
	offset: number?, -- seconds into the sound to start from
}

type Pool = { sounds: { Sound }, next: number }

local Sfx = {}

local groups: { [string]: SoundGroup } = {}
local pools2D: { [string]: Pool } = {}
local pools3D: { [string]: Pool } = {}
local lastAt: { [string]: number } = {}
local lastAny = -math.huge
local random = Random.new()
local settings: Types.SoundSettings? = nil

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
	lastAny = now
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

-- Every sound's name, sorted (the TEST panel's Sound board).
function Sfx.names(): { string }
	local names = {}
	for name in SoundBank do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function Sfx.length(name: string): number
	local entry = SoundBank[name]
	return if entry then entry.length else 0
end

-- The player's volume settings: the sliders scale Config.SOUND_MIX.
function Sfx.apply(newSettings: Types.SoundSettings)
	settings = newSettings
	local mute = if newSettings.muted then 0 else 1
	local mix = Config.SOUND_MIX
	group("Music").Volume = mix.Music * newSettings.musicVolume * mute
	group("Ambience").Volume = mix.Ambience * newSettings.ambienceVolume * mute
	group("SFX").Volume = mix.SFX * newSettings.sfxVolume * mute
	group("UI").Volume = mix.UI * newSettings.sfxVolume * mute
end

function Sfx.current(): Types.SoundSettings
	return settings or table.clone(Config.SOUND_SETTINGS)
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

Sfx.apply(table.clone(Config.SOUND_SETTINGS))

return Sfx
