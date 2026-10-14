--!strict
-- All lightning visuals and feedback. Purely cosmetic: the server already
-- decided who caught what before any of this plays.
--
--   StrikeWarning -> glowing circle that fills up until the bolt lands
--   StrikeLanded  -> bolt + flash + thunder; if we caught it: screen flash,
--                    camera shake, "+5" popup, catch sound
--   Sold          -> big "+Volts" popup
--   State         -> bottle glows brighter as it fills

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Formulas = require(ReplicatedStorage.Shared.Util.Formulas)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local UI = require(script.Parent.Parent.Lib.UI)
local State = require(script.Parent.State)

local player = Players.LocalPlayer

local ZONE_COLORS: { [Types.ZoneMode]: Color3 } = {
	Shared = Color3.fromRGB(255, 225, 90),
	Single = Color3.fromRGB(255, 120, 70),
}
local BOLT_COLOR = Color3.fromRGB(200, 225, 255)
local BOLT_HEIGHT = 140
local BOLT_SEGMENTS = 7
local FADE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POPUP_RISE = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FULL_MESSAGE_COOLDOWN = 3

type Warning = { ring: BasePart, fill: BasePart }

local warnings: { [number]: Warning } = {}
local fxFolder: Folder
local screenGui: ScreenGui
local flashFrame: Frame
local random = Random.new()
local lastFullMessage = 0

local StrikeFX = {}

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

-- Flat disc lying on the ground (cylinders point along X, so tip it over).
local function discCFrame(position: Vector3, lift: number): CFrame
	return CFrame.new(position + Vector3.new(0, lift, 0)) * CFrame.Angles(0, 0, math.rad(90))
end

local function playSound(soundId: string, parent: Instance, speed: number?)
	local sound = UI.make(Instance.new("Sound"), {
		SoundId = soundId,
		Volume = 0.8,
		PlaybackSpeed = (speed or 1) * random:NextNumber(0.92, 1.08),
		RollOffMaxDistance = 400,
		Parent = parent,
	})
	sound:Play()
	Debris:AddItem(sound, 4)
end

local function playSoundAt(soundId: string, position: Vector3, speed: number?)
	local attachment = UI.make(Instance.new("Attachment"), {
		WorldPosition = position,
		Parent = workspace.Terrain,
	})
	playSound(soundId, attachment, speed)
	Debris:AddItem(attachment, 4)
end

local function popup(text: string, color: Color3, y: number)
	local label = UI.label({
		Text = text,
		TextColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, y),
		Size = UDim2.fromScale(0.4, 0.07),
		Parent = screenGui,
	})
	UI.maxText(label, 48)
	UI.pop(label, 1.25)
	local rise = TweenService:Create(label, POPUP_RISE, {
		Position = UDim2.fromScale(0.5, y - 0.08),
		TextTransparency = 1,
	})
	rise.Completed:Once(function()
		label:Destroy()
	end)
	rise:Play()
end

local function screenFlash()
	flashFrame.BackgroundTransparency = 0.35
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

local function onWarning(warning: Types.StrikeWarning)
	local timeLeft = warning.landsAt - workspace:GetServerTimeNow()
	if timeLeft <= 0 then
		return
	end
	local zone = Config.ZONES[warning.zoneId]
	local mode: Types.ZoneMode = if zone then zone.mode else "Shared"
	local color = ZONE_COLORS[mode]
	local diameter = warning.radius * 2

	local ring = effectPart({
		Name = "WarningRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, diameter, diameter),
		CFrame = discCFrame(warning.position, 0.1),
		Color = color,
		Transparency = 0.65,
		Parent = fxFolder,
	})
	local fill = effectPart({
		Name = "WarningFill",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 0.5, 0.5),
		CFrame = discCFrame(warning.position, 0.12),
		Color = color,
		Transparency = 0.35,
		Parent = fxFolder,
	})
	-- the inner disc grows to the edge exactly when the bolt lands
	TweenService:Create(fill, TweenInfo.new(timeLeft, Enum.EasingStyle.Linear), {
		Size = Vector3.new(0.2, diameter, diameter),
	}):Play()

	warnings[warning.id] = { ring = ring, fill = fill }
	-- safety net in case the landed event never arrives
	Debris:AddItem(ring, timeLeft + 2)
	Debris:AddItem(fill, timeLeft + 2)
end

local function bolt(position: Vector3)
	local points = {
		position + Vector3.new(random:NextNumber(-12, 12), BOLT_HEIGHT, random:NextNumber(-12, 12)),
	}
	for i = 1, BOLT_SEGMENTS - 1 do
		local t = i / BOLT_SEGMENTS
		local straight = points[1]:Lerp(position, t)
		local wobble = 6 * (1 - t)
		table.insert(
			points,
			straight
				+ Vector3.new(
					random:NextNumber(-wobble, wobble),
					0,
					random:NextNumber(-wobble, wobble)
				)
		)
	end
	table.insert(points, position)

	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local segment = effectPart({
			Name = "Bolt",
			Size = Vector3.new(0.6, 0.6, (b - a).Magnitude),
			CFrame = CFrame.lookAt((a + b) / 2, b),
			Color = BOLT_COLOR,
			Parent = fxFolder,
		})
		local fade = TweenService:Create(segment, FADE, { Transparency = 1 })
		fade.Completed:Once(function()
			segment:Destroy()
		end)
		fade:Play()
	end

	-- ground flash
	local flash = effectPart({
		Name = "ImpactFlash",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(4, 4, 4),
		Position = position,
		Color = BOLT_COLOR,
		Transparency = 0.2,
		Parent = fxFolder,
	})
	UI.make(Instance.new("PointLight"), {
		Color = BOLT_COLOR,
		Brightness = 8,
		Range = 45,
		Parent = flash,
	})
	local grow =
		TweenService:Create(flash, FADE, { Size = Vector3.new(16, 16, 16), Transparency = 1 })
	grow.Completed:Once(function()
		flash:Destroy()
	end)
	grow:Play()

	playSoundAt(Config.SOUNDS.STRIKE, position, 0.6)
end

local function onLanded(landed: Types.StrikeLanded)
	local warning = warnings[landed.id]
	if warning then
		warnings[landed.id] = nil
		warning.ring:Destroy()
		warning.fill:Destroy()
	end

	bolt(landed.position)

	if table.find(landed.catchers, player.UserId) then
		screenFlash()
		cameraShake(0.25, 0.6)
		popup(`+{Format.abbreviate(landed.value)} ⚡`, UI.COLORS.volt, 0.42)
		playSound(Config.SOUNDS.CATCH, screenGui, 1.2)
	elseif table.find(landed.full, player.UserId) then
		local now = os.clock()
		if now - lastFullMessage > FULL_MESSAGE_COOLDOWN then
			lastFullMessage = now
			popup("Bottle full! Sell at the Power Plant", UI.COLORS.red, 0.42)
		end
	end
end

local function onSold(earned: number, count: number)
	popup(`+{Format.abbreviate(earned)} Volts!`, UI.COLORS.volt, 0.35)
	popup(`sold {count} charges`, UI.COLORS.subtext, 0.42)
	cameraShake(0.15, 0.3)
	playSound(Config.SOUNDS.SELL, screenGui, 0.8)
end

-- Bottle glows brighter the fuller it is.
local function updateBottleGlow()
	local snapshot = State.current
	if not snapshot then
		return
	end
	local fill = snapshot.chargeCount / Formulas.capacity(snapshot.bottleTier)
	-- the tool lives in the character while equipped, otherwise in the backpack
	local containers: { Instance } = {}
	if player.Character then
		table.insert(containers, player.Character)
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		table.insert(containers, backpack)
	end
	for _, container in containers do
		local tool = container:FindFirstChild("Bottle")
		local handle = tool and tool:FindFirstChild("Handle")
		local glow = handle and handle:FindFirstChild("Glow")
		if glow and glow:IsA("PointLight") then
			glow.Brightness = fill * 4
		end
		if handle and handle:IsA("BasePart") then
			handle.Material = if fill > 0 then Enum.Material.Neon else Enum.Material.Glass
		end
	end
end

function StrikeFX.init()
	fxFolder = UI.make(Instance.new("Folder"), { Name = "StrikeFX", Parent = workspace })
	screenGui = UI.make(Instance.new("ScreenGui"), {
		Name = "StrikeFX",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 10,
		Parent = player:WaitForChild("PlayerGui"),
	})
	flashFrame = UI.make(Instance.new("Frame"), {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = screenGui,
	})

	Net.get("StrikeWarning").OnClientEvent:Connect(onWarning)
	Net.get("StrikeLanded").OnClientEvent:Connect(onLanded)
	Net.get("Sold").OnClientEvent:Connect(onSold)
end

function StrikeFX.start()
	State.Changed:Connect(updateBottleGlow)
	-- also catches respawns and equipping (the tool moves between containers)
	while true do
		updateBottleGlow()
		task.wait(0.5)
	end
end

return StrikeFX
