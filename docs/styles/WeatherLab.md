# WeatherLab: Barometer Bay

A cozy seaside town of storm scientists. The Barometer Bay Weather Society
lives in a little harbour village around a red-and-white lighthouse. Every
field station sits on its own island in a different biome, and a winding
plank boardwalk on stilts leads out to each one. In calm weather it is a
warm late afternoon by the sea: cream cottages, teal shutters, striped
weather balloons and amber lanterns. In a storm the bay turns slate blue,
the sky drops, and the cyan "bottled lightning" glows take over.

What we take from Bee Swarm Simulator (not copied): each catch floor is a
big, perfectly flat field with a bold two-tone pattern you can recognise
from across the map; fields sit at different heights and progression goes
outward and upward round a spiral; the hub is compact and friendly with
chunky signs; colours stay saturated and cheerful even in a storm; shapes
are simple from far away and full of small charm up close.

## Palette (10 colours)

| Token | RGB | Used for |
| --- | --- | --- |
| `beacon` | 214, 69, 58 | Lighthouse red: lighthouse bands, cottage roofs, balloon stripes, buoys, the SELL lettering |
| `sailcloth` | 246, 239, 222 | Cream: plaster walls, lighthouse white bands, research domes, sign boards, umbrellas |
| `driftwood` | 196, 154, 108 | Light wood: boardwalk decks, benches, crates, sign frames, beach huts |
| `piling` | 92, 68, 52 | Dark tarred wood: stilts, posts, beams, rails, door frames |
| `harbor` | 72, 92, 122 | Slate blue: slate roofs, instrument metal, lamp posts, stone plinths, rocks |
| `seafoam` | 86, 190, 176 | Lab teal: shutters, dome ribs, awnings, doors, trims |
| `slicker` | 255, 204, 64 | Raincoat yellow: the SELL pad, wayfinding arrows, hazard stripes, teaser barrier |
| `spark` | 110, 232, 255 | Neon cyan, the "bottled lightning": lighthouse lens, charge tanks, sensor tips, storm glow |
| `kelp` | 104, 164, 84 | Foliage: trees, hedges, beach grass, cacti, planters |
| `ink` | 34, 44, 66 | Navy: text strokes, sign backs, iron fittings, windows, the observatory slit |

Warm lamp light (PointLights, lit windows) is `slicker` warmed toward
`beacon` (255, 178, 100). Each zone's own `Config` colour is its signature:
the glowing border rope, the boardwalk post caps (a light trail from the hub
to the zone), the plaza trail, the fingerpost arm and the gate title.

The ground is part-built (no Terrain): chunky anchored SmoothPlastic blocks
from `World/Blocks`, so colour carries every surface. `Palette.ground`
holds the ground tones, all mixes in the palette's family: warm pale sand
and a deeper beach sand, creamy salt, terracotta sandstone, cream
limestone, a dusty mesa top, kelp grass and a darker meadow, earth,
blue-grey rock and slate, cobble, brick, plank, saturated sea-glass teal
(`64,200,196`) for the beach-towel stripes and a deep teal sea bed. The sea
is one see-through teal sheet (`Palette.water`, 35% transparent).

## Materials

- Plaster (`sailcloth`) walls, ClayRoofTiles (`beacon`) and RoofShingles
  (`harbor`) roofs: the village.
- WoodPlanks decks and Wood posts: boardwalks, jetties, huts, signs.
- SmoothPlastic for painted things (lighthouse bands, domes, balloons,
  buoys); Fabric for awnings, windsocks and umbrellas.
- Metal for instruments (anemometers, radar, telescope); Glass for the
  lantern room, charge tanks and the greenhouse.
- Neon only for light: `spark` cyan electricity, warm window glow and the
  zone-coloured trail caps.
- Ground: SmoothPlastic blocks only (no unions, meshes, decals or textured
  materials): grass and sand caps, two-tone strata bands, sand beach tiers
  with wedge slopes, cobble and cream paving, brick mole, stone slipway,
  rock stacks and `Blocks.rock` boulders.

## Shape language

- Round and chunky: cylinders and balls first (lighthouse, domes, balloons,
  buoys, lanterns, trees). Pitched roofs from wedges. Everything man-made is
  a little hand-built: posts lean slightly, planks alternate in tone,
  nothing is perfectly symmetrical.
- Tall thin verticals mark places (the lighthouse, balloon tethers, the
  observatory spire, the radar mast) against long low horizontals (fields,
  boardwalks, beaches).
- Natural forms are a hand-built diorama: islands are polygon discs
  (7-14 sides) and stepped blocks, never smooth blobs. Every island reads
  in layers from the top down: a lighter cap 1 stud thick that overhangs
  the band below by 0.6, strata bands in two alternating tones that step
  out as they descend, a sand tier just above the water and wedge beach
  slopes (26.6 degrees) down to a sea bed 4 studs under the surface, so
  anyone who falls in wades back out. Lobes (beach bulges, sand spits,
  bluffs, mesa steps) are unioned onto an island at their own height, so
  silhouettes are never a plain block.
- Flat pieces that overlap at one height share one exact colour (no
  per-part jitter) so they never flicker; paving sits 0.1-0.3 over the grass
  and decks 0.2 over the ground they start or land on.
- Three scales of detail: hero landmark per area (seen from spawn),
  mid-size props (huts, lamps, signs, boats, windmills), small details
  (rocks, shells, tufts, flowers, crates, ropes). None of it on the fields.

## Lighting mood

- **Calm (cozy)**: ClockTime 15.6, warm low sun with soft shadows, light
  sea haze, cream cumulus, teal water, gentle bloom so amber lanterns and
  cyan accents glow. Saturation +0.15, warm tint.
- **Storm (dramatic)**: brightness drops to 0.9, slate-indigo ambient, a
  dense blue-grey atmosphere and charcoal-navy clouds; the client tween
  desaturates and cools the `StormGrade`, so the neon cyan lens, tanks and
  zone-coloured ropes become the brightest things on screen.

## Hub: Barometer Bay harbour

- **Hero landmark**: the Barometer Bay lighthouse in the centre of the
  square, red and white bands, a cyan storm lens in a glass lantern room,
  a weather vane and lightning rod on top (~75 studs tall, the landmark
  every field can see).
- **Sell station (the Volt Exchange)**: at the lighthouse door, square to
  the spawn's line of sight. A 24x24 yellow pad in a 2-stud navy frame
  with glowing edges and "SELL" painted on it, a 25-stud striped arch
  whose giant SELL board sits ~30 studs up (it shows over the cottages
  from every boardwalk arch), and two glass charge tanks full of cyan
  lightning wired up the tower to the lens, standing beside the pad.
- **Spawn**: a cream compass deck 52 studs out, facing straight down the
  pad to the lighthouse; the spawn gap has no cottage and its lamp stands
  aside, so nothing blocks the view.
- **Wayfinding**: a fingerpost beside the spawn with one arm per zone (zone
  colour, pointed toward it); a dashed glowing trail in each zone's colour
  set into the cobbles from the lighthouse to that zone's boardwalk; a
  cobbled path through the village ring; a named arch at every boardwalk
  start ("TO SHORELINE"), including the Coming Soon one.
- **Village ring**: cottages with clay or slate roofs, teal shutters, lit
  windows and chimneys; two research domes (observatory and radar); lamp
  posts, benches, planters and round trees. All of it sits between the
  boardwalk directions of every possible future zone, so new zones never
  hit a building.
- **Island**: a grass 14-gon (apothem 69, top at the hub floor) on earth
  and stone bands, a sand ring at 1.2 and wedge beach slopes to the sea
  bed (out to ~88 studs), well short of every zone island, so each
  boardwalk crosses open water. Boardwalks stay flat until they have
  cleared the grass top.
- **Harbour**: an L-shaped brick mole (one step above the sand) that runs
  out from the beach and hooks across the mouth, ending in a teal harbour
  light; a raised plank pier out to deep water with moored boats and a
  crane; a stone slipway from the grass down to the sea bed (the way back
  up for anyone who falls in). Marker buoys out on open water; sea-stack
  islets (a sand 7-gon and a leaning stack of turned blocks with a grass
  cap).
- **Plaza**: a cobbled 12-gon just over the grass with a brick kerb ring
  (no rings inside it, so it never reads as a target from above), a big
  cream market square on the harbour side, a smaller one at the lighthouse
  foot, and a small cream square beside every boardwalk exit where the
  tapered cream spoke ends.

## Zones

Every zone island is generic (any slot position, rotation, size, height):
- **Plateau** (`Land.plateau`, all slot-relative): the footprint plus the
  theme margins is one flat top at the floor: the catch floor blocks in
  the middle and a cap round them, laid edge to edge with no overlaps. Under
  it, rectangular strata (`Blocks.strataBox`) step out band by band down
  to the sea bed; the front (hub side) drops straight into the sea, so the
  boardwalk arrives over open water.
- **Beach tier**: a rounded rectangle (12-gon) of sand round the plateau's
  sides and back, just above the water, with wedge slopes to the sea bed
  on every edge that faces open water. Themes can add a ramp from the beach
  up the cliff (`island.ramp`) and union lobes, bluffs, mesa steps and
  stacks onto it (`theme.ground`), each checked with `Geo.clearOf` so
  neighbouring islands never merge.
- **Catch floor**: 1-stud blocks with their tops exactly at the floor,
  laid in a bold two-tone pattern (stripes or a checker, optional cream
  piping) inside a contrasting trim band, framed by a raised 3-stud plank
  kerb (open at the gate). Nothing stands on it.
- **Border**: posts on the kerb every ~10 studs, each with a glowing cap in
  the zone colour; one glowing rope spans two gaps (resting over the middle
  post) to halve the Beam count; striped corner poles in the zone colour
  with windsocks.
- **Gate**: two striped lighthouse-style posts and a beam with the zone's
  name and tagline facing the boardwalk ("BACK TO THE HARBOUR" on the
  back), lanterns, a windsock, and a value plaque.
- **Connector**: a winding plank boardwalk on stilts over the water, flat
  at both ends, a rest platform with a bench on long ones, rope rails with
  zone-coloured glowing caps and amber lanterns.

| Theme | Field pattern | Hero landmark (outside the field) | Edge dressing |
| --- | --- | --- | --- |
| `Beach` | Sand / sea-glass teal beach-towel stripes 12 studs wide with cream piping, plank trim and kerb | A giant red-and-white striped weather balloon on tethers above a launch deck | low sand plateau one step above a wide beach that bulges out on the long side and the back, a grassy rock bluff on the back corner, a sand spit stepping down off the other, sea stacks; props in vignettes with open sand between: a cabana row of three huts with surfboards, the tide-watch tower with its umbrella-and-deck-chair cluster, two palm groves, the plank pier on stilts over the beach out to open water (T-head, lamp, tide gauge, tied rowboat, sea spray), a rowboat pulled up on the beach; buoys, rocks, shells, driftwood |
| `Canyon` | Sandstone / limestone checkerboard (5 x 5), brick trim, dusty mesa top | The Anvil Observatory: a white dome with a telescope on a banded stone spire | sandstone / limestone strata, rotated lower mesa steps, a headland, a tall stepped butte, hoodoo stacks in the shallows, a sand bar, a trail ramp up the cliff, a wooden water tower, a farm windmill, adobe weather huts, windsocks, cacti, tumbleweeds, rocks |
| `Default` | Rotates by spiral slot so fallback zones never match: grass/limestone stripes with brick trim, grass/salt checker with plank trim, grass/earth cross stripes with cream trim, sand/grass checker with slate trim; set in a rough meadow cap | A radar mast with a big white radome and a red beacon | earth and rock strata, a grassy hill on a back corner, a rocky point, a ramp up the cliff, mossy boulders, a greenhouse, an instrument shelter, hay bales, round trees, flowers, rocks |

## Teaser (Coming Soon)

A misty rocky island in the next slot: a grass-topped 11-gon on tall
grey cliff bands with a sand skirt, two lower rock horns with stacks
round a bay at the back and a sea stack off the front. Only a site is marked out on top: survey pegs with orange flags
and yellow caution tape and just two half-ploughed stripes, so it reads
as "not built yet". A survey camp (tent, crates, scaffold with a work
light), a grey balloon with a big neon yellow "?" facing the hub, and a
wide slow mist emitter (rate 4).
The boardwalk to it stops half-way: bare stilts stick out of the water
past a striped barrier, caution rope, and a big "COMING SOON" board.

## Stacking and budget

- A new zone needs only its `Config.ZONES` entry (and a theme module for a
  new look; unknown themes use `Default`). The spiral (first ring 178 studs, 135 degrees, +38
  studs per slot) places it; its island shape, channel to its
  neighbours, hub bay, boardwalk, border, gate, sign and light trail all
  follow from the slot.
- Part budget (`Geo.markHub/allowance/room`): the hub (with its ground)
  is counted before the first zone, the teaser keeps a 290-part reserve
  and every zone gets an equal share of a 2,450-part cap for its ground
  (`Map.Ground/<id>`, counted too), island art, border, gate and
  boardwalk. Themes build their hero landmark first and ask `Geo.room`
  before each optional piece (huts, pier, tower, greenhouse, every
  scattered prop), so the first zones are fully dressed while a 7-zone
  world gets a lighter dressing. `Geo.detail` additionally thins props,
  widens border spacing, uses longer deck segments and sparser rail
  posts, stilts, lamps and trail dashes on long boardwalks, and drops a
  hub tree per gap. Only the first lamp on each boardwalk, the hub lamps,
  the gate lamps and a few key lights cast real light.
- Measured with the harness: 2 zones 2,345 parts (457 of them ground:
  hub 140, Shoreline 129, Mesa 118, teaser 69, sea bed 1) / 140 beams /
  25 lights. Each extra zone adds roughly 80-120 ground parts on top of
  its border, gate and boardwalk, so past five or six zones turn on
  StreamingEnabled and raise the part cap (`PART_CAP` in `Geo.luau`).
- Props find real ground with `Geo.heightAt` / `Geo.groundAt` (Land
  remembers every flat top it lays: polygons, rectangles, ledges) and
  open water with `Geo.seaward` (which steps on past the beach slopes), so
  buoys, boats and rocks sit on the block coast.

## Proposed names (ids unchanged)

| Id | Display name | Tagline |
| --- | --- | --- |
| `Shoreline` | Tidewatch Beach | Everyone in the circle catches |
| `Mesa` | Anvil Mesa | One catcher per bolt - 4x Volts |
| (future) | Meadow Station | (Default theme) |

The gates and signs print `Config.ZONES[id].displayName` and `tagline`, so
renaming a zone in Config renames it everywhere.

## Revision notes (review round 2)

- Block ground (round 3): Terrain is gone. Islands, plateaus, beaches, paving and the sea are SmoothPlastic parts (`Land.luau` on `World/Blocks`); the style sets `ground = "Blocks"`. The Shoreline stripes are now the catch floor blocks themselves.
- Mesa gets a tall stepped butte behind the field (top at floor + 26); it and every other landform are skipped by `Geo.clearOf` if a future zone, the teaser or the hub would be too close.
- Teaser: the deck runs 70% of the way, ending at tall caution-striped gate posts with a lit neon crossbar; the "?" balloon floats at y >= 68, above the lighthouse lens.
