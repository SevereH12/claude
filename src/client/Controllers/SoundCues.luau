--!strict
-- Sounds for changes that only show up in the snapshot: a new bottle or
-- boots (the purchase chime), and a timed boost starting or running out.
-- Everything else plays its sound where it happens (Lib/Sfx).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Sfx = require(script.Parent.Parent.Lib.Sfx)
local State = require(script.Parent.State)

local SoundCues = {}

local last: Types.Snapshot? = nil
local running: { [string]: boolean } = {} -- boost key -> running at the last check

local function onChanged(snapshot: Types.Snapshot)
	local before = last
	last = snapshot
	if
		before and (snapshot.bottleTier > before.bottleTier or snapshot.bootTier > before.bootTier)
	then
		Sfx.play("purchase")
	end
end

-- Boosts run out by the clock, not by a snapshot, so this checks often.
-- False until there's a snapshot to check.
local function checkBoosts(first: boolean): boolean
	local snapshot = State.current
	if not snapshot then
		return false
	end
	local now = workspace:GetServerTimeNow()
	local started, ended = false, false
	for _, boost in Config.BOOSTS do
		local ends = snapshot.boosts[boost.key]
		local on = ends ~= nil and ends > now
		if on and not running[boost.key] then
			started = true
		elseif not on and running[boost.key] then
			ended = true
		end
		running[boost.key] = on
	end
	if first then
		return true -- already running when you joined
	end
	if started then
		Sfx.play("boost_start")
	elseif ended then
		Sfx.play("boost_end")
	end
	return true
end

function SoundCues.init()
	Sfx.preload()
end

function SoundCues.start()
	if State.current then
		onChanged(State.current)
	end
	State.Changed:Connect(onChanged)
	local first = true
	while true do
		if checkBoosts(first) then
			first = false
		end
		task.wait(0.5)
	end
end

return SoundCues
