--!strict
-- The Game Pass perks other players see (the pass maths is in
-- Shared/Util/Passes, ownership in Systems/Passes):
--   * Bolt Colours: SetBoltColour(index) saves the owner's lightning colour
--     (profile.boltColour, 0 = default) and puts it on the BoltColour player
--     attribute, which StrikeFX (arcs) and Bottles (charge glow) read.
--   * VIP: a small "⚡ STORM VIP" title over the head, seen from up to
--     TITLE_DISTANCE studs away.
-- (VIP's gold bottle is Systems/Bottles; its chat tag Controllers/VipChat.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local PassRules = require(ReplicatedStorage.Shared.Util.Passes)
local Types = require(ReplicatedStorage.Shared.Types)
local Passes = require(script.Parent.Passes)
local PlayerData = require(script.Parent.PlayerData)
local Sync = require(script.Parent.Sync)
local RateLimit = require(ServerScriptService.Server.Lib.RateLimit)

local BOLT_ATTRIBUTE = PassRules.BOLT_ATTRIBUTE
local TITLE_NAME = "VipTitle"
local TITLE_DISTANCE = 60

local PassPerks = {}

local function onSetBoltColour(player: Player, index: unknown)
	if not RateLimit.allow(player, "SetBoltColour", 2, 4) then
		return
	end
	if not PassRules.isValidColour(index) or not Passes.owns(player, "BoltColours") then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local choice = index :: number
	profile.boltColour = choice
	player:SetAttribute(BOLT_ATTRIBUTE, choice)
	Sync.markDirty(player)
end

local function makeTitle(head: BasePart): BillboardGui
	local title = Instance.new("BillboardGui")
	title.Name = TITLE_NAME
	title.Adornee = head
	-- sized in studs, so it shrinks with distance like the world does
	title.Size = UDim2.fromScale(4.4, 0.8)
	title.StudsOffsetWorldSpace = Vector3.new(0, 3.3, 0) -- above the name
	title.MaxDistance = TITLE_DISTANCE
	title.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "⚡ STORM VIP"
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Config.VIP_GOLD
	label.Parent = title
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(70, 40, 0)
	stroke.Parent = label
	title.Parent = head
	return title
end

-- Puts the title on (or takes it off) the player's current character.
local function updateTitle(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local existing = head:FindFirstChild(TITLE_NAME)
	local vip = Passes.owns(player, "VIP")
	if vip and not existing then
		makeTitle(head)
	elseif not vip and existing then
		existing:Destroy()
	end
end

local function onLoaded(player: Player, profile: Types.Profile)
	-- a saved pick that no longer exists falls back to the default
	if not PassRules.isValidColour(profile.boltColour) then
		profile.boltColour = 0
	end
	player:SetAttribute(BOLT_ATTRIBUTE, profile.boltColour)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Head", 5)
		updateTitle(player)
	end)
	player:GetAttributeChangedSignal(Passes.ATTRIBUTE .. "VIP"):Connect(function()
		updateTitle(player)
	end)
	updateTitle(player)
end

function PassPerks.init()
	Net.get("SetBoltColour").OnServerEvent:Connect(onSetBoltColour)
	PlayerData.Loaded:Connect(onLoaded)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return PassPerks
