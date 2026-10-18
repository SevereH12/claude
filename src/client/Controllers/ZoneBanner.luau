--!strict
-- Big title card when you walk into a zone ("SHORELINE - everyone in the
-- circle catches"), a short note when you leave it (speed boost), and why a
-- zone is locked when you walk up to its gate. Other controllers use
-- ZoneBanner.show for their own news ("MESA UNLOCKED").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local Types = require(ReplicatedStorage.Shared.Types)
local Zones = require(ReplicatedStorage.Shared.Util.Zones)
local UI = require(script.Parent.Parent.Lib.UI)
local State = require(script.Parent.State)

local SHOW_TIME = 2.2
local GATE_NEAR = 18 -- studs from a locked gate's barrier to explain the lock
local GATE_FAR = 28 -- and this far away before it explains again
local FADE = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local player = Players.LocalPlayer

local ZoneBanner = {}

local banner: CanvasGroup
local title: TextLabel
local subtitle: TextLabel
local showToken = 0

function ZoneBanner.show(text: string, subtext: string, color: Color3)
	showToken += 1
	local token = showToken
	title.Text = text
	title.TextColor3 = color
	subtitle.Text = subtext
	banner.GroupTransparency = 1
	banner.Visible = true
	TweenService:Create(banner, FADE, { GroupTransparency = 0 }):Play()
	UI.pop(banner, 1.15)
	task.delay(SHOW_TIME, function()
		if showToken == token then
			TweenService:Create(banner, FADE, { GroupTransparency = 1 }):Play()
		end
	end)
end

function ZoneBanner.init()
	local screenGui = UI.make(Instance.new("ScreenGui"), {
		Name = "ZoneBanner",
		ResetOnSpawn = false,
		DisplayOrder = 3,
		Parent = player:WaitForChild("PlayerGui"),
	})
	banner = UI.make(Instance.new("CanvasGroup"), {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.27),
		Size = UDim2.fromScale(0.5, 0.13),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screenGui,
	})
	UI.make(Instance.new("UIScale"), { Parent = banner })
	title = UI.label({
		Title = true,
		Size = UDim2.fromScale(1, 0.65),
		Parent = banner,
	})
	UI.maxText(title, 72)
	subtitle = UI.label({
		Position = UDim2.fromScale(0, 0.65),
		Size = UDim2.fromScale(1, 0.33),
		Parent = banner,
	})
	UI.maxText(subtitle, 30)
end

-- When you walk up to the gate of a zone you can't enter yet, say why.
local explained: { [string]: boolean } = {}
local function nearLockedGate(position: Vector3)
	local snapshot = State.current
	local map = workspace:FindFirstChild("Map")
	local gates = map and map:FindFirstChild("ZoneGates")
	if not snapshot or not gates then
		return
	end
	for _, gate in gates:GetChildren() do
		local zone = Config.ZONES[gate.Name]
		local barrier = gate:FindFirstChild("Barrier")
		if zone and barrier and barrier:IsA("BasePart") then
			local reason = Progression.lockReason(snapshot, zone)
			local distance = (barrier.Position - position).Magnitude
			if reason and distance < GATE_NEAR and not explained[zone.id] then
				explained[zone.id] = true
				ZoneBanner.show(`🔒 {string.upper(zone.displayName)}`, reason, UI.COLORS.red)
			elseif distance > GATE_FAR then
				explained[zone.id] = nil
			end
		end
	end
end

function ZoneBanner.start()
	local current: Types.ZoneDef? = nil
	while true do
		task.wait(0.2)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local zone = Zones.at(root.Position)
			if zone ~= current then
				if zone then
					ZoneBanner.show(string.upper(zone.displayName), zone.tagline, zone.color)
				elseif current then
					ZoneBanner.show(
						"SPEED BOOST",
						"Running fast outside storm zones",
						UI.COLORS.calm
					)
				end
				current = zone
			end
			nearLockedGate(root.Position)
		end
	end
end

return ZoneBanner
