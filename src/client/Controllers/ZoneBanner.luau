--!strict
-- Big title card when you walk into a zone ("SHORELINE - everyone in the
-- circle catches"), plus two toasts (UI.toast): a short note when you leave
-- a zone (speed boost) and why a zone is locked when you walk up to its
-- gate. Every other message is a toast too; this banner is only for zone
-- titles and Server Storms (Controllers/Announcements). Each shows once per event: the card not again for the same zone
-- within REPEAT_TIME (walking along a zone's edge flips in and out), the
-- leave note at most every REPEAT_TIME, the gate reason once until you've
-- walked GATE_FAR away.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local Types = require(ReplicatedStorage.Shared.Types)
local Zones = require(ReplicatedStorage.Shared.Util.Zones)
local Layout = require(script.Parent.Parent.Lib.Layout)
local UI = require(script.Parent.Parent.Lib.UI)
local State = require(script.Parent.State)

local SHOW_TIME = 2.2
local REPEAT_TIME = 10
local GATE_NEAR = 18 -- studs from a locked gate's barrier to explain the lock
local GATE_FAR = 28 -- and this far away before it explains again
local FADE = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local player = Players.LocalPlayer

local ZoneBanner = {}

local banner: CanvasGroup
local title: TextLabel
local subtitle: TextLabel
local showToken = 0

-- A title card for SHOW_TIME seconds (or `seconds`). Each show bumps the
-- token; a hide only runs for the show that scheduled it, and ends invisible.
function ZoneBanner.show(text: string, subtext: string, color: Color3, seconds: number?)
	showToken += 1
	local token = showToken
	title.Text = text
	title.TextColor3 = color
	subtitle.Text = subtext
	banner.GroupTransparency = 1
	banner.Visible = true
	TweenService:Create(banner, FADE, { GroupTransparency = 0 }):Play()
	UI.pop(banner, 1.15)
	task.delay(seconds or SHOW_TIME, function()
		if showToken ~= token then
			return
		end
		local fade = TweenService:Create(banner, FADE, { GroupTransparency = 1 })
		fade.Completed:Once(function()
			if showToken == token then
				banner.Visible = false
			end
		end)
		fade:Play()
	end)
end

function ZoneBanner.init()
	local _, screenGui = Layout.screen("ZoneBanner", 3)
	-- the slot sits at Layout.hud.banner; the banner fills it from its centre,
	-- so its pop grows evenly
	local slot = UI.make(Instance.new("Frame"), {
		Name = "BannerSlot",
		BackgroundTransparency = 1,
		Parent = screenGui,
	})
	UI.onLayout(function()
		UI.place(slot, Layout.hud.banner)
	end)
	banner = UI.make(Instance.new("CanvasGroup"), {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = slot,
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
			local reason = Progression.lockReason(snapshot, zone, snapshot.premium)
			local distance = (barrier.Position - position).Magnitude
			if reason and distance < GATE_NEAR and not explained[zone.id] then
				explained[zone.id] = true
				UI.toast(`🔒 {zone.displayName}: {reason}`, "warn")
			elseif distance > GATE_FAR then
				explained[zone.id] = nil
			end
		end
	end
end

function ZoneBanner.start()
	local current: Types.ZoneDef? = nil
	local lastCard: { [string]: number } = {} -- zone id -> when its card last showed
	while true do
		task.wait(0.2)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local zone = Zones.at(root.Position)
			if zone ~= current then
				local now = os.clock()
				if zone then
					if now - (lastCard[zone.id] or -math.huge) >= REPEAT_TIME then
						lastCard[zone.id] = now
						local snapshot = State.current
						local size = if snapshot
							then Progression.chargeSize(snapshot, zone)
							else zone.chargeSize
						ZoneBanner.show(
							string.upper(zone.displayName),
							`{zone.tagline} · each bolt fills {size}`,
							zone.color
						)
					end
				elseif current then
					UI.toastEvery(
						"speedBoost",
						REPEAT_TIME,
						"Speed boost: you run fast outside storm zones",
						"good"
					)
				end
				current = zone
			end
			nearLockedGate(root.Position)
		end
	end
end

return ZoneBanner
