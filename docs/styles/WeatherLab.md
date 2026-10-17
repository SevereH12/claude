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
(warm pale Sand, creamy Salt, terracotta Sandstone, cream Limestone, kelp
Grass, blue-grey Slate) and the sea is a clear teal.

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
- Terrain: Sand beaches and shallows, Salt beach-towel stripes, Sandstone /
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
- Natural forms are never rectangles or circles: every landmass is a
  stack of terraces with wobbly outlines that steps down through beach and
  shallows into the sea, so coastlines read as layered and irregular.
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
- **Sell station (the Volt Exchange)**: at the lighthouse door. A big
  yellow pad framed in navy with glowing edges and "SELL" painted on it, a
  striped arch carrying a giant SELL board, two glass charge tanks full of
  cyan lightning wired up the tower to the lens. It faces the spawn, so it
  is the first thing a player sees.
- **Spawn**: a cream compass deck on the plaza facing the sell station.
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
- **Coast**: terraced grass bank, sand beach, shallows; a brick-walled cove
  with a jetty and moored boats; marker buoys; sea-stack islets.

## Zones

Every zone island is generic (any slot position, rotation, size, height):
- **Ground**: a stack of terraces with wobbly outlines around the
  footprint (shallows, beach, then theme layers), flat at the floor height
  across the footprint plus a rim for props.
- **Catch floor**: flat terrain painted in a bold two-tone pattern with a
  contrasting trim around the field edge. Nothing stands on it.
- **Border**: posts just outside the footprint edge every ~9 studs, each
  with a glowing cap in the zone colour, joined by a glowing rope; striped
  survey poles with windsocks at the corners.
- **Gate**: two striped lighthouse-style posts and a beam with the zone's
  name and tagline facing the boardwalk ("BACK TO THE HARBOUR" on the
  back), lanterns, a windsock, and a value plaque.
- **Connector**: a winding plank boardwalk on stilts over the water, flat
  at both ends, a rest platform with a bench on long ones, rope rails with
  zone-coloured glowing caps and amber lanterns.

| Theme | Field pattern | Hero landmark (outside the field) | Edge dressing |
| --- | --- | --- | --- |
| `Beach` | Sand / Salt beach-towel stripes, plank trim | A giant red-and-white striped weather balloon on tethers above a launch deck | dunes with beach grass, beach huts, umbrellas, a tide-watch tower, palms, buoys, a rowboat, rocks, shells, driftwood |
| `Canyon` | Sandstone / Limestone checkerboard, brick trim | The Anvil Observatory: a white dome with a telescope on a striped rock spire | layered sandstone cliffs and hoodoos, a farm windmill, adobe weather huts, windsocks, cacti, tumbleweeds, rocks |
| `Default` | Grass / LeafyGrass mowed stripes, salt-white line trim | A radar mast with a big white radome and a red beacon | grass banks, a greenhouse, an instrument shelter, hay bales, round trees, flowers, rocks |

## Teaser (Coming Soon)

A misty rock island in the next slot with a survey camp (tent, crates,
scaffold) and a grey "?" balloon. The boardwalk to it stops half-way:
bare stilts stick out of the water past a striped barrier, caution rope,
and a big "COMING SOON" board.

## Proposed names (ids unchanged)

| Id | Display name | Tagline |
| --- | --- | --- |
| `Shoreline` | Tidewatch Beach | Everyone in the circle catches |
| `Mesa` | Anvil Mesa | One catcher per bolt - 4x Volts |
| (future) | Meadow Station | (Default theme) |

The gates and signs print `Config.ZONES[id].displayName` and `tagline`, so
renaming a zone in Config renames it everywhere.
