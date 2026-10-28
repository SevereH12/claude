--!strict
-- The new-player tutorial, as the player sees it (the rules: Util/Tutorial;
-- the server moves the step on: Systems/Tutorial). While a step is on:
--   * a step card in the middle of the top (Layout.hud.tutorial; the toasts
--     move under it) with one short line and SKIP, which asks "Skip the
--     tutorial?" first (YES sends "skip" on the Tutorial remote)
--   * step 1: a glowing Beam from the player to the first zone's gate, and
--     a beacon there
--   * step 2: the catch count, or (when it's calm) the storm timer
--     explained, with the timer pointed at
--   * step 3: once the bottle is full, a Beam to the nearest sell pad
--   * step 4: once they can afford it, it points at the MENU button, then
--     the SHOP tile, then the next bottle's Buy button, in turn
--   * "finished" (Tutorial remote): "You're a Storm Bottler!" for a few
--     seconds; the reward itself celebrates like any reward (Rewarded)
-- Everything here is local and only shows things: the server decides.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Portals = require(ReplicatedStorage.Shared.Util.Portals)
local Types = require(ReplicatedStorage.Shared.Types)
local TutorialRules = require(ReplicatedStorage.Shared.Util.Tutorial)
local Zones = require(ReplicatedStorage.Shared.Util.Zones)
local Celebrate = require(script.Parent.Parent.Lib.Celebrate)
local Layout = require(script.Parent.Parent.Lib.Layout)
local Sfx = require(script.Parent.Parent.Lib.Sfx)
local UI = require(script.Parent.Parent.Lib.UI)
local Menu = require(script.Parent.Menu)
local ShopUI = require(script.Parent.ShopUI)
local State = require(script.Parent.State)
local Storm = require(script.Parent.Storm)

local COLORS = UI.COLORS
local TICK = 0.2 -- seconds between updates
local FINISH_SECONDS = 5 -- how long "You're a Storm Bottler!" stays
local GATE_INSET = 6 -- studs inside the zone's gate edge the path ends
local SELL_TAG = "SellArea"
local PATH_COLOR = Color3.fromRGB(255, 230, 90)
local BOB = TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

local Tutorial = {}

local player = Players.LocalPlayer
local remote: RemoteEvent
local card: Frame
local line: TextLabel
local skipButton: TextButton
local yesButton: TextButton
local noButton: TextButton
local confirming = false
local skipped = false -- SKIP was confirmed: hide until the server agrees
local caught = 0 -- step 2's catches (the server says)
local finishUntil = 0
local lastStep = -1
local shopWasOpen = false

-- the path: a Beam from the player's feet to a spot, and a beacon there
local pathFolder: Folder? = nil
local startAttachment: Attachment? = nil
local endAttachment: Attachment? = nil
local beam: Beam? = nil
local beacon: BasePart? = nil

-- the pointer: a glowing outline and a bouncing arrow on a button
local pointer: Frame
local pointerArrow: TextLabel
local pointerTarget: GuiObject? = nil

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Where step 1's path ends: just inside the first zone's gate (the zone
-- faces the hub along -Z; its gate is the middle of that edge).
local function gatePosition(): Vector3?
	local part = Zones.part(Config.TUTORIAL.zone)
	if not part then
		return nil
	end
	local spot = part.CFrame * CFrame.new(0, 1 - part.Size.Y / 2, -part.Size.Z / 2 + GATE_INSET)
	return spot.Position
end

-- Where step 3's path ends: the nearest sell pad in the player's world.
local function sellPosition(from: Vector3): Vector3?
	local best: Vector3? = nil
	local bestDistance = math.huge
	local world = Portals.worldOf(player)
	for _, area in CollectionService:GetTagged(SELL_TAG) do
		if area:IsA("BasePart") and area:IsDescendantOf(workspace) then
			local spot = area.Position - Vector3.new(0, area.Size.Y / 2 - 1, 0)
			local offset = spot - world.offset
			local distance = (spot - from).Magnitude
			-- the pad in this world (worlds are 5000 studs apart)
			if Vector2.new(offset.X, offset.Z).Magnitude < 2500 and distance < bestDistance then
				best, bestDistance = spot, distance
			end
		end
	end
	return best
end

local function clearPath()
	if pathFolder then
		pathFolder:Destroy()
	end
	pathFolder, startAttachment, endAttachment, beam, beacon = nil, nil, nil, nil, nil
end

-- Shows the path to `target` (or hides it with nil).
local function showPath(target: Vector3?)
	local root = rootPart()
	if not target or not root then
		clearPath()
		return
	end
	if not pathFolder then
		local folder = Instance.new("Folder")
		folder.Name = "TutorialPath"
		folder.Parent = workspace
		pathFolder = folder
		local finish = Instance.new("Attachment")
		finish.Name = "PathEnd"
		finish.Parent = workspace.Terrain
		endAttachment = finish
		local light = Instance.new("Part")
		light.Name = "Beacon"
		light.Anchored = true
		light.CanCollide = false
		light.CanQuery = false
		light.CanTouch = false
		light.CastShadow = false
		light.Material = Enum.Material.Neon
		light.Color = PATH_COLOR
		light.Transparency = 0.45
		light.Size = Vector3.new(1.2, 40, 1.2)
		light.Parent = folder
		beacon = light
		local ribbon = Instance.new("Beam")
		ribbon.Name = "Path"
		ribbon.Color = ColorSequence.new(PATH_COLOR)
		ribbon.LightEmission = 1
		ribbon.LightInfluence = 0
		ribbon.Transparency = NumberSequence.new(0.25)
		ribbon.Width0 = 1.6
		ribbon.Width1 = 1.6
		ribbon.FaceCamera = true
		ribbon.Segments = 1
		ribbon.Attachment1 = finish
		ribbon.Parent = folder
		beam = ribbon
		-- the end attachment lives in Terrain: remove it with the folder
		folder.Destroying:Connect(function()
			finish:Destroy()
		end)
	end
	-- the start sits at the player's feet; a new character needs a new one
	if not startAttachment or startAttachment.Parent ~= root then
		if startAttachment then
			startAttachment:Destroy()
		end
		local start = Instance.new("Attachment")
		start.Name = "TutorialPathStart"
		start.Position = Vector3.new(0, -2.5, 0)
		start.Parent = root
		startAttachment = start
		if beam then
			beam.Attachment0 = start
		end
	end
	if endAttachment then
		endAttachment.WorldPosition = target + Vector3.new(0, 0.5, 0)
	end
	if beacon then
		beacon.Position = target + Vector3.new(0, 20, 0)
	end
end

-- Points at `target` (or nobody with nil). The arrow goes on the side
-- `side` says: "right" of the button, or "left".
local function pointAt(target: GuiObject?, side: string?)
	if target == pointerTarget then
		return
	end
	pointerTarget = target
	if not target then
		pointer.Visible = false
		pointer.Parent = card -- out of the way
		return
	end
	-- cover the whole button: UI.button pads its contents
	local padding = target:FindFirstChildOfClass("UIPadding")
	if padding then
		local w = 1 - padding.PaddingLeft.Scale - padding.PaddingRight.Scale
		local h = 1 - padding.PaddingTop.Scale - padding.PaddingBottom.Scale
		-- (the title nudge moves the top and bottom padding by offsets)
		pointer.Position = UDim2.new(
			-padding.PaddingLeft.Scale / w,
			-padding.PaddingLeft.Offset,
			-padding.PaddingTop.Scale / h,
			-padding.PaddingTop.Offset
		)
		pointer.Size = UDim2.fromScale(1 / w, 1 / h)
	else
		pointer.Position = UDim2.new()
		pointer.Size = UDim2.fromScale(1, 1)
	end
	pointer.Parent = target
	pointer.Visible = true
	local left = side == "left"
	pointerArrow.Text = if left then "👉" else "👈"
	pointerArrow.AnchorPoint = Vector2.new(if left then 1 else 0, 0.5)
	pointerArrow.Position = if left then UDim2.new(0, -6, 0.5, 0) else UDim2.new(1, 6, 0.5, 0)
end

local function setConfirming(on: boolean)
	confirming = on
	skipButton.Visible = not on
	yesButton.Visible = on
	noButton.Visible = on
end

-- The bottle step 4 asks for: the next one (the Vial for a new player).
local function nextBottle(tier: number): Types.BottleDef
	return Config.BOTTLES[math.min(tier + 1, #Config.BOTTLES)]
end

-- Step 4's pointer: MENU, then SHOP, then the bottle's Buy button.
local function pointForShop(tier: number)
	if ShopUI.isOpen() then
		local button: GuiObject? = pointerTarget
		if not shopWasOpen or not button or not button:IsDescendantOf(game) then
			button = ShopUI.focusBottle(tier + 1)
		end
		shopWasOpen = true
		pointAt(button, "left")
		return
	end
	shopWasOpen = false
	if Menu.isOpen() then
		pointAt(Menu.tile("SHOP"), "right")
	else
		pointAt(Menu.button(), "right")
	end
end

local function stormPill(): GuiObject?
	local gui = player:FindFirstChildOfClass("PlayerGui")
	local found = gui and gui:FindFirstChild("StormPill", true)
	return if found and found:IsA("GuiObject") then found else nil
end

local function update()
	local snapshot = State.current
	local finishing = os.clock() < finishUntil
	local step = if snapshot then snapshot.tutorialStep else TutorialRules.DONE
	if skipped and not TutorialRules.isActive(step) then
		skipped = false
	end
	local active = TutorialRules.isActive(step) and not skipped
	Layout.setTutorial(active or finishing)
	card.Visible = active or finishing
	if not active or not snapshot then
		showPath(nil)
		pointAt(nil)
		if finishing then
			line.Text = `🎉 {TutorialRules.cardText(TutorialRules.FINISHED, {
				calm = false,
				secondsLeft = 0,
				caught = 0,
				full = false,
				nextBottle = "",
				price = 0,
				volts = 0,
			})}`
			skipButton.Visible = false
			yesButton.Visible = false
			noButton.Visible = false
		end
		lastStep = step
		return
	end
	if step ~= lastStep then
		if lastStep >= TutorialRules.WALK then
			Sfx.play("tab")
			UI.pop(card, 1.06)
		end
		lastStep = step
		if step ~= TutorialRules.CATCH then
			caught = 0
		end
	end
	if not confirming then
		skipButton.Visible = true
	end

	local state = Storm.current
	local calm = state ~= nil and state.phase ~= "Storm"
	local full = snapshot.chargeCount >= snapshot.capacity
	local bottle = nextBottle(snapshot.bottleTier)
	local text = TutorialRules.cardText(step, {
		calm = calm,
		secondsLeft = Storm.secondsLeft(),
		caught = caught,
		full = full,
		nextBottle = bottle.name,
		price = bottle.price,
		volts = snapshot.volts,
	})
	line.Text = if confirming then "Skip the tutorial?" else text

	local root = rootPart()
	if step == TutorialRules.WALK then
		showPath(gatePosition())
	elseif step == TutorialRules.SELL and full and root then
		showPath(sellPosition(root.Position))
	else
		showPath(nil)
	end

	if step == TutorialRules.CATCH and calm then
		pointAt(stormPill(), "right")
	elseif step == TutorialRules.BUY and snapshot.volts >= bottle.price then
		pointForShop(snapshot.bottleTier)
	else
		pointAt(nil)
	end
end

local function build()
	local _, root = Layout.screen("StormBottlerTutorial", 6)
	card = UI.panel({
		Name = "TutorialCard",
		Visible = false,
		Parent = root,
	})
	UI.onLayout(function()
		UI.place(card, Layout.hud.tutorial)
	end)
	line = UI.label({
		Title = true,
		Name = "Line",
		Text = "",
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0, 14, 0, 6),
		Size = UDim2.new(1, -150, 1, -12),
		Parent = card,
	})
	UI.maxText(line, 22)
	skipButton = UI.button({
		Name = "Skip",
		Text = "SKIP",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(110, 44),
		BackgroundColor3 = COLORS.panelDark,
		Parent = card,
	})
	UI.maxText(skipButton, 20)
	yesButton = UI.button({
		Name = "Yes",
		Text = "YES",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -72, 0.5, 0),
		Size = UDim2.fromOffset(58, 44),
		BackgroundColor3 = COLORS.red,
		Visible = false,
		Parent = card,
	})
	UI.maxText(yesButton, 20)
	noButton = UI.button({
		Name = "No",
		Text = "NO",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(58, 44),
		BackgroundColor3 = COLORS.green,
		Visible = false,
		Parent = card,
	})
	UI.maxText(noButton, 20)
	skipButton.Activated:Connect(function()
		setConfirming(true)
		update()
	end)
	noButton.Activated:Connect(function()
		setConfirming(false)
		update()
	end)
	yesButton.Activated:Connect(function()
		setConfirming(false)
		skipped = true
		remote:FireServer("skip")
		update()
	end)

	pointer = UI.make(Instance.new("Frame"), {
		Name = "TutorialPointer",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 50,
		Visible = false,
		Parent = card,
	})
	UI.corner(pointer, UDim.new(0, 14))
	local glow = UI.stroke(pointer, 5, COLORS.volt)
	glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	TweenService:Create(glow, BOB, { Transparency = 0.6 }):Play()
	pointerArrow = UI.label({
		Name = "Arrow",
		Text = "👈",
		Size = UDim2.fromOffset(44, 44),
		ZIndex = 51,
		Parent = pointer,
	})
	local bounce = UI.make(Instance.new("UIScale"), { Parent = pointerArrow })
	TweenService:Create(bounce, BOB, { Scale = 1.25 }):Play()
end

function Tutorial.init()
	remote = Net.get("Tutorial")
	build()
end

function Tutorial.start()
	remote.OnClientEvent:Connect(function(kind: unknown, value: unknown)
		if kind == "caught" and typeof(value) == "number" then
			caught = value
		elseif kind == "finished" then
			finishUntil = os.clock() + FINISH_SECONDS
			Sfx.play("purchase")
			Celebrate.sparks()
		end
		update()
	end)
	State.Changed:Connect(update)
	while true do
		update()
		task.wait(TICK)
	end
end

return Tutorial
