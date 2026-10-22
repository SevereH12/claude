--!strict
-- All lightning visuals and feedback. Purely cosmetic: the server already
-- decided who caught what before any of this plays.
--
--   Forecast      -> faint dashed ring (your Forecaster), gone at the public warning
--   StrikeWarning -> glowing ring + light pillar; inner disc fills until the bolt lands
--   StrikeLanded  -> forked, flickering bolt; area lights up; sparks,
--                    shockwave, scorch mark, thunder. Arcs into each
--                    catcher's bottle, in their bolt colour (Bolt Colours
--                    pick, else VIP gold). If we caught it: screen flash,
--                    camera shake, "+5" popup ("x2 ASSAYED" if high grade).
--   Sold          -> big "+Volts" popup
--   (ambient)     -> the Power Plant's tesla coil crackles

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local BoostRules = require(ReplicatedStorage.Shared.Util.Boosts)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local PassRules = require(ReplicatedStorage.Shared.Util.Passes)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local Research = require(ReplicatedStorage.Shared.Util.Research)
local Types = require(ReplicatedStorage.Shared.Types)
local Layout = require(script.Parent.Parent.Lib.Layout)
local UI = require(script.Parent.Parent.Lib.UI)
local Zones = require(ReplicatedStorage.Shared.Util.Zones)
local State = require(script.Parent.State)

local player = Players.LocalPlayer

local CORE_COLOR = Color3.fromRGB(240, 248, 255)
local GLOW_COLOR = Color3.fromRGB(120, 175, 255)
local BOLT_HEIGHT = 160
local BOLT_SEGMENTS = 9
local FLASH_DISTANCE = 220 -- strikes closer than this light up your screen
local FORECAST_DASHES = 24
local BALLOON_MUTED = Color3.fromRGB(120, 124, 130)

local FADE = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SLOW_FADE = TweenInfo.new(4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local SHOCKWAVE = TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local POPUP_RISE = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

type Warning = { anchor: BasePart, pillar: BasePart }

local warnings: { [number]: Warning } = {}
local forecasts: { [number]: { BasePart } } = {}
local fxFolder: Folder
local screenGui: ScreenGui
local popupRoot: Frame -- pop-ups sit in the safe area (Lib/Layout)
type Popup = { y: number, size: number } -- design pixels
local livePopups: { Popup } = {}
local flashFrame: Frame
local strikeFlash: ColorCorrectionEffect
local random = Random.new()

local StrikeFX = {}

-- Helpers -------------------------------------------------------------------

local function effectPart(props: { [string]: any }): BasePart
	local part = UI.make(Instance.new("Part"), {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Material = Enum.Material.Neon,
	})
	return UI.make(part, props)
end

-- Invisible anchor part used to position adornments and lights in the world.
local function anchorAt(position: Vector3, lifetime: number): BasePart
	local anchor = effectPart({
		Name = "FXAnchor",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Position = position,
		Transparency = 1,
		Parent = fxFolder,
	})
	Debris:AddItem(anchor, lifetime)
	return anchor
end

-- Flat ring/disc lying on the ground around the anchor.
local function groundRing(anchor: BasePart, props: { [string]: any }): CylinderHandleAdornment
	local ring = UI.make(Instance.new("CylinderHandleAdornment"), {
		Adornee = anchor,
		CFrame = CFrame.Angles(math.rad(90), 0, 0), -- cylinder runs along Z; lay it flat
		Height = 0.25,
		AlwaysOnTop = false,
		ZIndex = 0,
	})
	return UI.make(ring, props)
end

local function playSound(soundId: string, parent: Instance, speed: number?, volume: number?)
	local sound = UI.make(Instance.new("Sound"), {
		SoundId = soundId,
		Volume = volume or 0.8,
		PlaybackSpeed = (speed or 1) * random:NextNumber(0.92, 1.08),
		RollOffMaxDistance = 500,
		Parent = parent,
	})
	sound:Play()
	Debris:AddItem(sound, 5)
end

-- Floating text that rises and fades. `y` is how far down the screen it
-- starts (0 to 1); `size` its height as a share of a 720-pixel-tall design
-- screen, so it's the same shape on every device. One that would land on a
-- pop-up still on screen moves down below it instead of piling on top.
local POPUP_WIDTH = 520
local POPUP_RISE_BY = 64

local function popup(text: string, gold: boolean, y: number, size: number?)
	local area = Layout.area
	local height = (size or 0.08) * 720
	local slot: Popup = { y = y * area.Y, size = height }
	for _ = 1, 8 do
		local moved = false
		for _, other in livePopups do
			local gap = (other.size + slot.size) / 2
			if math.abs(other.y - slot.y) < gap then
				slot.y = other.y + gap + 4
				moved = true
			end
		end
		if not moved then
			break
		end
	end
	slot.y = math.min(slot.y, area.Y - height / 2)
	table.insert(livePopups, slot)
	local label = UI.label({
		Title = true,
		Text = text,
		TextColor3 = if gold then Color3.new(1, 1, 1) else UI.COLORS.red,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, slot.y),
		Size = UDim2.fromOffset(math.min(POPUP_WIDTH, area.X - 24), height),
		Parent = popupRoot,
	})
	if gold then
		UI.gradient(label, UI.COLORS.volt, UI.COLORS.voltDeep)
	end
	UI.maxText(label, 64)
	UI.pop(label, 1.35)
	local rise = TweenService:Create(label, POPUP_RISE, {
		Position = UDim2.new(0.5, 0, 0, slot.y - POPUP_RISE_BY),
		TextTransparency = 1,
	})
	rise.Completed:Once(function()
		local index = table.find(livePopups, slot)
		if index then
			table.remove(livePopups, index)
		end
		label:Destroy()
	end)
	rise:Play()
end

local function screenFlash(amount: number)
	flashFrame.BackgroundTransparency = 1 - amount
	TweenService:Create(flashFrame, FADE, { BackgroundTransparency = 1 }):Play()
end

local function cameraShake(duration: number, intensity: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - started
		if elapsed >= duration then
			connection:Disconnect()
			humanoid.CameraOffset = Vector3.zero
			return
		end
		local strength = intensity * (1 - elapsed / duration)
		humanoid.CameraOffset =
			Vector3.new(random:NextNumber(-1, 1) * strength, random:NextNumber(-1, 1) * strength, 0)
	end)
end

-- Bolts ---------------------------------------------------------------------

-- Jagged path from a to b: straight line plus sideways jitter that shrinks
-- toward the end.
local function jaggedPath(a: Vector3, b: Vector3, segments: number, wobble: number): { Vector3 }
	local points = { a }
	for i = 1, segments - 1 do
		local t = i / segments
		local amount = wobble * (1 - t * 0.7)
		table.insert(
			points,
			a:Lerp(b, t)
				+ Vector3.new(
					random:NextNumber(-amount, amount),
					random:NextNumber(-amount, amount) * 0.3,
					random:NextNumber(-amount, amount)
				)
		)
	end
	table.insert(points, b)
	return points
end

-- Draws a glowing line along the points and returns its parts. `tint`
-- colours it (a player's bolt colour); white-blue when nil.
local function drawPath(points: { Vector3 }, thickness: number, into: { BasePart }, tint: Color3?)
	local glowColor = tint or GLOW_COLOR
	local coreColor = if tint then tint:Lerp(CORE_COLOR, 0.5) else CORE_COLOR
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local length = (b - a).Magnitude
		local cframe = CFrame.lookAt((a + b) / 2, b)
		table.insert(
			into,
			effectPart({
				Name = "BoltCore",
				Size = Vector3.new(thickness, thickness, length + thickness),
				CFrame = cframe,
				Color = coreColor,
				Parent = fxFolder,
			})
		)
		table.insert(
			into,
			effectPart({
				Name = "BoltGlow",
				Size = Vector3.new(thickness * 3.5, thickness * 3.5, length),
				CFrame = cframe,
				Color = glowColor,
				Transparency = 0.72,
				Parent = fxFolder,
			})
		)
	end
end

-- Flicker on-off-on like real lightning, then fade out.
local function flickerAndFade(parts: { BasePart })
	local original: { [BasePart]: number } = {}
	for _, part in parts do
		original[part] = part.Transparency
	end
	local function setVisible(visible: boolean)
		for _, part in parts do
			part.Transparency = if visible then original[part] else 1
		end
	end
	task.delay(0.05, setVisible, false)
	task.delay(0.09, setVisible, true)
	task.delay(0.14, function()
		for _, part in parts do
			TweenService:Create(part, FADE, { Transparency = 1 }):Play()
			Debris:AddItem(part, FADE.Time + 0.05)
		end
	end)
end

local function bolt(from: Vector3, to: Vector3, thickness: number, branches: number, tint: Color3?)
	local parts: { BasePart } = {}
	local main = jaggedPath(from, to, BOLT_SEGMENTS, (from - to).Magnitude * 0.06)
	drawPath(main, thickness, parts, tint)
	for _ = 1, branches do
		local startIndex = random:NextInteger(2, math.max(2, #main - 3))
		local start = main[startIndex]
		local reach = (from - to).Magnitude * random:NextNumber(0.12, 0.22)
		local finish = start
			+ Vector3.new(
				random:NextNumber(-1, 1) * reach,
				-reach,
				random:NextNumber(-1, 1) * reach
			)
		drawPath(jaggedPath(start, finish, 4, reach * 0.25), thickness * 0.5, parts, tint)
	end
	flickerAndFade(parts)
end

-- Thunder crack at a point in the world.
local function playThunderAt(position: Vector3)
	local attachment = UI.make(Instance.new("Attachment"), {
		WorldPosition = position,
		Parent = workspace.Terrain,
	})
	playSound(Config.SOUNDS.STRIKE, attachment, 0.55, 1)
	Debris:AddItem(attachment, 5)
end

-- Impact: light burst, sparks, shockwave, scorch mark.
local function impact(position: Vector3)
	local anchor = anchorAt(position + Vector3.new(0, 0.3, 0), 5)

	local burst = UI.make(Instance.new("PointLight"), {
		Color = GLOW_COLOR,
		Brightness = 14,
		Range = 60,
		Shadows = true,
		Parent = anchor,
	})
	TweenService:Create(burst, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Brightness = 0 }):Play()

	local sparkOrigin = UI.make(Instance.new("Attachment"), { Parent = anchor })
	local sparks = UI.make(Instance.new("ParticleEmitter"), {
		Enabled = false,
		Color = ColorSequence.new(CORE_COLOR, GLOW_COLOR),
		LightEmission = 1,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Speed = NumberRange.new(25, 50),
		Lifetime = NumberRange.new(0.3, 0.7),
		SpreadAngle = Vector2.new(75, 75),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -70, 0),
		Drag = 2,
		Parent = sparkOrigin,
	})
	sparks:Emit(45)

	local shockwave = groundRing(anchor, {
		Radius = 1,
		InnerRadius = 0.4,
		Color3 = GLOW_COLOR,
		Transparency = 0.1,
		Parent = anchor,
	})
	TweenService:Create(shockwave, SHOCKWAVE, { Radius = 16, InnerRadius = 15, Transparency = 1 })
		:Play()

	local scorch = groundRing(anchor, {
		Radius = 3.5,
		InnerRadius = 0,
		Height = 0.1,
		Color3 = Color3.fromRGB(20, 18, 25),
		Transparency = 0.35,
		Parent = anchor,
	})
	TweenService:Create(scorch, SLOW_FADE, { Transparency = 1 }):Play()

	-- strikes near you light up the whole screen for a moment
	local camera = workspace.CurrentCamera
	local distance = if camera then (camera.CFrame.Position - position).Magnitude else math.huge
	if distance < FLASH_DISTANCE then
		local strength = 1 - distance / FLASH_DISTANCE
		strikeFlash.Brightness = 0.45 * strength
		strikeFlash.TintColor = Color3.fromRGB(215, 230, 255)
		TweenService:Create(strikeFlash, TweenInfo.new(0.35), { Brightness = 0 }):Play()
	end

	playThunderAt(position)
end

-- Where a player's bottle is, for the arc that flies into it.
local function bottlePosition(userId: number): Vector3?
	local catcher = Players:GetPlayerByUserId(userId)
	local character = catcher and catcher.Character
	local bottle = character and character:FindFirstChild("Bottle")
	if bottle and bottle:IsA("Model") then
		return bottle:GetPivot().Position
	end
	return nil
end

-- A catcher's arc colour, from their player attributes: their Bolt Colours
-- pick, else VIP gold, else nil (the default).
local function arcColour(userId: number): Color3?
	local catcher = Players:GetPlayerByUserId(userId)
	if not catcher then
		return nil
	end
	local owned = {
		VIP = catcher:GetAttribute(PassRules.ATTRIBUTE .. "VIP") == true,
		BoltColours = catcher:GetAttribute(PassRules.ATTRIBUTE .. "BoltColours") == true,
	}
	local choice = catcher:GetAttribute(PassRules.BOLT_ATTRIBUTE)
	return PassRules.boltColour(owned, if typeof(choice) == "number" then choice else 0)
end

-- The level of your own researcher if they'd be working right now (posted to
-- the zone you stand in, set up). Display only: the server decides for real.
local function activeLevel(roleId: string): number?
	local snapshot = State.current
	local save = if snapshot then snapshot.researchers[roleId] else nil
	if not snapshot or not save or save.post == "Office" then
		return nil
	end
	local readyAt = snapshot.setupUntil[roleId]
	if readyAt and workspace:GetServerTimeNow() < readyAt then
		return nil
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local zone = if root and root:IsA("BasePart") then Zones.at(root.Position) else nil
	if not zone or zone.id ~= save.post then
		return nil
	end
	return save.level
end

-- Events --------------------------------------------------------------------

-- Your Forecaster's early look: a faint dashed ring only you can see, gone
-- when the public warning for the same strike appears.
local function onForecast(forecast: Types.Forecast)
	local timeLeft = forecast.warnsAt - workspace:GetServerTimeNow()
	if timeLeft <= 0 or forecasts[forecast.id] then
		return
	end
	local zone = Config.ZONES[forecast.zoneId]
	local color = if zone then zone.color else UI.COLORS.volt
	local dashes: { BasePart } = {}
	for index = 0, FORECAST_DASHES - 1 do
		local angle = (index / FORECAST_DASHES) * math.pi * 2
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * forecast.radius
		local dash = effectPart({
			Name = "ForecastDash",
			Size = Vector3.new(0.5, 0.2, forecast.radius * math.pi / FORECAST_DASHES),
			CFrame = CFrame.lookAt(
				forecast.position + offset + Vector3.new(0, 0.4, 0),
				forecast.position + Vector3.new(0, 0.4, 0)
			) * CFrame.Angles(0, math.rad(90), 0),
			Color = color,
			Transparency = 0.6,
			Parent = fxFolder,
		})
		Debris:AddItem(dash, timeLeft + 1)
		table.insert(dashes, dash)
	end
	forecasts[forecast.id] = dashes
end

local function clearForecast(id: number)
	local dashes = forecasts[id]
	if not dashes then
		return
	end
	forecasts[id] = nil
	for _, dash in dashes do
		local fade = TweenService:Create(dash, FADE, { Transparency = 1 })
		fade.Completed:Once(function()
			dash:Destroy()
		end)
		fade:Play()
	end
end

local function onWarning(warning: Types.StrikeWarning)
	local timeLeft = warning.landsAt - workspace:GetServerTimeNow()
	if timeLeft <= 0 then
		return
	end
	local zone = Config.ZONES[warning.zoneId]
	local color = if zone then zone.color else UI.COLORS.volt
	if warning.ownerId and warning.ownerId ~= player.UserId then
		color = BALLOON_MUTED -- someone else's balloon bolt
	end
	local lifetime = timeLeft + 2 -- safety net if the landed event never arrives
	clearForecast(warning.id)

	local anchor = anchorAt(warning.position + Vector3.new(0, 0.4, 0), lifetime)
	local ring = groundRing(anchor, {
		Radius = warning.radius,
		InnerRadius = warning.radius - 0.6,
		Height = 0.35,
		Color3 = color,
		Transparency = 0.05,
		Parent = anchor,
	})
	local fill = groundRing(anchor, {
		Radius = 0.3,
		InnerRadius = 0,
		Color3 = color,
		Transparency = 0.55,
		Parent = anchor,
	})
	-- the inner disc reaches the ring exactly when the bolt lands
	TweenService
		:Create(fill, TweenInfo.new(timeLeft, Enum.EasingStyle.Linear), { Radius = warning.radius })
		:Play()
	-- pulse the ring faster and faster
	TweenService:Create(
		ring,
		TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.5 }
	):Play()

	-- your Rod Tech's reach: a faint outer ring around the warning
	local rodTech = activeLevel("RodTech")
	if rodTech then
		local reach = Research.catchRadius(rodTech)
		groundRing(anchor, {
			Radius = reach,
			InnerRadius = reach - 0.3,
			Color3 = color,
			Transparency = 0.8,
			Parent = anchor,
		})
	end

	-- a column of light so you can spot circles from across the zone
	local pillar = effectPart({
		Name = "WarningPillar",
		Size = Vector3.new(0.5, 70, 0.5),
		Position = warning.position + Vector3.new(0, 35, 0),
		Color = color,
		Transparency = 0.8,
		Parent = fxFolder,
	})
	Debris:AddItem(pillar, lifetime)

	warnings[warning.id] = { anchor = anchor, pillar = pillar }
end

local function onLanded(landed: Types.StrikeLanded)
	local warning = warnings[landed.id]
	if warning then
		warnings[landed.id] = nil
		warning.anchor:Destroy()
		warning.pillar:Destroy()
	end

	local sky = landed.position
		+ Vector3.new(random:NextNumber(-15, 15), BOLT_HEIGHT, random:NextNumber(-15, 15))
	bolt(sky, landed.position, 0.5, 2)
	impact(landed.position)

	-- little arcs from the strike into every catcher's bottle
	for _, userId in landed.catchers do
		local target = bottlePosition(userId)
		if target then
			bolt(landed.position + Vector3.new(0, 1, 0), target, 0.18, 0, arcColour(userId))
		end
	end

	local caught = table.find(landed.catchers, player.UserId)
	if caught then
		screenFlash(0.55)
		cameraShake(0.3, 0.7)
		popup(`+{Format.abbreviate(landed.values[caught] or landed.value)} ⚡`, true, 0.42)
		playSound(Config.SOUNDS.CATCH, screenGui, 1.2)
		-- the Analyst's assay and Lucky Charges each double it
		local assayed = table.find(landed.assayed, player.UserId) ~= nil
		local lucky = table.find(landed.lucky, player.UserId) ~= nil
		if assayed and lucky then
			popup("x4 JACKPOT", true, 0.5, 0.075)
			cameraShake(0.25, 0.5)
		elseif lucky then
			popup("x2 LUCKY", true, 0.5, 0.06)
		elseif assayed then
			popup("x2 ASSAYED", true, 0.5, 0.06)
		end
	elseif table.find(landed.tanked, player.UserId) then
		local zone = Config.ZONES[landed.zoneId]
		local snapshot = State.current
		local units = if zone and snapshot then Progression.chargeSize(snapshot, zone) else 1
		popup(`+{units} → TANK`, true, 0.42, 0.06)
		playSound(Config.SOUNDS.CATCH, screenGui, 0.9)
	elseif table.find(landed.full, player.UserId) then
		UI.toastEvery("bottleFull", UI.FULL_REMINDER, UI.FULL_MESSAGE, "warn")
	end
end

local function onSold(earned: number, count: number)
	popup(`+{Format.abbreviate(earned)} Volts!`, true, 0.36, 0.1)
	popup(`sold {count} charges`, false, 0.45, 0.045)
	-- members of the game's group get more (Systems/Group), and everyone
	-- during a Server Storm (Systems/Boosts)
	local y = 0.5
	if player:GetAttribute(PassRules.GROUP) == true then
		popup(`+{math.round(Config.GROUP_BONUS * 100)}% group bonus`, true, y, 0.045)
		y += 0.05
	end
	local ends = workspace:GetAttribute(BoostRules.STORM_ENDS)
	if BoostRules.stormLeft(ends, workspace:GetServerTimeNow()) > 0 then
		popup(`x{Config.SERVER_STORM.multiplier} SERVER STORM`, true, y, 0.045)
	end
	screenFlash(0.25)
	cameraShake(0.2, 0.35)
	playSound(Config.SOUNDS.SELL, screenGui, 0.8)
end

-- The Power Plant's tesla coil throws small arcs now and then.
local function coilCrackle()
	local map = workspace:FindFirstChild("Map")
	local plant = map and map:FindFirstChild("PowerPlant")
	local orb = plant and plant:FindFirstChild("CoilOrb")
	local camera = workspace.CurrentCamera
	if not orb or not orb:IsA("BasePart") or not camera then
		return
	end
	if (camera.CFrame.Position - orb.Position).Magnitude > 300 then
		return
	end
	local angle = random:NextNumber(0, math.pi * 2)
	local target = orb.Position + Vector3.new(math.cos(angle) * 7, -5, math.sin(angle) * 7)
	bolt(orb.Position, target, 0.15, 1)
end

function StrikeFX.init()
	fxFolder = UI.make(Instance.new("Folder"), { Name = "StrikeFX", Parent = workspace })
	strikeFlash =
		UI.make(Instance.new("ColorCorrectionEffect"), { Name = "StrikeFlash", Parent = Lighting })
	screenGui = UI.make(Instance.new("ScreenGui"), {
		Name = "StrikeFX",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 10,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local _, root = Layout.screen("StrikeFXText", 10)
	popupRoot = root
	flashFrame = UI.make(Instance.new("Frame"), {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(235, 245, 255),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = screenGui,
	})

	Net.get("Forecast").OnClientEvent:Connect(onForecast)
	Net.get("StrikeWarning").OnClientEvent:Connect(onWarning)
	Net.get("StrikeLanded").OnClientEvent:Connect(onLanded)
	Net.get("Sold").OnClientEvent:Connect(onSold)
end

function StrikeFX.start()
	while true do
		task.wait(random:NextNumber(1.5, 4))
		coilCrackle()
	end
end

return StrikeFX
