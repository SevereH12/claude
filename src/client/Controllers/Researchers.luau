--!strict
-- Draws every player's Storm Society team. The server publishes
-- Research_<RoleId> = "<post>:<level>" on each Player; this reads those and
-- stands a model at the post's camp deck (or around the Research Office).
-- Your own researchers take the front spots and wear a name tag. Models are
-- local to this client. One Heartbeat loop animates the ones near the camera.
--
-- Reactions use only events that exist: your Forecaster points on Forecast,
-- an Analyst prints tape when StrikeLanded lists its owner in `assayed`, a
-- Storm Chaser's balloon jerks during a StrikeWarning with its owner's
-- `ownerId`, and your Chemist's tank fill follows the snapshot's tankCount.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local ResearchMath = require(ReplicatedStorage.Shared.Util.Research)
local ResearchSites = require(ReplicatedStorage.Shared.Util.ResearchSites)
local Types = require(ReplicatedStorage.Shared.Types)
local ResearcherModels = require(script.Parent.Parent.Lib.ResearcherModels)
local SettingsStore = require(script.Parent.Parent.Lib.SettingsStore)
local State = require(script.Parent.State)
local Storm = require(script.Parent.Storm)

local S = ResearcherModels.SCALE
local MAX_PER_SITE = 8
local ANIMATE_RANGE_SQ = 250 * 250
local RETRY_SECONDS = 2
local TAPE_SECONDS = 1.6
local CYAN = Color3.fromRGB(90, 230, 255)

-- Spots on a camp deck, in the camp box's own frame (x along the 28-stud
-- width, z along the 14-stud depth; the zone is toward +Z). Front first.
local CAMP_SPOTS: { Vector2 } = {
	Vector2.new(-3, 4.5),
	Vector2.new(1, 4.5),
	Vector2.new(-7, 4.5),
	Vector2.new(5, 4.5),
	Vector2.new(-11, 4.5),
	Vector2.new(9, 4.5),
	Vector2.new(-1, 0.5),
	Vector2.new(-10, 0.5),
}

type Rig = {
	key: string,
	userId: number,
	roleId: string,
	own: boolean,
	site: string,
	level: number,
	rank: number,
	model: Model,
	pivot: CFrame,
	pos: Vector3,
	seed: number,
	brace: number, -- 0 calm .. 1 hood up
	lit: boolean,
	pointUntil: number,
	tapeUntil: number,
	jerkUntil: number,
	fill: number,
	tag: TextLabel?,
	arm: BasePart,
	shoulder: CFrame,
	hood: BasePart,
	hoodBase: CFrame,
	inst: BasePart,
	instBase: CFrame,
	instColor: Color3,
	instMaterial: Enum.Material,
	fillPart: BasePart?,
	fillBase: CFrame,
	fillFull: number,
	tape: BasePart?,
	tapeBase: CFrame,
	tapeSize: Vector3,
	balloon: { BasePart },
	balloonBase: { CFrame },
	tether: BasePart?,
	peg: Vector3,
}

type Entry = { post: string, level: number, rank: number }

local Researchers = {}

local folder: Folder
local rigs: { [string]: Rig } = {} -- "<userId>:<roleId>"
local rigList: { Rig } = {}
local entries: { [Player]: { [string]: Entry } } = {}
local boards: { [string]: { part: BasePart, label: TextLabel } } = {}
local roleOrder: { [string]: number } = {}
local dirty = true
local retryAt = 0

local localPlayer = Players.LocalPlayer

-- Placement -------------------------------------------------------------------

local function parseAttribute(value: unknown): Entry?
	if typeof(value) ~= "string" then
		return nil
	end
	-- "<post>:<level>:<rank>" (older servers: "<post>:<level>")
	local post, level, rank = string.match(value, "^([^:]+):(%d+):?(%d*)$")
	if not post or not level then
		return nil
	end
	return { post = post, level = tonumber(level) or 1, rank = tonumber(rank) or 0 }
end

local function readPlayer(player: Player)
	local mine: { [string]: Entry } = {}
	for _, def in Config.RESEARCHERS do
		local entry = parseAttribute(player:GetAttribute(`Research_{def.id}`))
		if entry then
			mine[def.id] = entry
		end
	end
	entries[player] = mine
	dirty = true
end

-- World frames for a site's spots, front first, or nil if the site isn't in
-- the world (yet).
local function spotsFor(site: string): ({ CFrame }?, CFrame?)
	if site == "Office" then
		local office = ResearchSites.offices()[1]
		if not office then
			return nil, nil
		end
		local size = office.Size
		local floor = CFrame.new(0, 1 - size.Y / 2, 0)
		local frames: { CFrame } = {}
		for _, row in { -0.2, 0.2 } do
			for _, column in { 2, 3, 1, 4 } do
				table.insert(
					frames,
					office.CFrame * floor * CFrame.new((column - 2.5) * size.X / 4, 0, row * size.Z)
				)
			end
		end
		return frames, office.CFrame * CFrame.new(0, size.Y / 2 + 1, 0)
	end
	local camp = ResearchSites.camp(site)
	if not camp then
		return nil, nil
	end
	-- the box's base is 1 below the camp height; the deck is lifted above that
	local floor = camp.CFrame * CFrame.new(0, 1 + ResearchSites.CAMP_DECK_LIFT - camp.Size.Y / 2, 0)
	local frames: { CFrame } = {}
	for _, spot in CAMP_SPOTS do
		table.insert(frames, floor * CFrame.new(spot.X, 0, spot.Y) * CFrame.Angles(0, math.pi, 0))
	end
	return frames, floor * CFrame.new(0, 5, -6)
end

-- "Dr. Isobar · Forecaster Lv3 ★★": a gold star per rank.
local function tagText(roleId: string, level: number, rank: number): string
	local def = ResearchMath.def(roleId)
	local stars = if rank > 0 then ` <font color="#FFD23C">{string.rep("★", rank)}</font>` else ""
	return if def then `{def.name} · {def.role} Lv{level}{stars}` else roleId
end

local function makeTag(model: Model, text: string): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "NameTag"
	gui.Size = UDim2.fromOffset(240, 26)
	gui.StudsOffset = Vector3.new(0, 3.2, 0)
	gui.MaxDistance = 70
	gui.Enabled = SettingsStore.get("showNameTags") -- SETTINGS > Accessibility & HUD
	local head = model:FindFirstChild("Head")
	if head then
		gui.Adornee = head
	end
	gui.Parent = model
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(24, 30, 44)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = Color3.fromRGB(240, 240, 232)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 15
	label.RichText = true
	label.Text = text
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	return label
end

local function part(model: Model, name: string): BasePart?
	local found = model:FindFirstChild(name)
	return if found and found:IsA("BasePart") then found else nil
end

local function makeRig(
	userId: number,
	own: boolean,
	roleId: string,
	level: number,
	rank: number
): Rig
	local model = ResearcherModels.build(roleId)
	model.Name = `{userId}_{roleId}`
	local arm = part(model, "Arm") :: BasePart
	local hood = part(model, "Hood") :: BasePart
	local inst = part(model, "Instrument") :: BasePart
	local fillPart = part(model, "TankFill")
	local tape = part(model, "Tape")
	local tether = part(model, "Tether")
	local peg = part(model, "Peg")

	local balloon: { BasePart } = {}
	local balloonBase: { CFrame } = {}
	for _, name in { "Balloon", "Stripe", "Stripe2" } do
		local piece = part(model, name)
		if piece then
			table.insert(balloon, piece)
			table.insert(balloonBase, piece.CFrame)
		end
	end

	local rig: Rig = {
		key = `{userId}:{roleId}`,
		userId = userId,
		roleId = roleId,
		own = own,
		site = "",
		level = level,
		rank = rank,
		model = model,
		pivot = CFrame.identity,
		pos = Vector3.zero,
		seed = (userId % 97) * 0.7 + (roleOrder[roleId] or 1) * 1.9,
		brace = 0,
		lit = false,
		pointUntil = 0,
		tapeUntil = 0,
		jerkUntil = 0,
		fill = 0,
		tag = if own then makeTag(model, tagText(roleId, level, rank)) else nil,
		arm = arm,
		shoulder = arm.CFrame * CFrame.new(0, 0.65 * S, 0),
		hood = hood,
		hoodBase = hood.CFrame,
		inst = inst,
		instBase = inst.CFrame,
		instColor = inst.Color,
		instMaterial = inst.Material,
		fillPart = fillPart,
		fillBase = if fillPart then fillPart.CFrame else CFrame.identity,
		fillFull = if fillPart then fillPart.Size.X else 0,
		tape = tape,
		tapeBase = if tape then tape.CFrame else CFrame.identity,
		tapeSize = if tape then tape.Size else Vector3.zero,
		balloon = balloon,
		balloonBase = balloonBase,
		tether = tether,
		peg = if peg then peg.Position + Vector3.new(0, peg.Size.X / 2, 0) else Vector3.zero,
	}
	model.Parent = folder
	rigs[rig.key] = rig
	table.insert(rigList, rig)
	return rig
end

local function destroyRig(rig: Rig)
	rigs[rig.key] = nil
	local index = table.find(rigList, rig)
	if index then
		table.remove(rigList, index)
	end
	rig.model:Destroy()
end

local function setBoard(site: string, anchor: CFrame?, extra: number)
	local board = boards[site]
	if extra <= 0 or not anchor then
		if board then
			board.part.Parent = nil
		end
		return
	end
	if not board then
		local anchorPart = Instance.new("Part")
		anchorPart.Name = `Board_{site}`
		anchorPart.Anchored = true
		anchorPart.CanCollide = false
		anchorPart.CanQuery = false
		anchorPart.CanTouch = false
		anchorPart.Transparency = 1
		anchorPart.Size = Vector3.one
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(180, 30)
		gui.MaxDistance = 90
		gui.Adornee = anchorPart
		gui.Parent = anchorPart
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(24, 30, 44)
		label.BackgroundTransparency = 0.2
		label.TextColor3 = Color3.fromRGB(240, 240, 232)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 16
		label.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = label
		board = { part = anchorPart, label = label }
		boards[site] = board
	end
	board.part.CFrame = anchor
	board.label.Text = `+{extra} more on site`
	board.part.Parent = folder
end

type Row = { userId: number, own: boolean, roleId: string, level: number, rank: number, site: string }

-- Decide who stands where. Cheap (a handful of researchers), and only runs
-- when something changed.
local function layout()
	dirty = false

	-- a saved post that isn't in the world falls back to the office
	local function siteOf(entry: Entry): string
		return if entry.post ~= "Office" and not Config.ZONES[entry.post]
			then "Office"
			else entry.post
	end
	-- other players' researchers follow SETTINGS > Graphics: Hidden, only at
	-- sites where yours work, or All
	local others = SettingsStore.get("othersResearchers")
	local mySites: { [string]: boolean } = {}
	for _, entry in entries[localPlayer] or {} do
		mySites[siteOf(entry)] = true
	end
	local bySite: { [string]: { Row } } = {}
	local wanted: { [string]: boolean } = {}
	for player, mine in entries do
		local own = player == localPlayer
		for roleId, entry in mine do
			local site = siteOf(entry)
			if not own and (others == "Hidden" or (others == "My sites" and not mySites[site])) then
				continue
			end
			local list = bySite[site]
			if not list then
				list = {}
				bySite[site] = list
			end
			table.insert(list, {
				userId = player.UserId,
				own = own,
				roleId = roleId,
				level = entry.level,
				rank = entry.rank,
				site = site,
			})
		end
	end

	local missing = false
	for site, list in bySite do
		table.sort(list, function(a: Row, b: Row)
			if a.own ~= b.own then
				return a.own
			end
			if a.userId ~= b.userId then
				return a.userId < b.userId
			end
			return (roleOrder[a.roleId] or 99) < (roleOrder[b.roleId] or 99)
		end)
		local frames, boardAt = spotsFor(site)
		if not frames then
			missing = true
		end
		local slots = if frames then math.min(MAX_PER_SITE, #frames) else 0
		for index, row in list do
			local key = `{row.userId}:{row.roleId}`
			local rig = rigs[key]
			if frames and index <= slots then
				wanted[key] = true
				if not rig then
					rig = makeRig(row.userId, row.own, row.roleId, row.level, row.rank)
				end
				local frame = frames[index]
				rig.site = site
				rig.level = row.level
				rig.rank = row.rank
				rig.pivot = frame
				rig.pos = frame.Position
				rig.model:PivotTo(frame)
				if rig.tag then
					rig.tag.Text = tagText(rig.roleId, rig.level, rig.rank)
				end
			end
		end
		setBoard(site, boardAt, #list - slots)
	end
	for site in boards do
		if not bySite[site] then
			setBoard(site, nil, 0)
		end
	end

	-- anyone no longer shown (unhired, left, over the cap, or no site yet)
	for key, rig in rigs do
		if not wanted[key] then
			destroyRig(rig)
		end
	end
	if missing then
		retryAt = os.clock() + RETRY_SECONDS
		dirty = true
	end
end

-- Animation -------------------------------------------------------------------

local ARM_OFFSET = CFrame.new(0, -0.65 * S, 0)

local function animate(rig: Rig, now: number, dt: number, stormy: boolean, tankFraction: number)
	local t = now + rig.seed
	local role = rig.roleId
	local pivot = rig.pivot
	rig.brace += ((if stormy then 1 else 0) - rig.brace) * math.min(1, dt * 3)
	local brace = rig.brace

	-- arm: each role works their instrument; storms brace it up toward the hood
	local armAngle: number
	if role == "Forecaster" then
		armAngle = 0.7 + math.sin(t * 6) * 0.12 -- writing
		if now < rig.pointUntil then
			armAngle = 1.45 + math.sin(t * 9) * 0.05 -- pointing at the forecast
			brace = 0
		end
	elseif role == "RodTech" then
		armAngle = 1 + math.sin(t * 1.7) * 0.3
	elseif role == "Analyst" then
		armAngle = 1.1 + math.abs(math.sin(t * 5)) * 0.2
	elseif role == "Chemist" then
		armAngle = 2.1 + math.sin(t * 1.1) * 0.15
	else
		armAngle = 2.4 + math.sin(t * 0.9) * 0.1
	end
	armAngle += (0.6 - armAngle) * brace * 0.5 + math.sin(t * 25) * 0.04 * brace
	rig.arm.CFrame = pivot * rig.shoulder * CFrame.Angles(armAngle, 0, 0) * ARM_OFFSET

	-- hood goes up in a storm
	rig.hood.CFrame = pivot
		* CFrame.new(0, 0.2 * S * rig.brace, -0.3 * S * rig.brace)
		* rig.hoodBase

	-- instruments crackle cyan in storms
	local crackle = stormy and math.noise(t * 9, rig.seed) > 0.2
	if crackle ~= rig.lit then
		rig.lit = crackle
		rig.inst.Color = if crackle then CYAN else rig.instColor
		rig.inst.Material = if crackle then Enum.Material.Neon else rig.instMaterial
	end

	if role == "Forecaster" then
		rig.inst.CFrame = pivot * rig.instBase * CFrame.Angles(0, 0, math.sin(t * 0.8) * 0.05)
	elseif role == "Chemist" then
		local fillPart = rig.fillPart
		if fillPart then
			local target = if rig.own then tankFraction else 0
			rig.fill += (target - rig.fill) * math.min(1, dt * 4)
			local length = math.max(rig.fillFull * rig.fill, 0.05)
			local size = fillPart.Size
			fillPart.Size = Vector3.new(length, size.Y, size.Z)
			fillPart.CFrame = pivot * CFrame.new(0, -(rig.fillFull - length) / 2, 0) * rig.fillBase
		end
	elseif role == "Analyst" then
		local tape = rig.tape
		if tape then
			local remaining = rig.tapeUntil - now
			local length = rig.tapeSize.Z
			if remaining > 0 then
				-- grows out of the printer, then retracts
				length += math.sin(math.pi * (1 - remaining / TAPE_SECONDS)) * 1.6 * S
			end
			tape.Size = Vector3.new(rig.tapeSize.X, rig.tapeSize.Y, length)
			tape.CFrame = pivot * rig.tapeBase * CFrame.new(0, 0, -(length - rig.tapeSize.Z) / 2)
		end
	elseif role == "StormChaser" then
		local dx = math.sin(t * 0.9) * 0.4 * (1 + rig.brace) * S
		local dy = (math.sin(t * 1.3) * 0.25 + 2.5 * rig.brace) * S
		if now < rig.jerkUntil then
			-- the balloon yanks on its tether just before the bolt
			dy = (-1.2 + math.sin(t * 35) * 0.3) * S
			dx += math.sin(t * 28) * 0.25 * S
		end
		local shift = CFrame.new(dx, dy, 0)
		for index, piece in rig.balloon do
			piece.CFrame = pivot * shift * rig.balloonBase[index]
		end
		local tether = rig.tether
		local first = rig.balloonBase[1]
		if tether and first then
			local bottom = first.Position + Vector3.new(dx, dy - 1.6 * S, 0)
			local length = (bottom - rig.peg).Magnitude
			local size = tether.Size
			tether.Size = Vector3.new(size.X, size.Y, math.max(length, 0.1))
			tether.CFrame = pivot * CFrame.lookAt((rig.peg + bottom) / 2, bottom)
		end
	end
end

local function update(dt: number)
	local now = os.clock()
	if dirty and now >= retryAt then
		layout()
	end
	local camera = workspace.CurrentCamera
	if not camera or #rigList == 0 then
		return
	end
	local camPos = camera.CFrame.Position
	local state = Storm.current
	local stormy = state ~= nil and state.phase == "Storm"

	local snapshot = State.current
	local tankFraction = 0
	local chemist = if snapshot then snapshot.researchers.Chemist else nil
	if snapshot and chemist then
		tankFraction = math.clamp(
			snapshot.tankCount / math.max(ResearchMath.tankCapacity(chemist.level, chemist.rank), 1),
			0,
			1
		)
	end

	for _, rig in rigList do
		local offset = rig.pos - camPos
		if offset:Dot(offset) <= ANIMATE_RANGE_SQ then
			animate(rig, now, dt, stormy, tankFraction)
		end
	end
end

-- Events ----------------------------------------------------------------------

local playerConnections: { [Player]: RBXScriptConnection } = {}

local function watchPlayer(player: Player)
	if playerConnections[player] then
		return
	end
	readPlayer(player)
	playerConnections[player] = player.AttributeChanged:Connect(function(name: string)
		if string.sub(name, 1, 9) == "Research_" then
			readPlayer(player)
		end
	end)
end

local function unwatchPlayer(player: Player)
	local connection = playerConnections[player]
	if connection then
		connection:Disconnect()
		playerConnections[player] = nil
	end
	entries[player] = nil
	dirty = true
end

local function onForecast(_forecast: Types.Forecast)
	local rig = rigs[`{localPlayer.UserId}:Forecaster`]
	if rig then
		rig.pointUntil = os.clock() + 2.5
	end
end

local function onWarning(warning: Types.StrikeWarning)
	if not warning.ownerId then
		return
	end
	local rig = rigs[`{warning.ownerId}:StormChaser`]
	if rig then
		rig.jerkUntil = os.clock() + math.max(0, warning.landsAt - workspace:GetServerTimeNow())
	end
end

local function onLanded(landed: Types.StrikeLanded)
	for _, userId in landed.assayed do
		local rig = rigs[`{userId}:Analyst`]
		if rig then
			rig.tapeUntil = os.clock() + TAPE_SECONDS
		end
	end
end

-- A promotion: your researcher (at their camp or the office) does a little
-- jump.
function Researchers.celebrate(roleId: string)
	local rig = rigs[`{localPlayer.UserId}:{roleId}`]
	if not rig then
		return
	end
	task.spawn(function()
		local base = rig.pivot
		local start = os.clock()
		for _ = 1, 2 do
			repeat
				local t = (os.clock() - start) / 0.45
				rig.pivot = base * CFrame.new(0, math.sin(math.min(t, 1) * math.pi) * 2.4, 0)
				rig.model:PivotTo(rig.pivot)
				RunService.Heartbeat:Wait()
			until t >= 1
			start = os.clock()
		end
		rig.pivot = base
		rig.model:PivotTo(base)
	end)
end

function Researchers.init()
	for index, def in Config.RESEARCHERS do
		roleOrder[def.id] = index
	end
	folder = Instance.new("Folder")
	folder.Name = "Researchers"
	folder.Parent = workspace
end

function Researchers.start()
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(unwatchPlayer)
	Net.get("Forecast").OnClientEvent:Connect(onForecast)
	Net.get("StrikeWarning").OnClientEvent:Connect(onWarning)
	Net.get("StrikeLanded").OnClientEvent:Connect(onLanded)
	RunService.Heartbeat:Connect(update)
	SettingsStore.Changed:Connect(function(key: string, value: any)
		if key == "othersResearchers" then
			dirty = true
		elseif key == "showNameTags" then
			for _, rig in rigs do
				local gui = rig.tag and rig.tag:FindFirstAncestorOfClass("BillboardGui")
				if gui then
					gui.Enabled = value == true
				end
			end
		end
	end)
end

return Researchers
