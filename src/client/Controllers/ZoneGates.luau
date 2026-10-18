--!strict
-- Your own copy of each zone gate (Map.ZoneGates, which the server builds
-- with nothing solid). It's solid while you can't enter that zone, and your
-- character is simulated on your client, so the local collision blocks you.
-- When you unlock the zone it turns green, bursts into sparks and fades
-- away, with a banner. The server's checks are the real lock.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local Types = require(ReplicatedStorage.Shared.Types)
local State = require(script.Parent.State)
local ZoneBanner = require(script.Parent.ZoneBanner)

local FADE = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local GREEN = Color3.fromRGB(90, 230, 120)

local ZoneGates = {}

local wasOpen: { [string]: boolean } = {} -- zone id -> open at the last update

local function gates(): { Model }
	local map = workspace:FindFirstChild("Map")
	local container = map and map:FindFirstChild("ZoneGates")
	local list: { Model } = {}
	if container then
		for _, child in container:GetChildren() do
			if child:IsA("Model") then
				table.insert(list, child)
			end
		end
	end
	return list
end

-- Fades every part of the gate out (instantly when time is 0).
local function fadeOut(model: Model, time: number)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			if time > 0 then
				TweenService:Create(descendant, TweenInfo.new(time), { Transparency = 1 }):Play()
			else
				descendant.Transparency = 1
			end
		elseif descendant:IsA("SurfaceGui") then
			descendant.Enabled = false
		end
	end
end

local function dissolve(model: Model, barrier: BasePart)
	barrier.CanCollide = false
	TweenService:Create(barrier, FADE, { Color = GREEN }):Play()
	local sparks = Instance.new("ParticleEmitter")
	sparks.Enabled = false
	sparks.Lifetime = NumberRange.new(0.6, 1.2)
	sparks.Speed = NumberRange.new(4, 10)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Size = NumberSequence.new(0.35, 0)
	sparks.Color = ColorSequence.new(GREEN, Color3.fromRGB(110, 230, 255))
	sparks.LightEmission = 1
	sparks.Parent = barrier
	sparks:Emit(90)
	task.delay(0.5, fadeOut, model, 1)
end

local function update(snapshot: Types.Snapshot)
	for _, model in gates() do
		local zoneId = model:GetAttribute("ZoneId")
		local zone = if typeof(zoneId) == "string" then Config.ZONES[zoneId] else nil
		local barrier = model:FindFirstChild("Barrier")
		if zone and barrier and barrier:IsA("BasePart") then
			local open = Progression.canEnter(snapshot, zone)
			local before = wasOpen[zone.id]
			if open and before == false then
				-- unlocked while playing
				dissolve(model, barrier)
				ZoneBanner.show(`{string.upper(zone.displayName)} UNLOCKED`, zone.tagline, GREEN)
			elseif open and before == nil then
				fadeOut(model, 0) -- already open when you joined
			elseif not open then
				barrier.CanCollide = true
			end
			wasOpen[zone.id] = open
		end
	end
end

function ZoneGates.start()
	-- the gates are a Persistent model, but may arrive after this script runs
	local map = workspace:WaitForChild("Map", 30)
	if map then
		map:WaitForChild("ZoneGates", 10)
	end
	if State.current then
		update(State.current)
	end
	State.Changed:Connect(update)
end

return ZoneGates
