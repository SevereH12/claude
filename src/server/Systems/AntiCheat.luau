--!strict
-- Movement checks: teleport and speed cheats (the rules are Util/AntiCheat,
-- the numbers Config.ANTI_CHEAT). Every checkEvery seconds the server
-- looks at each living player's position. A move further than they could
-- walk makes them "suspect" for a few seconds: Strikes (bolts and ball
-- lightning) and Selling (stations) skip them until then. Nobody is kicked
-- or banned, since lag can look like a teleport too; repeat offenders are
-- logged ("[AntiCheat] ...") and listed in the admin panel (Systems/Errors
-- listens to AntiCheat.Logged).
--
-- Moves the server makes call AntiCheat.allowMove(player) first: portals
-- and the Teleport panel (Systems/Travel, also Ascension's trip home), the
-- AFK Lounge (Systems/Afk) and the zone lock (Systems/Movement). A new
-- character (a respawn) starts a fresh check by itself.
--
-- Checking Humanoid.WalkSpeed wouldn't help: a client's change to it never
-- reaches the server, so the server always sees what Movement set. The
-- distance check catches a faster walk instead.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local AntiCheatRules = require(ReplicatedStorage.Shared.Util.AntiCheat)
local Formulas = require(ReplicatedStorage.Shared.Util.Formulas)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Zones = require(ReplicatedStorage.Shared.Util.Zones)
local Passes = require(script.Parent.Passes)
local PlayerData = require(script.Parent.PlayerData)

local RULES = Config.ANTI_CHEAT

local tracks: { [Player]: AntiCheatRules.Track } = {}
local roots: { [Player]: BasePart } = {} -- the root part being tracked

local AntiCheat = {}

-- Fires for each impossible move of a player who has made
-- Config.ANTI_CHEAT.logAfter of them: (player, what happened).
AntiCheat.Logged = Signal.new() :: Signal.Signal<Player, string>

local function trackOf(player: Player): AntiCheatRules.Track
	local track = tracks[player]
	if not track then
		track = AntiCheatRules.new()
		tracks[player] = track
	end
	return track
end

-- The server is about to move this player (call it just before PivotTo).
function AntiCheat.allowMove(player: Player)
	AntiCheatRules.allowMove(trackOf(player), os.clock())
end

-- True while this player may not catch or sell (an impossible move just now).
function AntiCheat.isSuspect(player: Player): boolean
	local track = tracks[player]
	return track ~= nil and AntiCheatRules.isSuspect(track, os.clock())
end

local function check(player: Player, now: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local profile = PlayerData.get(player)
	if
		not humanoid
		or humanoid.Health <= 0
		or not root
		or not root:IsA("BasePart")
		or not profile
	then
		return
	end
	local track = trackOf(player)
	if roots[player] ~= root then
		roots[player] = root -- a new character: it spawned somewhere new
		AntiCheatRules.allowMove(track, now)
	end
	local owned = Passes.owned(player)
	local speeds: AntiCheatRules.Speeds = {
		inZone = math.max(Formulas.walkSpeed(true, profile.bootTier, owned), humanoid.WalkSpeed),
		outside = math.max(Formulas.walkSpeed(false, profile.bootTier, owned), humanoid.WalkSpeed),
	}
	local position = root.Position
	local sample: AntiCheatRules.Sample =
		{ x = position.X, z = position.Z, at = now, inZone = Zones.at(position) ~= nil }
	if not AntiCheatRules.step(track, sample, speeds) then
		return
	end
	local text =
		`impossible move by {player.Name} (no catching or selling for {RULES.suspectSeconds} s)`
	print(`[AntiCheat] {text}, {track.strikes} so far`)
	if AntiCheatRules.shouldLog(track) then
		AntiCheat.Logged:Fire(player, text)
	end
end

function AntiCheat.init()
	Players.PlayerRemoving:Connect(function(player)
		tracks[player] = nil
		roots[player] = nil
	end)
end

function AntiCheat.start()
	while true do
		task.wait(RULES.checkEvery)
		local now = os.clock()
		for _, player in Players:GetPlayers() do
			check(player, now)
		end
	end
end

return AntiCheat
