--!strict
-- Ascension (rebirth): the rules are Util/Ascension. The client never
-- decides anything here; it only asks, in two steps, on the Ascend remote:
--   1. Ascend() with no token: "can I?". The server checks the rules and
--      answers ("offer", { token, level, cost, seconds }) with a fresh token
--      that runs out after Config.ASCENSION.confirmSeconds, or
--      ("refused", reason).
--   2. Ascend(token) from the confirm screen: the server checks the token
--      (this player's, not run out, used once) and the rules again, then
--      resets the player (Ascension.ascend), moves them to Barometer Bay's
--      spawn and answers ("done", newLevel). Researchers posted to zones
--      the player can't enter any more go back to the Office (the offer
--      names them as `moving`, for the confirm screen). The profile is
--      saved straight away.
-- Both steps are rate-limited. The +50% per level needs nothing here:
-- Systems/Passes adds it to every sale.
--
-- Everyone sees the level: the player attribute Ascension, stars over the
-- head (a small title, above the VIP one) and in the player list (Sync).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AscensionRules = require(ReplicatedStorage.Shared.Util.Ascension)
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local PassRules = require(ReplicatedStorage.Shared.Util.Passes)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local StatRules = require(ReplicatedStorage.Shared.Util.Stats)
local Types = require(ReplicatedStorage.Shared.Types)
local PlayerData = require(script.Parent.PlayerData)
local Research = require(script.Parent.Research)
local Stats = require(script.Parent.Stats)
local Sync = require(script.Parent.Sync)
local Travel = require(script.Parent.Travel)
local RateLimit = require(ServerScriptService.Server.Lib.RateLimit)

local TOKEN_LENGTH = 64 -- characters; a real token (a GUID) is shorter
local TITLE_NAME = "AscensionTitle"
local TITLE_DISTANCE = 60
local TITLE_HEIGHT = 3.3 -- studs above the head, over the name
local ABOVE_VIP = 0.9 -- higher still when the VIP title is there too
local STAR_COLOR = Color3.fromRGB(190, 140, 255)

type Pending = { token: string, expires: number }

local pending: { [Player]: Pending } = {}

local Ascension = {}

local function setTitle(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local profile = PlayerData.get(player)
	local level = if profile then profile.ascension else 0
	local existing = head:FindFirstChild(TITLE_NAME)
	if level <= 0 then
		if existing then
			existing:Destroy()
		end
		return
	end
	local title = if existing and existing:IsA("BillboardGui") then existing else nil
	if not title then
		local made = Instance.new("BillboardGui")
		made.Name = TITLE_NAME
		made.Adornee = head
		made.Size = UDim2.fromScale(4.4, 0.8) -- studs, so it shrinks with distance
		made.MaxDistance = TITLE_DISTANCE
		made.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = STAR_COLOR
		label.Parent = made
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.fromRGB(40, 10, 70)
		stroke.Parent = label
		made.Parent = head
		title = made
	end
	assert(title)
	local vip = player:GetAttribute(PassRules.ATTRIBUTE .. "VIP") == true
	title.StudsOffsetWorldSpace = Vector3.new(0, TITLE_HEIGHT + (if vip then ABOVE_VIP else 0), 0)
	local label = title:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text = `{AscensionRules.stars(level)} ASCENDED`
	end
end

local function show(player: Player, profile: Types.Profile)
	player:SetAttribute(AscensionRules.ATTRIBUTE, profile.ascension)
	setTitle(player)
end

local function offer(player: Player, profile: Types.Profile, remote: RemoteEvent)
	local ok, reason = AscensionRules.canAscend(profile)
	if not ok then
		remote:FireClient(player, "refused", reason)
		return
	end
	local token = HttpService:GenerateGUID(false)
	local seconds = Config.ASCENSION.confirmSeconds
	pending[player] = { token = token, expires = os.clock() + seconds }
	-- researchers who'll go back to the Office, by name, for the confirm screen
	local moving: { string } = {}
	for _, roleId in AscensionRules.researchersToMove(profile, Progression.playerIsPremium(player)) do
		for _, def in Config.RESEARCHERS do
			if def.id == roleId then
				table.insert(moving, def.name)
			end
		end
	end
	remote:FireClient(player, "offer", {
		token = token,
		level = profile.ascension + 1,
		cost = AscensionRules.cost(profile.ascension),
		seconds = seconds,
		bonus = AscensionRules.bonusText(profile.ascension + 1),
		moving = moving,
	})
end

local function confirm(player: Player, profile: Types.Profile, token: string, remote: RemoteEvent)
	local waiting = pending[player]
	if not waiting or waiting.token ~= token then
		return
	end
	pending[player] = nil -- one use only
	if os.clock() > waiting.expires then
		remote:FireClient(player, "refused", "That took too long: press ASCEND again")
		return
	end
	local level, moved = AscensionRules.ascend(profile, Progression.playerIsPremium(player))
	if not level then
		local _, reason = AscensionRules.canAscend(profile)
		remote:FireClient(player, "refused", reason)
		return
	end
	Stats.add(player, StatRules.ASCENSIONS, 1)
	if #moved > 0 then
		Research.movedToOffice(player, moved)
	end
	Sync.markDirty(player)
	show(player, profile)
	print(`[Ascension] {player.Name} ascended to level {level}`)
	remote:FireClient(player, "done", level)
	-- saved straight away (like a purchase), so a server crash can't undo it
	task.spawn(PlayerData.saveNow, player)
	task.spawn(Travel.sendHome, player)
end

local function onAscend(player: Player, token: unknown)
	if not RateLimit.allow(player, "Ascend", 2, 6) then
		return
	end
	if token ~= nil and (typeof(token) ~= "string" or #token > TOKEN_LENGTH) then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local remote = Net.get("Ascend")
	if token == nil then
		offer(player, profile, remote)
	else
		confirm(player, profile, token :: string, remote)
	end
end

-- Studio TEST "Ready to ascend" (Systems/DevCommands only calls it in
-- Studio): the top bottle and exactly enough Volts for the next level.
function Ascension.testReady(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	profile.bottleTier = AscensionRules.topTier()
	profile.volts = math.max(profile.volts, AscensionRules.cost(profile.ascension))
	Sync.markDirty(player)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Head", 5)
		setTitle(player)
	end)
	player:GetAttributeChangedSignal(PassRules.ATTRIBUTE .. "VIP"):Connect(function()
		setTitle(player)
	end)
end

function Ascension.init()
	Net.get("Ascend").OnServerEvent:Connect(onAscend)
	PlayerData.Loaded:Connect(show)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return Ascension
