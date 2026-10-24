--!strict
-- The world's background sound, in the Ambience SoundGroup:
--   calm  -> the wind-and-waves loop, quiet
--   storm -> the rain loop (the waves faintly under it), plus a wind gust or
--            a distant rumble every Config.AMBIENCE.eventEvery seconds
-- A phase change crossfades over Config.MUSIC_FADE seconds. Each world's
-- sell station (every part tagged SellArea) hums with the power plant's
-- electric loop, heard within Config.AMBIENCE.humRadius studs.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Sfx = require(script.Parent.Parent.Lib.Sfx)
local Storm = require(script.Parent.Storm)

local SELL_TAG = "SellArea" -- World/Kit.SELL_TAG
local GUST_UP = TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local GUST_DOWN = TweenInfo.new(3.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local Ambience = {}

local calm: Sound? = nil
local rain: Sound? = nil
local gust: Sound? = nil
local storming = false
local random = Random.new()

local function fadeTo(sound: Sound?, name: string, share: number, seconds: number)
	if not sound then
		return
	end
	local target = Sfx.volumeOf(name) * share
	if target > 0 and not sound.IsPlaying then
		sound:Play()
	end
	TweenService:Create(sound, TweenInfo.new(seconds, Enum.EasingStyle.Sine), { Volume = target })
		:Play()
end

local function setPhase(state: Types.StormState?, seconds: number)
	storming = state ~= nil and state.phase == "Storm"
	local mix = Config.AMBIENCE
	fadeTo(calm, "calm_loop", if storming then mix.stormCalmVolume else mix.calmVolume, seconds)
	fadeTo(rain, "rain_loop", if storming then mix.stormRainVolume else 0, seconds)
	if not storming then
		fadeTo(gust, "gust_loop", 0, seconds)
	end
end

-- A gust swells up and dies away; a rumble is far-off thunder.
local function stormEvent()
	if random:NextNumber() < 0.55 then
		local sound = gust
		if sound then
			if not sound.IsPlaying then
				sound.TimePosition = random:NextNumber(0, 15)
				sound:Play()
			end
			local up = TweenService:Create(
				sound,
				GUST_UP,
				{ Volume = Sfx.volumeOf("gust_loop") * random:NextNumber(0.6, 1) }
			)
			up.Completed:Once(function()
				task.wait(random:NextNumber(0.5, 1.5))
				if storming then
					TweenService:Create(sound, GUST_DOWN, { Volume = 0 }):Play()
				end
			end)
			up:Play()
		end
	else
		Sfx.play(`thunder_{random:NextInteger(1, 3)}`, {
			volume = random:NextNumber(0.2, 0.35),
			pitch = random:NextNumber(0.75, 0.9), -- further away: deeper
			background = true,
		})
	end
end

-- The power plant hum on one sell station.
local function addHum(part: Instance)
	if not part:IsA("BasePart") or part:FindFirstChild("PowerHum") then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "PowerHum"
	attachment.Parent = part
	local hum = Sfx.loop("hum_loop", attachment)
	if hum then
		hum.RollOffMode = Enum.RollOffMode.Linear
		hum.RollOffMinDistance = 8
		hum.RollOffMaxDistance = Config.AMBIENCE.humRadius
		hum.Volume = Sfx.volumeOf("hum_loop")
		hum:Play()
	end
end

function Ambience.init()
	calm = Sfx.loop("calm_loop")
	rain = Sfx.loop("rain_loop")
	gust = Sfx.loop("gust_loop")
end

function Ambience.start()
	setPhase(Storm.current, 1)
	Storm.Changed:Connect(function(state: Types.StormState)
		local wasStorming = storming
		if (state.phase == "Storm") ~= wasStorming then
			setPhase(state, Config.MUSIC_FADE)
		end
	end)
	for _, part in CollectionService:GetTagged(SELL_TAG) do
		addHum(part)
	end
	CollectionService:GetInstanceAddedSignal(SELL_TAG):Connect(addHum)

	local low, high = Config.AMBIENCE.eventEvery[1], Config.AMBIENCE.eventEvery[2]
	while true do
		task.wait(random:NextNumber(low, high))
		if storming then
			stormEvent()
		end
	end
end

return Ambience
