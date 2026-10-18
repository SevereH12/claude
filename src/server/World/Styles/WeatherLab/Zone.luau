--!strict
-- Generic zone pieces for WeatherLab, used by every zone whatever its
-- slot, size or theme: the block island (field plateau, strata and beach
-- from Land, then the theme's landforms), the winding boardwalk from the
-- hub, the glowing rope border and the lighthouse-post gate. Themes only
-- add biome landforms and dressing on top.

local ServerScriptService = game:GetService("ServerScriptService")

local Blocks = require(ServerScriptService.Server.World.Blocks)
local Kit = require(ServerScriptService.Server.World.Kit)
local Geo = require(script.Parent.Geo)
local Land = require(script.Parent.Land)
local Palette = require(script.Parent.Palette)
local Pieces = require(script.Parent.Pieces)
local Themes = require(script.Parent.Themes)
local WLTypes = require(script.Parent.WLTypes)

type Context = WLTypes.Context
type ZoneContext = WLTypes.ZoneContext

local C = Palette.colors

local Zone = {}

Zone.DECK_WIDTH = 10
-- Decks ride this far over the ground they start and land on, so plank
-- and grass tops never share a height.
local LIFT = 0.2

-- Ground --------------------------------------------------------------------------

function Zone.ground(ctx: Context, zone: ZoneContext)
	local def = zone.def
	local theme = Themes.get(if def then def.theme else "Default")
	local look = if theme.fieldFor then theme.fieldFor(zone) else theme.field
	Land.plateau(ctx, zone, theme.margins, theme.island, look)
	theme.ground(ctx, zone)
end

-- Boardwalk -------------------------------------------------------------------------

export type WalkOptions = {
	color: Color3, -- trail colour: post caps, arch, plaza dashes
	title: string, -- hub arch sign
	subtitle: string?,
	landing: number, -- flat studs at the far end (over the island rim)
	stopAt: number?, -- teaser: fraction of the length where the deck ends
}

type Profile = {
	length: number,
	startFlat: number,
	at: (s: number) -> Vector3, -- point on the walking surface
	tangent: (s: number) -> Vector3, -- horizontal direction of travel
	platform: { from: number, to: number }?,
	breaks: { number },
}

-- Plans the walkway from `from` to `to`: flat at both ends (at the hub
-- end until it has cleared the hub's grass top), an S-bend in the middle
-- and (on long runs) a flat rest platform half way.
local function profile(from: Vector3, to: Vector3, landing: number, flat: number): Profile
	local flatDelta = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local length = flatDelta.Magnitude
	local dir = flatDelta.Unit
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local startFlat = math.min(flat, length * 0.3)
	local endFlat = math.min(landing, length * 0.3)
	local rampLength = length - startFlat - endFlat
	local platform: { from: number, to: number }? = nil
	local platformLength = 12
	if rampLength >= 46 then
		local mid = startFlat + rampLength * 0.5
		platform = { from = mid - platformLength / 2, to = mid + platformLength / 2 }
	end
	local climb = rampLength - (if platform then platformLength else 0)
	local amplitude = math.clamp((length - 30) * 0.08, 0, 7)

	local function height(s: number): number
		local ramped = s - startFlat
		if platform then
			if s >= platform.to then
				ramped -= platformLength
			elseif s > platform.from then
				ramped = platform.from - startFlat
			end
		end
		local t = math.clamp(ramped / math.max(climb, 0.001), 0, 1)
		return from.Y + (to.Y - from.Y) * t
	end
	local function offset(s: number): number
		local u = s / length
		return amplitude * math.sin(2 * math.pi * u) * math.sin(math.pi * u) / 0.77
	end
	local function at(s: number): Vector3
		local base = from + dir * s + right * offset(s)
		return Vector3.new(base.X, height(s), base.Z)
	end
	local function tangent(s: number): Vector3
		local a = at(math.max(s - 0.5, 0))
		local b = at(math.min(s + 0.5, length))
		return Pieces.flatUnit(b - a)
	end
	local breaks = { 0, startFlat, length - endFlat, length }
	if platform then
		table.insert(breaks, platform.from)
		table.insert(breaks, platform.to)
	end
	return {
		length = length,
		startFlat = startFlat,
		at = at,
		tangent = tangent,
		platform = platform,
		breaks = breaks,
	}
end

-- Sample distances along the walk: every ~7 studs plus every profile break.
-- Longer walks (and busier worlds, via the detail budget) use longer
-- deck segments and sparser posts, stilts and lamps.
local function segmentLength(length: number, detail: number): number
	local seg = if length < 110 then 7 else math.min(12, 7 + (length - 110) / 25)
	return if detail < 1 then math.max(seg, 11) else seg
end

local function samples(p: Profile, limit: number, detail: number): { number }
	local list = table.clone(p.breaks)
	local n = math.max(1, math.ceil(p.length / segmentLength(p.length, detail)))
	for i = 1, n - 1 do
		table.insert(list, p.length * i / n)
	end
	table.sort(list)
	local out = {}
	for _, s in list do
		if s <= limit + 0.01 and (#out == 0 or s - out[#out] > 2.5) then
			table.insert(out, s)
		end
	end
	if out[#out] < limit - 0.5 then
		table.insert(out, limit)
	end
	return out
end

-- A rail post with a glowing cap in the trail colour. Returns the rope point.
local function railPost(parent: Instance, bottom: Vector3, color: Color3, cap: boolean?): Vector3
	Pieces.box(
		parent,
		CFrame.new(bottom + Vector3.new(0, 1.6, 0)),
		Vector3.new(0.5, 3.2, 0.5),
		C.piling,
		Enum.Material.Wood
	)
	if cap ~= false then
		Pieces.glow(Pieces.ball(parent, bottom + Vector3.new(0, 3.45, 0), 0.8, color), color)
	end
	return bottom + Vector3.new(0, 2.7, 0)
end

local function rope(ctx: Context, a: Vector3, b: Vector3)
	Kit.cable(ctx, a, b, { Color = Palette.sand, Width = 0.16, CurveSize = 0.5 })
end

-- Arch over the start of a boardwalk with the destination's name.
local function hubArch(parent: Instance, at: Vector3, dir: Vector3, opts: WalkOptions)
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local half = Zone.DECK_WIDTH / 2 + 1
	local tops = {}
	for _, side in { -1, 1 } do
		local bottom = at + right * side * half
		-- posts stand on the grass beside the (lifted) deck
		local post = bottom + Vector3.new(0, 4.5 - LIFT / 2, 0)
		Pieces.box(
			parent,
			CFrame.lookAt(post, post + dir),
			Vector3.new(0.9, 9 + LIFT, 0.9),
			C.piling,
			Enum.Material.Wood
		)
		Pieces.glow(Pieces.ball(parent, bottom + Vector3.new(0, 9.3, 0), 1, opts.color), opts.color)
		table.insert(tops, bottom + Vector3.new(0, 8.4, 0))
	end
	local mid = (tops[1] + tops[2]) / 2
	Pieces.box(
		parent,
		CFrame.lookAt(mid, mid + dir),
		Vector3.new(half * 2 + 1.4, 0.7, 0.7),
		C.piling,
		Enum.Material.Wood,
		false
	)
	local boardCf = CFrame.lookAt(mid - Vector3.new(0, 1.6, 0), mid - Vector3.new(0, 1.6, 0) - dir)
	local board = Kit.sign(
		parent,
		boardCf,
		half * 2 - 0.6,
		2.4,
		opts.title,
		opts.subtitle,
		Palette.zoneSign(opts.color)
	)
	Kit.faceText(board, Enum.NormalId.Back, opts.title, nil, Palette.zoneSign(opts.color))
	Pieces.lantern(parent, mid - Vector3.new(0, 3.6, 0) + right * (half - 1.2), nil, 16)
end

-- Builds a winding plank boardwalk on stilts from `from` to `to`. Returns
-- the profile so callers can add things along it.
function Zone.boardwalk(
	ctx: Context,
	parent: Instance,
	from: Vector3,
	to: Vector3,
	opts: WalkOptions
)
	local rng = ctx.rng
	local up = Vector3.new(0, LIFT, 0)
	local p = profile(from + up, to + up, opts.landing, Land.hubEdge() - ctx.layout.hubRadius + 1.5)
	local limit = if opts.stopAt then p.length * opts.stopAt else p.length
	local detail = Geo.detail(ctx)
	local list = samples(p, limit, detail)
	local width = Zone.DECK_WIDTH
	local platform = p.platform
	local function onPlatform(s: number): boolean
		return platform ~= nil and s > platform.from + 0.1 and s < platform.to - 0.1
	end
	local function inPlatformSpan(a: number, b: number): boolean
		return platform ~= nil and a >= platform.from - 0.1 and b <= platform.to + 0.1
	end

	hubArch(parent, p.at(1.2), p.tangent(1.2), opts)

	-- deck segments
	local deckColors = { C.driftwood, Palette.plankLight, Palette.plankDark }
	for i = 1, #list - 1 do
		local a, b = list[i], list[i + 1]
		if not inPlatformSpan(a, b) then
			local pa, pb = p.at(a), p.at(b)
			local along = (pb - pa).Unit
			local lift = if i % 2 == 0 then Vector3.new(0, 0.03, 0) else Vector3.zero
			Kit.walkway(parent, pa - along * 0.45 + lift, pb + along * 0.45 + lift, width, 1, {
				Name = "Boardwalk",
				Color = deckColors[rng:NextInteger(1, #deckColors)],
				Material = Enum.Material.WoodPlanks,
			})
		end
	end

	-- rest platform: a wider deck with corner posts, a bench and a lantern
	if platform and platform.to <= limit then
		local a, b = p.at(platform.from), p.at(platform.to)
		local dir = Pieces.flatUnit(b - a)
		local right = Vector3.new(-dir.Z, 0, dir.X)
		local wide = width + 8
		Kit.walkway(parent, a - dir * 0.3, b + dir * 0.3, wide, 1.2, {
			Name = "RestPlatform",
			Color = Palette.plankLight,
			Material = Enum.Material.WoodPlanks,
		})
		local corners = {}
		for _, side in { -1, 1 } do
			for _, q in { a, b } do
				local c = q + right * side * (wide / 2 - 0.4) + dir * (if q == a then 0.4 else -0.4)
				table.insert(corners, railPost(parent, c, opts.color))
			end
			Kit.cable(ctx, corners[#corners - 1], corners[#corners], {
				Color = Palette.sand,
				Width = 0.16,
				CurveSize = 0.6,
			})
		end
		local mid = (a + b) / 2
		local benchSide = if rng:NextNumber() < 0.5 then -1 else 1
		Pieces.bench(
			parent,
			CFrame.lookAt(mid + right * benchSide * (wide / 2 - 2), mid + right * benchSide * wide)
		)
		Pieces.lampPost(
			parent,
			mid - right * benchSide * (wide / 2 - 1) - dir * 3,
			6,
			right * benchSide
		)
		Pieces.barrel(parent, mid - right * benchSide * (wide / 2 - 1.6) + dir * 3)
	end

	-- rail posts, ropes, stilts and lanterns at each sample
	local last: { [number]: Vector3 } = {}
	local stiltEvery = if p.length < 110 then 2 elseif detail < 1 then 4 else 3
	local postEvery = if detail < 1 and p.length >= 110 then 4 else 2
	local lampGap = if p.length < 110 then 30 elseif detail < 1 then 90 else 60
	local postCount = 0
	local litLanterns = 0
	local nextLantern = 24
	local lanternSide = 1
	for i, s in list do
		local point = p.at(s)
		local dir = p.tangent(s)
		local right = Vector3.new(-dir.Z, 0, dir.X)
		local endpoint = i == 1 or (i == #list and not opts.stopAt)
		if
			onPlatform(s)
			or (platform and (math.abs(s - platform.from) < 0.2 or math.abs(s - platform.to) < 0.2))
		then
			last = {}
		elseif not endpoint and (i % postEvery == 1 or i == #list) then
			postCount += 1
			for _, side in { -1, 1 } do
				local bottom = point + right * side * (width / 2 - 0.3)
				local ropePoint
				if s >= nextLantern and side == lanternSide and s < p.length - 10 then
					nextLantern = s + lampGap
					lanternSide = -lanternSide
					-- only the first lamp on each walk casts real light
					Pieces.lampPost(parent, bottom, 5.5, -right * side, litLanterns == 0)
					litLanterns += 1
					ropePoint = bottom + Vector3.new(0, 2.7, 0)
				else
					ropePoint = railPost(parent, bottom, opts.color, postCount % 2 == 1)
				end
				local previous = last[side]
				if previous then
					rope(ctx, previous, ropePoint)
				end
				last[side] = ropePoint
			end
		end
		-- stilts every other sample where the deck is over water
		if
			i % stiltEvery == 0
			and s > p.startFlat
			and s < p.length - opts.landing + 4
			and not onPlatform(s)
		then
			local tops = {}
			for _, side in { -1, 1 } do
				local top = point + right * side * (width / 2 - 0.8) - Vector3.new(0, 1, 0)
				Pieces.cyl(
					parent,
					Vector3.new(top.X, -8, top.Z),
					top.Y + 8,
					1.1,
					C.piling,
					Enum.Material.Wood,
					false
				)
				table.insert(tops, top - Vector3.new(0, 0.7, 0))
			end
			Pieces.beam(parent, tops[1], tops[2], 0.5, C.piling)
		end
	end
	-- stilts under the rest platform corners
	if platform and platform.to <= limit then
		local a, b = p.at(platform.from), p.at(platform.to)
		local dir = Pieces.flatUnit(b - a)
		local right = Vector3.new(-dir.Z, 0, dir.X)
		for _, q in { a, b } do
			for _, side in { -1, 1 } do
				local top = q + right * side * (width / 2 + 3) - Vector3.new(0, 1.2, 0)
				Pieces.cyl(
					parent,
					Vector3.new(top.X, -8, top.Z),
					top.Y + 8,
					1.3,
					C.piling,
					Enum.Material.Wood,
					false
				)
			end
		end
	end
	return p, list
end

-- Plaza trail and cobbled path from the lighthouse to a hub exit: paving
-- blocks just over the plaza and grass (in Map.Ground/<key>), with
-- glowing dashes set into them.
function Zone.trail(ctx: Context, parent: Instance, angle: number, color: Color3, key: string)
	local layout = ctx.layout
	local dir = Vector3.new(math.sin(angle), 0, -math.cos(angle))
	local floor = layout.hubFloor
	local ground = Land.folder(ctx, key)
	local G = Palette.ground
	local function strip(r0: number, r1: number, width: number, lift: number, tone: Color3)
		local from, to = dir * r0, dir * r1
		local mid = (from + to) / 2
		local y = floor + lift - 0.3
		Blocks.box(
			ground,
			tone,
			CFrame.lookAt(Vector3.new(mid.X, y, mid.Z), Vector3.new(to.X, y, to.Z)),
			Vector3.new(width, 0.6, (to - from).Magnitude),
			{ Color = tone, Name = "Path" }
		)
	end
	-- a cream spoke across the plaza that tapers toward the lighthouse and
	-- ends in the flagstone square by the exit (Hub), then a cobbled path
	-- with a brick edging through the village to the boardwalk
	strip(24, 34, 3, 0.3, G.limestone)
	strip(34, 46, 5, 0.3, G.limestone)
	strip(46, layout.hubRadius - 0.5, 10, 0.2, G.cobble)
	strip(46, layout.hubRadius - 0.5, 11.6, 0.1, G.brick)
	-- glowing dashes set into the paving
	local r = 15
	while r < layout.hubRadius - 2 do
		local p = dir * r + Vector3.new(0, floor + 0.26, 0)
		local dash = Pieces.box(
			parent,
			CFrame.lookAt(p, p + dir),
			Vector3.new(1.3, 0.3, 2.6),
			color,
			nil,
			false
		)
		Pieces.glow(dash, color)
		r += if Geo.detail(ctx) < 1 then 9 else 5.5
	end
end

function Zone.connector(ctx: Context, zone: ZoneContext)
	local def = zone.def :: any
	local slot = zone.slot
	local theme = Themes.get(def.theme)
	local parent = Instance.new("Folder")
	parent.Name = def.id
	parent.Parent = ctx.folders.connectors
	Zone.trail(ctx, parent, slot.angle, zone.color, Geo.key(zone))
	Zone.boardwalk(ctx, parent, slot.hubExit.Position, slot.gate.Position, {
		color = zone.color,
		title = string.upper(def.displayName),
		subtitle = `{def.chargeValue} VOLTS PER BOLT`,
		landing = theme.margins.front + 4,
	})
end

-- Border ------------------------------------------------------------------------------

function Zone.border(ctx: Context, zone: ZoneContext)
	local def = zone.def :: any
	local look = Themes.get(def.theme).border
	local slot = zone.slot
	local hw, hd = slot.width / 2, slot.depth / 2
	local inset = -1.4
	local gapHalf = Zone.DECK_WIDTH / 2 + 3.5
	local folder = zone.folder
	type Post = { top: Vector3?, corner: boolean }
	local posts: { Post } = {}
	-- a raised 3-stud plank kerb frames the field just outside the
	-- footprint (open at the gate), so every field reads as a bounded tile
	local kerbW, kerbH = 2.8, 0.9
	local kerbColor = look.postColor:Lerp(C.driftwood, 0.5)
	local function kerb(x0: number, x1: number, z0: number, z1: number)
		Pieces.box(
			folder,
			Geo.cf(zone, (x0 + x1) / 2, (z0 + z1) / 2, kerbH / 2 - 0.2),
			Vector3.new(x1 - x0, kerbH + 0.4, z1 - z0),
			kerbColor,
			Enum.Material.WoodPlanks
		)
	end
	local ox, oz = hw + 0.2, hd + 0.2
	kerb(-ox - kerbW, ox + kerbW, oz, oz + kerbW)
	kerb(-ox - kerbW, -ox, -oz, oz)
	kerb(ox, ox + kerbW, -oz, oz)
	kerb(-ox - kerbW, -gapHalf, -oz - kerbW, -oz)
	kerb(gapHalf, ox + kerbW, -oz - kerbW, -oz)
	local spacing = math.min(10 / Geo.detail(ctx), 22)
	for _, cf in Kit.perimeter(zone, spacing, inset) do
		local l = Geo.toLocal(zone, cf.Position)
		local corner = math.abs(math.abs(l.X) - (hw - inset)) < 0.5
			and math.abs(math.abs(l.Z) - (hd - inset)) < 0.5
		local inGate = l.Z < -hd and math.abs(l.X) < gapHalf
		local bottom = cf.Position + Vector3.new(0, kerbH - 0.2, 0)
		if inGate then
			table.insert(posts, { top = nil, corner = false })
		elseif corner then
			local full = Geo.detail(ctx) >= 1
			local top = Pieces.stripedPole(
				folder,
				bottom,
				9,
				1,
				{ zone.color, C.sailcloth },
				if full then 5 else 2
			)
			if full or l.Z > 0 then
				Pieces.windsock(folder, top - Vector3.new(0, 0.6, 0), zone.color, 4.5)
			end
			Pieces.glow(
				Pieces.ball(folder, top + Vector3.new(0, 0.4, 0), 1, zone.color),
				zone.color
			)
			table.insert(
				posts,
				{ top = bottom + Vector3.new(0, look.postHeight - 0.4, 0), corner = true }
			)
		else
			if look.stones then
				Pieces.box(
					folder,
					CFrame.new(bottom + Vector3.new(0, 0.3, 0))
						* CFrame.Angles(0.2, ctx.rng:NextNumber(0, 6), 0.15),
					Vector3.new(2, 1.2, 1.7),
					Palette.stone,
					Enum.Material.Slate
				)
			end
			Pieces.cyl(
				folder,
				bottom,
				look.postHeight,
				look.postDiameter,
				look.postColor,
				look.postMaterial
			)
			Pieces.glow(
				Pieces.ball(
					folder,
					bottom + Vector3.new(0, look.postHeight + 0.3, 0),
					look.postDiameter + 0.3,
					zone.color
				),
				zone.color
			)
			table.insert(
				posts,
				{ top = bottom + Vector3.new(0, look.postHeight - 0.4, 0), corner = false }
			)
		end
	end
	-- one rope spans two post gaps (it rests over the middle post), which
	-- halves the Beam count; corners always anchor a rope end
	local i = 1
	while i <= #posts do
		local post = posts[i]
		local step = 2
		local mid = posts[i % #posts + 1]
		if not mid.top or mid.corner or i == #posts then
			step = 1
		end
		local nextPost = posts[(i + step - 1) % #posts + 1]
		i += step
		if post.top and nextPost.top then
			Kit.cable(ctx, post.top :: Vector3, nextPost.top :: Vector3, {
				Color = zone.color,
				Width = 0.24,
				CurveSize = 0.7,
				LightEmission = 0.7,
			})
		end
	end
end

-- Gate ----------------------------------------------------------------------------------

function Zone.gate(ctx: Context, zone: ZoneContext)
	local def = zone.def :: any
	local folder = zone.folder
	local hd = zone.slot.depth / 2
	local z = -hd - 1.8
	local postX = Zone.DECK_WIDTH / 2 + 2.2
	for _, side in { -1, 1 } do
		local bottom = Geo.at(zone, side * postX, z, 0)
		Pieces.cyl(folder, bottom, 1.2, 3.2, Palette.stone, Enum.Material.Cobblestone)
		local top = Pieces.stripedPole(
			folder,
			bottom + Vector3.new(0, 1.2, 0),
			11,
			2,
			{ C.beacon, C.sailcloth },
			if Geo.detail(ctx) < 1 then 3 else 5
		)
		Pieces.cyl(folder, top, 0.4, 2.8, C.ink, Enum.Material.Metal)
		local lamp = Pieces.glow(
			Pieces.ball(folder, top + Vector3.new(0, 1.3, 0), 1.3, zone.color),
			zone.color
		)
		Kit.light(lamp, zone.color, 20, 1.5)
		local glass = Pieces.cyl(
			folder,
			top + Vector3.new(0, 0.4, 0),
			1.8,
			2,
			C.sailcloth,
			Enum.Material.Glass,
			false
		)
		glass.Transparency = 0.6
		Pieces.cyl(
			folder,
			top + Vector3.new(0, 2.2, 0),
			0.5,
			2.6,
			C.beacon,
			Enum.Material.SmoothPlastic,
			false
		)
		Pieces.ball(
			folder,
			top + Vector3.new(0, 2.8, 0),
			0.8,
			C.beacon,
			Enum.Material.SmoothPlastic,
			false
		)
	end
	Pieces.box(
		folder,
		Geo.cf(zone, 0, z, 11.6),
		Vector3.new(postX * 2 + 1.6, 0.9, 0.9),
		C.piling,
		Enum.Material.Wood,
		false
	)
	local style = Palette.zoneSign(zone.color)
	Pieces.signBoard(
		folder,
		Geo.cf(zone, 0, z, 9.3),
		postX * 2 - 1.4,
		3.2,
		string.upper(def.displayName),
		def.tagline,
		style,
		nil,
		{ title = "BACK TO HARBOUR", subtitle = "Sell your bottles at the lighthouse" }
	)
	for _, side in { -1, 1 } do
		Kit.cable(
			ctx,
			Geo.at(zone, side * (postX - 1.5), z, 11.2),
			Geo.at(zone, side * (postX - 1.5), z, 10.9),
			{
				Color = C.ink,
				Width = 0.15,
			}
		)
	end
	Pieces.weatherVane(folder, Geo.at(zone, 0, z, 12.05), 1.2)
	-- value plaque on the left post
	Pieces.signBoard(
		folder,
		Geo.cf(zone, -postX - 2.4, z - 0.4, 3.4),
		3.6,
		2,
		`{def.chargeValue} VOLTS`,
		"per bolt",
		Palette.SIGN,
		zone.slot.floor
	)
end

return Zone
