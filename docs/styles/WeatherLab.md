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

Terrain colours are tuned to the palette with `Terrain:SetMaterialColor`
(warm pale Sand, creamy Salt, sea-glass teal Mud for the "wet sand"
beach-towel stripes, terracotta Sandstone, cream Limestone, kelp Grass,
blue-grey Slate) and the sea is a clear teal. (The harness renderer draws
fixed material colours, so Shoreline's teal Mud stripes show dark brown
there; in Studio they are teal.)

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
- Terrain: Sand beaches and shallows, teal Mud beach-towel stripes, Sandstone /
  Limestone / Rock mesa strata, Grass and LeafyGrass meadows, Cobblestone
  plaza with Brick edging, Brick quay walls, Slate and Rock outcrops, Water.

## Shape language

- Round and chunky: cylinders and balls first (lighthouse, domes, balloons,
  buoys, lanterns, trees). Pitched roofs from wedges. Everything man-made is
  a little hand-built: posts lean slightly, planks alternate in tone,
  nothing is perfectly symmetrical.
- Tall thin verticals mark places (the lighthouse, balloon tethers, the
  observatory spire, the radar mast) against long low horizontals (fields,
  boardwalks, beaches).
- Natural forms are never rectangles or circles. Every island is a stack
  of terraces drawn like contour lines on a map: one smooth random wobble
  per island (2-8 lobes) is shared by all its layers, so headlands, coves
  and sand spits line up from the plateau down through beach and shallows.
  Where the beach swings back to nothing the plateau drops straight into
  the sea (a cove); where it swings out it becomes a spit or headland.
  Small coves are bitten into the gate side away from the boardwalk.
- Terrace edges get a traced band: cream limestone cap rock on the mesa,
  a broken dune-grass fringe on the beach, mossy stones on the meadow.
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
- **Coast**: terraced grass bank, sand beach, shallows, all following one
  shared wobble. The coast dips into a little bay wherever a boardwalk
  leaves and stops well short of every zone island, so each boardwalk
  crosses open water. The harbour is a basin bitten out of the coast (a
  `Geo.bite`, so the land is never built there) with an L-shaped brick
  mole that follows the shore and hooks across the mouth, ending in a
  teal harbour light; a jetty with moored boats and a crane. Marker buoys
  out on real open water; sea-stack islets built from leaning, offset
  drums and wedge faces (never a stack of coins).
- **Plaza**: an irregular cobbled square (no rings): wider toward the
  harbour and the spawn, with a broken brick kerb, a big cream market
  square on the harbour side, a smaller one at the lighthouse foot, and a
  small cream square beside every boardwalk exit where the tapered cream
  spoke ends.

## Zones

Every zone island is generic (any slot position, rotation, size, height):
- **Ground**: contour-nested terraces around the footprint (shallows,
  beach, theme cliff bands, the top), flat at the floor height across the
  footprint plus a rim for props. The top terrace only ever bulges
  outward, so props on the rim always stand on land. Islands keep out of
  a circle round the hub, and land above water stays nearer its own
  footprint than any neighbour's, so islands never merge, however many
  zones are added.
- **Ground shape**: coves are `Geo.bite` circles cut from every land
  layer (always leaving a 7-stud strip round the footprint); each terrace
  mixes the island's shared wobble with its own so headlands don't line
  up; Canyon cliffs get wedge-faced scree (`Geo.talus`) and a broken
  cap-rock lip of mixed sizes.
- **Catch floor**: flat terrain painted in a bold two-tone pattern with a
  contrasting trim around the field edge, framed by a raised 3-stud plank
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
| `Beach` | Sand / sea-glass teal (Mud) beach-towel stripes 12 studs wide, plank trim and kerb | A giant red-and-white striped weather balloon on tethers above a launch deck | island with a NE rock headland, a long curving sand spit, a cove and a sandstone dune bluff behind the field; props in vignettes with open sand between: a cabana row of three huts with surfboards, the tide-watch tower with its umbrella-and-deck-chair cluster, two palm groves, the plank pier out to open water (T-head, lamp, tide gauge, tied rowboat, sea spray), a lagoon; buoys, rocks, shells, driftwood |
| `Canyon` | Sandstone / Limestone checkerboard, brick trim | The Anvil Observatory: a white dome with a telescope on a striped rock spire | cream cap-rock lip, layered cliff bands and hoodoos, a wooden water tower, a farm windmill, adobe weather huts, dry-scrub and rock-pavement patches, windsocks, cacti, tumbleweeds, rocks |
| `Default` | Rotates by spiral slot so fallback zones never match: Grass/Limestone stripes with brick trim, LeafyGrass/Salt checker with plank trim, Grass/Ground cross stripes with cream trim, Sand/Grass checker with slate trim; set in rough LeafyGrass meadow | A radar mast with a big white radome and a red beacon | grass banks with mossy stones on the edge, a greenhouse, an instrument shelter, hay bales, round trees, flowers, rocks |

## Teaser (Coming Soon)

A misty rocky crescent (a wide bay bitten out of the back) in the next
slot. Only a site is marked out on top: survey pegs with orange flags
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
- Part budget (`Geo.markHub/allowance/room`): the hub is counted before
  the first zone, the teaser keeps a 200-part reserve and every zone gets
  an equal share of a 2,400-part cap for its island art, border, gate and
  boardwalk. Themes build their hero landmark first and ask `Geo.room`
  before each optional piece (huts, pier, tower, greenhouse, every
  scattered prop), so the first zones are fully dressed while a 7-zone
  world gets a lighter dressing. `Geo.detail` additionally thins props,
  widens border spacing, uses longer deck segments and sparser rail
  posts, stilts, lamps and trail dashes on long boardwalks, and drops a
  hub tree per gap. Only the first lamp on each boardwalk, the hub lamps,
  the gate lamps and a few key lights cast real light.
- Measured with the harness (extra zones 100x110, floors +8 each):
  2 zones 1,873 parts / 134 beams / 24 lights; 4 zones ~2,060 / 145 / 32;
  7 zones ~2,470 / 229 / 44 (all gameplay and walk checks pass);
  8 zones ~2,580, so past seven zones turn on StreamingEnabled and raise
  the part cap (`PART_CAP` in `Geo.luau`).
- Props find real ground with `Geo.heightAt` / `Geo.groundAt` (every
  terrace outline is remembered on the build context) and open water
  with `Geo.seaward`, so buoys, boats and rocks follow the organic coast.

## Proposed names (ids unchanged)

| Id | Display name | Tagline |
| --- | --- | --- |
| `Shoreline` | Tidewatch Beach | Everyone in the circle catches |
| `Mesa` | Anvil Mesa | One catcher per bolt - 4x Volts |
| (future) | Meadow Station | (Default theme) |

The gates and signs print `Config.ZONES[id].displayName` and `tagline`, so
renaming a zone in Config renames it everywhere.

## Revision notes (review round 2)

- Coastlines: `Geo.wave` is overdriven and clipped, so outlines have long near-straight runs between bites; `Geo.fan` varies its edge bumps about 0.5x-2x round the coast instead of equal scallops.
- Shoreline stripes are flush SmoothPlastic inlays (7 studs, saturated sea-glass teal `64,200,196`) with cream piping, top at floor + 0.05, so the colour no longer depends on terrain tinting.
- Mesa gets a tall stepped butte behind the field (floor + 6 / 16 / 26 / 28 cap) and a long low sand terrace on one side; both are skipped by `Geo.clearOf` if a future zone, the teaser or the hub would be too close.
- Teaser: the deck runs 70% of the way, ending at tall caution-striped gate posts with a lit neon crossbar; the "?" balloon floats at y >= 68, above the lighthouse lens.
