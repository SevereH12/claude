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
--                    Rare bolts (Config.BOLT_TYPES): a gold ring (Golden),
--                    a colour-cycling ring (Rainbow) or a drifting orb
--                    (Ball lightning), a coloured bolt and a "GOLDEN x10!"
--                    popup when you catch one.
--   Sold          -> big "+Volts" popup
--   (ambient)     -> the Power Plant's tesla coil crackles
--
-- How a bolt is drawn: one invisible, anchored host part in the StrikeFX
-- folder with an Attachment at every point of its jagged path, and two
-- Beams per segment (a thin core and a wide see-through glow) that face the
-- camera. Neighbouring segments share their attachment, so the bolt has no
-- gaps where it bends. It flickers like a real restrike: it dims to 40% for
-- a beat, comes back down a slightly moved path, then fades (Reduce
-- flashing: just a slow fade). It never vanishes mid-flash. The host part
-- is destroyed when the fade ends.
--
-- How much is drawn (Util/StrikeFx, numbers in Config.STRIKE_FX): your own
-- strikes in full; another world's not at all, and silent; other players'
-- less the further away they are, and Others' lightning can only lower
-- that. At most maxLights strike lights shine at once (a new one replaces
-- the oldest), and only your own strike's light casts shadows (Lightning
-- glow on Full).

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
local Portals = require(ReplicatedStorage.Shared.Util.Portals)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local Research = require(ReplicatedStorage.Shared.Util.Research)
local StrikeFx = require(ReplicatedStorage.Shared.Util.StrikeFx)
local Types = require(ReplicatedStorage.Shared.Types)
local Weather = require(ReplicatedStorage.Shared.Util.Weather)
local Layout = require(script.Parent.Parent.Lib.Layout)
local SettingsStore = require(script.Parent.Parent.Lib.SettingsStore)
local Sfx = require(script.Parent.Parent.Lib.Sfx)
local UI = require(script.Parent.Parent.Lib.UI)
local ZoneColours = require(script.Parent.Parent.Lib.ZoneColours)
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

type Warning = { anchor: BasePart, pillar: BasePart, orb: BasePart? }

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

-- Floating text that rises and fades. `y` is how far down the screen it
-- starts (0 to 1); `size` its height as a share of a 720-pixel-tall design
-- screen, so it's the same shape on every device. One that would land on a
-- pop-up still on screen moves down below it instead of piling on top.
local POPUP_WIDTH = 520
local POPUP_RISE_BY = 64

local function popup(text: string, gold: boolean, y: number, size: number?)
	if not SettingsStore.get("showPopups") then
		return -- SETTINGS > Accessibility & HUD
	end
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
	if SettingsStore.get("reduceFlashing") then
		return
	end
	flashFrame.BackgroundTransparency = 1 - amount
	TweenService:Create(flashFrame, FADE, { BackgroundTransparency = 1 }):Play()
end

local function cameraShake(duration: number, baseIntensity: number)
	local intensity = baseIntensity * SettingsStore.get("cameraShake")
	if intensity <= 0 then
		return
	end
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

-- A bolt on screen: one invisible host part holding an Attachment per path
-- point, and two Beams per segment (a thin core and a wide see-through
-- glow). Neighbouring segments share their attachment, so the joins are
-- seamless. stepBolts dims, restrikes and fades every live bolt each frame,
-- then destroys its host part.
local CORE_SEEN = 0 -- the core's transparency at full brightness
local GLOW_SEEN = 0.72 -- the glow's
local RESTRIKE_MOVE = 0.35 -- the restrike moves each joint up to this share of the wobble

type BoltPath = { attachments: { Attachment }, points: { Vector3 } }
type LiveBolt = {
	host: BasePart,
	origin: Vector3, -- the host part's position (attachments sit relative to it)
	cores: { Beam },
	glows: { Beam },
	paths: { BoltPath },
	wobble: number,
	born: number,
	calm: boolean, -- Reduce flashing: just a slow fade
	restruck: boolean,
	shown: number, -- the brightness last drawn
}
local liveBolts: { LiveBolt } = {}

local function beam(
	a0: Attachment,
	a1: Attachment,
	width: number,
	color: ColorSequence,
	seen: number,
	host: BasePart
): Beam
	local line = Instance.new("Beam")
	line.Attachment0 = a0
	line.Attachment1 = a1
	line.FaceCamera = true
	line.Segments = 1 -- straight, so one piece is enough
	line.Width0 = width
	line.Width1 = width
	line.Color = color
	line.Transparency = NumberSequence.new(seen)
	line.LightEmission = 1
	line.LightInfluence = 0
	line.Parent = host
	return line
end

-- Draws a glowing line along the points into the bolt and returns its
-- attachments. `root`: the attachment it grows from (a branch shares its
-- bolt's joint). `tint` colours it (a player's bolt colour); white-blue
-- when nil.
local function drawPath(
	live: LiveBolt,
	points: { Vector3 },
	thickness: number,
	tint: Color3?,
	root: Attachment?
): { Attachment }
	local glowColor = ColorSequence.new(tint or GLOW_COLOR)
	local coreColor = ColorSequence.new(if tint then tint:Lerp(CORE_COLOR, 0.5) else CORE_COLOR)
	local attachments: { Attachment } = {}
	for i, point in points do
		if i == 1 and root then
			attachments[i] = root
		else
			local attachment = Instance.new("Attachment")
			attachment.Position = point - live.origin
			attachment.Parent = live.host
			attachments[i] = attachment
		end
	end
	for i = 1, #points - 1 do
		local a0, a1 = attachments[i], attachments[i + 1]
		local core = beam(a0, a1, thickness, coreColor, CORE_SEEN, live.host)
		core.ZOffset = 0.1 -- drawn in front of the glow
		table.insert(live.cores, core)
		table.insert(live.glows, beam(a0, a1, thickness * 3.5, glowColor, GLOW_SEEN, live.host))
	end
	table.insert(live.paths, { attachments = attachments, points = points })
	return attachments
end

-- The restrike comes down a slightly different path: every joint moves a
-- little (never the ends, so a branch stays on the joint it grows from).
local function restrike(live: LiveBolt)
	live.restruck = true
	for _, path in live.paths do
		local moved = StrikeFx.restrike(path.points, live.wobble * RESTRIKE_MOVE, random)
		for i = 2, #moved - 1 do
			path.attachments[i].Position = moved[i] - live.origin
		end
	end
end

-- Draws the bolt at a brightness (1 = full, 0 = gone) through its Beams'
-- Transparency.
local function show(live: LiveBolt, brightness: number)
	live.shown = brightness
	local core = NumberSequence.new(1 - (1 - CORE_SEEN) * brightness)
	local glow = NumberSequence.new(1 - (1 - GLOW_SEEN) * brightness)
	for _, line in live.cores do
		line.Transparency = core
	end
	for _, line in live.glows do
		line.Transparency = glow
	end
end

-- Every frame: each live bolt's flicker and fade (Util/StrikeFx.brightness:
-- full, a dip to 40% for one beat, the restrike, then a fade; it never
-- hides completely). A bolt that has faded out is destroyed.
local function stepBolts()
	local now = os.clock()
	for i = #liveBolts, 1, -1 do
		local live = liveBolts[i]
		local elapsed = now - live.born
		local brightness = StrikeFx.brightness(elapsed, live.calm)
		if brightness == nil then
			live.host:Destroy()
			table.remove(liveBolts, i)
		else
			if not live.calm and not live.restruck and elapsed >= StrikeFx.restrikeTime() then
				restrike(live)
			end
			if brightness ~= live.shown then
				show(live, brightness)
			end
		end
	end
end

local function bolt(from: Vector3, to: Vector3, thickness: number, branches: number, tint: Color3?)
	local length = (from - to).Magnitude
	local live: LiveBolt = {
		host = effectPart({
			Name = "Bolt",
			Size = Vector3.new(0.2, 0.2, 0.2),
			CFrame = CFrame.new(to),
			Transparency = 1,
		}),
		origin = to,
		cores = {},
		glows = {},
		paths = {},
		wobble = length * 0.06,
		born = os.clock(),
		calm = SettingsStore.get("reduceFlashing") == true,
		restruck = false,
		shown = 1,
	}
	local main = StrikeFx.jaggedPath(from, to, BOLT_SEGMENTS, live.wobble, random)
	local joints = drawPath(live, main, thickness, tint)
	for _ = 1, branches do
		local startIndex = random:NextInteger(2, math.max(2, #main - 3))
		local start = main[startIndex]
		local reach = length * random:NextNumber(0.12, 0.22)
		local finish = start
			+ Vector3.new(
				random:NextNumber(-1, 1) * reach,
				-reach,
				random:NextNumber(-1, 1) * reach
			)
		local branch = StrikeFx.jaggedPath(start, finish, 4, reach * 0.25, random)
		drawPath(live, branch, thickness * 0.5, tint, joints[startIndex])
	end
	live.host.Parent = fxFolder -- in the world once it's all built
	table.insert(liveBolts, live)
end

-- The bolt's crack at a point in the world (a whistle and crack for your
-- own balloon bolt), and its thunder, later the further away you are (sound
-- takes about 1 s per Config.THUNDER_STUDS_PER_SECOND studs).
local function playThunderAt(position: Vector3, balloon: boolean)
	if balloon then
		Sfx.playAt("balloon_bolt", position)
	else
		Sfx.playAt(`strike_crack_{random:NextInteger(1, 3)}`, position)
	end
	local camera = workspace.CurrentCamera
	local distance = if camera then (camera.CFrame.Position - position).Magnitude else 0
	local delay = math.min(distance / Config.THUNDER_STUDS_PER_SECOND, Config.THUNDER_MAX_DELAY)
	task.delay(delay, function()
		Sfx.playAt(`thunder_{random:NextInteger(1, 3)}`, position)
	end)
end

-- The catch sound rises as the bottle fills: catch_1 (nearly empty) to
-- catch_5 (nearly full).
local function catchSound(): string
	local snapshot = State.current
	local fill = if snapshot then snapshot.chargeCount / math.max(snapshot.capacity, 1) else 0
	return `catch_{math.clamp(math.ceil(fill * 5), 1, 5)}`
end

-- Strike lights: at most Config.STRIKE_FX.maxLights at once (a new one
-- replaces the oldest), each gone once it has faded.
local LIGHT_FADE = 0.6
local lights: StrikeFx.Budget<PointLight> = StrikeFx.newBudget(Config.STRIKE_FX.maxLights)
local function budgetLight(light: PointLight)
	local oldest = StrikeFx.admit(lights, light)
	if oldest then
		oldest:Destroy()
	end
	light.Destroying:Once(function()
		StrikeFx.release(lights, light)
	end)
	Debris:AddItem(light, LIGHT_FADE + 0.05)
end

-- Impact: light burst, sparks, shockwave, scorch mark. `simple` (Util/StrikeFx
-- said simple): just the shockwave. The light follows Lightning glow (and
-- casts shadows only for your own strike, on Full), the sparks Rain and
-- particles.
local function impact(position: Vector3, simple: boolean, mine: boolean)
	local anchor = anchorAt(position + Vector3.new(0, 0.3, 0), 5)
	local glow = SettingsStore.get("glow")

	if glow ~= "Off" and not simple then
		local soft = glow == "Soft"
		local burst = UI.make(Instance.new("PointLight"), {
			Color = GLOW_COLOR,
			Brightness = if soft then 6 else 14,
			Range = if soft then 40 else 60,
			Shadows = StrikeFx.castsShadows(mine, glow),
			Parent = anchor,
		})
		local fade = TweenInfo.new(LIGHT_FADE, Enum.EasingStyle.Quad)
		TweenService:Create(burst, fade, { Brightness = 0 }):Play()
		budgetLight(burst)
	end

	if not simple then
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
		sparks:Emit(math.round(45 * SettingsStore.get("particleAmount")))
	end

	local shockwave = groundRing(anchor, {
		Radius = 1,
		InnerRadius = 0.4,
		Color3 = GLOW_COLOR,
		Transparency = 0.1,
		Parent = anchor,
	})
	TweenService:Create(shockwave, SHOCKWAVE, { Radius = 16, InnerRadius = 15, Transparency = 1 })
		:Play()

	if simple then
		return
	end
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
	local flashes = glow ~= "Off" and not SettingsStore.get("reduceFlashing")
	if distance < FLASH_DISTANCE and flashes then
		local strength = (1 - distance / FLASH_DISTANCE) * (if glow == "Soft" then 0.5 else 1)
		strikeFlash.Brightness = 0.45 * strength
		strikeFlash.TintColor = Color3.fromRGB(215, 230, 255)
		TweenService:Create(strikeFlash, TweenInfo.new(0.35), { Brightness = 0 }):Play()
	end
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
local function activeLevel(roleId: string): (number?, number)
	local snapshot = State.current
	local save = if snapshot then snapshot.researchers[roleId] else nil
	if not snapshot or not save or save.post == "Office" then
		return nil, 0
	end
	local readyAt = snapshot.setupUntil[roleId]
	if readyAt and workspace:GetServerTimeNow() < readyAt then
		return nil, 0
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local zone = if root and root:IsA("BasePart") then Zones.at(root.Position) else nil
	if not zone or zone.id ~= save.post then
		return nil, 0
	end
	return save.level, save.rank or 0
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
	Sfx.play("forecast")
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

-- Colourblind rings: a dashed outline outside the ring and a ⚡ in the
-- middle, so a ring reads by shape as well as colour.
local CB_DASHES = 12
local function colourblindMarks(
	anchor: BasePart,
	position: Vector3,
	radius: number,
	color: Color3,
	lifetime: number
)
	local outer = radius + 1.2
	for index = 0, CB_DASHES - 1 do
		local angle = (index / CB_DASHES) * math.pi * 2
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * outer
		local dash = effectPart({
			Name = "AssistDash",
			Size = Vector3.new(0.6, 0.25, outer * math.pi / CB_DASHES),
			CFrame = CFrame.lookAt(
				position + offset + Vector3.new(0, 0.45, 0),
				position + Vector3.new(0, 0.45, 0)
			) * CFrame.Angles(0, math.rad(90), 0),
			Color = Color3.new(1, 1, 1),
			Transparency = 0.1,
			Parent = anchor,
		})
		Debris:AddItem(dash, lifetime)
	end
	local icon = UI.make(Instance.new("BillboardGui"), {
		Name = "AssistIcon",
		Size = UDim2.fromScale(4, 4),
		StudsOffset = Vector3.new(0, 2.5, 0),
		AlwaysOnTop = true,
		Parent = anchor,
	})
	UI.label({
		Title = true,
		Text = "⚡",
		TextColor3 = color,
		Size = UDim2.fromScale(1, 1),
		Parent = icon,
	})
end

local function onWarning(warning: Types.StrikeWarning)
	local timeLeft = warning.landsAt - workspace:GetServerTimeNow()
	if timeLeft <= 0 then
		return
	end
	local zone = Config.ZONES[warning.zoneId]
	local color = ZoneColours.of(zone, UI.COLORS.volt)
	if warning.ownerId and warning.ownerId ~= player.UserId then
		color = BALLOON_MUTED -- someone else's balloon bolt
	end
	local rare = Weather.boltDef(warning.boltType)
	if rare then
		color = rare.color
	end
	local orbSeconds = warning.orbSeconds or 0
	-- safety net if the landed event never arrives
	local lifetime = timeLeft + orbSeconds + 2
	clearForecast(warning.id)
	-- the charge-up hum lasts WARNING_TIME: join it part way if we're late
	local someoneElses = warning.ownerId ~= nil and warning.ownerId ~= player.UserId
	Sfx.playAt("strike_warning", warning.position, {
		offset = Config.WARNING_TIME - timeLeft,
		volume = if someoneElses then 0.4 else 1,
	})

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
	-- pulse the ring (slower and softer with Reduce flashing: it always shows)
	local calm = SettingsStore.get("reduceFlashing")
	TweenService:Create(
		ring,
		TweenInfo.new(
			if calm then 0.8 else 0.25,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut,
			-1,
			true
		),
		{ Transparency = if calm then 0.3 else 0.5 }
	):Play()
	if ZoneColours.assist() then
		colourblindMarks(anchor, warning.position, warning.radius, color, lifetime)
	end

	-- your Rod Tech's reach: a faint outer ring around the warning
	local rodTech, rodRank = activeLevel("RodTech")
	if rodTech then
		local reach = Research.catchRadius(rodTech, rodRank)
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

	-- rare bolts: a bigger, brighter pillar and a name over the ring; a
	-- Rainbow's colours keep cycling
	local orb: BasePart? = nil
	if rare then
		pillar.Size = Vector3.new(1.4, 120, 1.4)
		pillar.Position = warning.position + Vector3.new(0, 60, 0)
		pillar.Transparency = 0.55
		local tag = UI.make(Instance.new("BillboardGui"), {
			Name = "RareTag",
			Size = UDim2.fromOffset(220, 44),
			StudsOffset = Vector3.new(0, 7, 0),
			AlwaysOnTop = true,
			Parent = anchor,
		})
		UI.label({
			Title = true,
			Text = `{rare.label}!`,
			TextColor3 = rare.color,
			Size = UDim2.fromScale(1, 1),
			Parent = tag,
		})
		if rare.key == "Rainbow" then
			local beat = RunService.Heartbeat:Connect(function()
				local hue = (os.clock() * 0.6) % 1
				local rainbow = Color3.fromHSV(hue, 0.75, 1)
				ring.Color3 = rainbow
				fill.Color3 = rainbow
				pillar.Color = rainbow
			end)
			anchor.Destroying:Once(function()
				beat:Disconnect()
			end)
		end
	end
	-- Ball lightning: an orb that drifts from the ring to orbTo
	local orbTo = warning.orbTo
	if warning.boltType == "Ball" and orbTo and orbSeconds > 0 then
		local ball = Config.BALL_LIGHTNING
		local lift = Vector3.new(0, ball.height, 0)
		local part = effectPart({
			Name = "BallLightning",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(3, 3, 3),
			Position = warning.position + lift,
			Color = color,
			Transparency = 0.1,
			Parent = fxFolder,
		})
		if SettingsStore.get("glow") ~= "Off" then
			UI.make(Instance.new("PointLight"), {
				Color = color,
				Brightness = 4,
				Range = 18,
				Parent = part,
			})
		end
		Debris:AddItem(part, lifetime)
		local from = warning.position
		local beat = RunService.Heartbeat:Connect(function()
			local t =
				math.clamp((workspace:GetServerTimeNow() - warning.landsAt) / orbSeconds, 0, 1)
			local bob = Vector3.new(0, math.sin(os.clock() * 6) * 0.4, 0)
			part.Position = from:Lerp(orbTo, t) + lift + bob
		end)
		part.Destroying:Once(function()
			beat:Disconnect()
		end)
		orb = part
	end

	warnings[warning.id] = { anchor = anchor, pillar = pillar, orb = orb }
end

-- Does this strike concern you: you caught it (or were full, or it went to
-- your tank), it's your balloon bolt, or it landed in the zone you're in?
local function isMine(landed: Types.StrikeLanded): boolean
	local me = player.UserId
	if
		table.find(landed.catchers, me)
		or table.find(landed.full, me)
		or table.find(landed.tanked, me)
		or landed.ownerId == me
	then
		return true
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local zone = if root and root:IsA("BasePart") then Zones.at(root.Position) else nil
	return zone ~= nil and zone.id == landed.zoneId
end

local function onLanded(landed: Types.StrikeLanded)
	local warning = warnings[landed.id]
	local orbAt: Vector3? = nil
	if warning then
		warnings[landed.id] = nil
		warning.anchor:Destroy()
		warning.pillar:Destroy()
		if warning.orb then
			orbAt = warning.orb.Position
			warning.orb:Destroy()
		end
	end
	local rare = Weather.boltDef(landed.boltType)
	local tint = if rare then rare.color else nil
	if landed.boltType == "Rainbow" then
		tint = Color3.fromHSV(random:NextNumber(), 0.75, 1)
	end

	-- how much to draw (Util/StrikeFx): your own strikes in full; another
	-- world's not at all (not even its sound); someone else's (a zone you're
	-- not in, nothing to do with you) by distance and Others' lightning:
	-- Off, Simple (no branches, sparks or glow) or Full
	local mine = isMine(landed)
	local strikeZone = Config.ZONES[landed.zoneId]
	local sameWorld = strikeZone == nil or strikeZone.world == Portals.worldOf(player).id
	local camera = workspace.CurrentCamera
	local level = StrikeFx.level({
		distance = if camera then (camera.CFrame.Position - landed.position).Magnitude else 0,
		sameWorld = sameWorld,
		mine = mine,
		setting = SettingsStore.get("othersStrikes"),
	})
	if level ~= "none" then
		local simple = level == "simple"
		if landed.boltType ~= "Ball" then
			local sky = landed.position
				+ Vector3.new(random:NextNumber(-15, 15), BOLT_HEIGHT, random:NextNumber(-15, 15))
			-- a rare bolt is thicker, with more branches, in its colour
			bolt(
				sky,
				landed.position,
				if rare then 0.9 else 0.5,
				if simple then 0 elseif rare then 4 else 2,
				tint
			)
		end
		impact(landed.position, simple, mine)

		-- little arcs from the strike (or the orb) into every catcher's bottle
		local from = orbAt or landed.position + Vector3.new(0, 1, 0)
		for _, userId in landed.catchers do
			local target = bottlePosition(userId)
			if target then
				bolt(from, target, 0.18, 0, arcColour(userId) or tint)
			end
		end
	end
	if mine or sameWorld then
		playThunderAt(landed.position, landed.ownerId == player.UserId)
	end

	local caught = table.find(landed.catchers, player.UserId)
	if caught then
		screenFlash(0.55)
		cameraShake(0.3, 0.7)
		popup(`+{Format.abbreviate(landed.values[caught] or landed.value)} ⚡`, true, 0.42)
		Sfx.play(catchSound())
		-- a rare bolt: "GOLDEN x10!" (and the Rainbow's boost)
		if rare then
			Sfx.play("jackpot")
			popup(`{rare.label} x{rare.multiplier}!`, true, 0.3, 0.09)
			screenFlash(0.4)
			cameraShake(0.35, 0.8)
			local boost = if landed.boost then BoostRules.def(landed.boost) else nil
			if boost and rare.boostMinutes then
				popup(`+{rare.boostMinutes} min {boost.icon} {boost.name}`, true, 0.58, 0.05)
			end
		end
		-- the Analyst's assay and Lucky Charges each double it
		local assayed = table.find(landed.assayed, player.UserId) ~= nil
		local lucky = table.find(landed.lucky, player.UserId) ~= nil
		if assayed and lucky then
			Sfx.play("jackpot")
			popup("x4 JACKPOT", true, 0.5, 0.075)
			cameraShake(0.25, 0.5)
		elseif lucky then
			Sfx.play("lucky")
			popup("x2 LUCKY", true, 0.5, 0.06)
		elseif assayed then
			Sfx.play("lucky")
			popup("x2 ASSAYED", true, 0.5, 0.06)
		end
	elseif table.find(landed.tanked, player.UserId) then
		local zone = Config.ZONES[landed.zoneId]
		local snapshot = State.current
		local units = if zone and snapshot then Progression.chargeSize(snapshot, zone) else 1
		popup(`+{units} → TANK`, true, 0.42, 0.06)
		Sfx.play("tank_glug")
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
		y += 0.05
	end
	-- a scheduled event (Double Volts Weekend)
	for _, active in Weather.liveEvents() do
		popup(`x{active.event.multiplier} {string.upper(active.event.name)}`, true, y, 0.045)
		y += 0.05
	end
	screenFlash(0.25)
	cameraShake(0.2, 0.35)
	-- the ka-ching grows with how much of a bottle you sold
	local snapshot = State.current
	local share = if snapshot then count / math.max(snapshot.capacity, 1) else 0
	Sfx.play(
		if share >= 0.9 then "sell_big" elseif share >= 0.34 then "sell_medium" else "sell_small"
	)
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

	RunService.RenderStepped:Connect(stepBolts)
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
