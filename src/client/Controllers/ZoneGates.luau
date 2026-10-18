--!strict
-- Your own copy of each zone gate (Map.ZoneGates, which the server builds
-- with nothing solid). It's solid while you can't enter that zone, and your
-- character is simulated on your client, so the local collision blocks you.
-- When you unlock the zone it turns green, bursts into sparks and fades
-- away, with a banner. The server's checks are the real lock. A non-member
-- who walks into a Premium zone's barrier gets Roblox's Premium offer.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local Types = require(ReplicatedStorage.Shared.Types)
local State = require(script.Parent.State)
local ZoneBanner = require(script.Parent.ZoneBanner)

local FADE = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local GREEN = Color3.fromRGB(90, 230, 120)
local UPSELL_COOLDOWN = 30 -- seconds between Premium offers
local TOUCH = 2.5 -- studs from a barrier's face that count as walking into it

local player = Players.LocalPlayer

local ZoneGates = {}

local wasOpen: { [string]: boolean } = {} -- zone id -> open at the last update
local lastUpsell = -math.huge

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

-- A gate's zone and its barrier part, if it has both.
local function parts(model: Model): (Types.ZoneDef?, BasePart?)
	local zoneId = model:GetAttribute("ZoneId")
	local zone = if typeof(zoneId) == "string" then Config.ZONES[zoneId] else nil
	local barrier = model:FindFirstChild("Barrier")
	if zone and barrier and barrier:IsA("BasePart") then
		return zone, barrier
	end
	return nil, nil
end

local function update(snapshot: Types.Snapshot)
	for _, model in gates() do
		local zone, barrier = parts(model)
		if zone and barrier then
			local open = Progression.canEnter(snapshot, zone, snapshot.premium)
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

-- Offers Premium when a non-member walks into a Premium zone's barrier.
local function checkUpsell(snapshot: Types.Snapshot)
	if snapshot.premium or os.clock() - lastUpsell < UPSELL_COOLDOWN then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	for _, model in gates() do
		local zone, barrier = parts(model)
		if zone and zone.premium and barrier then
			local p = barrier.CFrame:PointToObjectSpace(root.Position)
			local half = barrier.Size / 2
			if
				math.abs(p.X) < half.X + 1
				and math.abs(p.Z) < half.Z + TOUCH
				and math.abs(p.Y) < half.Y + 3
			then
				lastUpsell = os.clock()
				pcall(MarketplaceService.PromptPremiumPurchase, MarketplaceService, player)
				return
			end
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
	while true do
		task.wait(0.2)
		if State.current then
			checkUpsell(State.current)
		end
	end
end

return ZoneGates
