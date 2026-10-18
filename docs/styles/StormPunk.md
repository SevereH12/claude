# StormPunk: Voltcliff Works

A lightning-harvesting factory island. The Stormworks Bottling Co. has
wired a ring of little islands into one big storm catcher: copper pylons
and brass catwalks, white ceramic insulators, and cyan electricity humming
in every cable. Calm weather is a warm, golden late afternoon over teal
water. In a storm the sky goes slate and indigo and the cyan glows take over.

Takes from Bee Swarm Simulator (not copied): big flat fields with a bold
two-tone pattern you can read from across the map, fields that get further
out and higher up as you progress, a small friendly hub with chunky signs,
and saturated, cheerful colours.

## Palette (10 colours)

| Token | RGB | Used for |
| --- | --- | --- |
| `copper` | 186, 104, 58 | Main metal: pylons, coil windings, pipes, chimney bands, bridge piles |
| `patina` | 78, 168, 150 | Verdigris: roofs, domes, panels, the Shoreline tide bands |
| `brass` | 222, 176, 78 | Trim: handrails, sign frames, lamp housings, rivets, gate arches |
| `ceramic` | 240, 236, 224 | Insulator stacks, lighthouse bands, sign boards, tank caps |
| `volt` | 90, 238, 255 | Electricity (Neon only): orbs, lanterns, glowing cables, coil sparks |
| `iron` | 60, 66, 78 | Girders, catwalk decks, lattice legs, machine bases |
| `soot` | 34, 36, 44 | Darkest accent: sign boards, text strokes, tyres, window glass |
| `hazard` | 255, 190, 40 | Amber: the SELL station, hazard stripes, the teaser, warm lamp light |
| `timber` | 156, 104, 64 | Boardwalks, piers, crates, scaffold planks |
| `sage` | 132, 158, 112 | Scrub plants, dune grass, the Mesa field tiles |

Each zone's own `Config` colour is used for its border cables, gate lights,
sign title and the floor light trail that leads to it, so a zone's colour is
also the colour of its warning circles.

## Materials

- Metal: `Metal` (copper, brass, iron), `CorrodedMetal` (old iron and piles),
  `DiamondPlate` (catwalk decks, the sell pad, floor plates).
- Ceramic: `SmoothPlastic` in `ceramic` (insulators read as glazed china).
- Energy: `Neon` in `volt` and the zone colours. Glass for lantern rooms.
- Wood: `WoodPlanks` (decks), `Wood` (posts, crates).
- Terrain: `Sand` beaches, `Limestone` and `Sandstone` mesa strata, `Slate`
  and `Rock` cliffs, `Basalt` sea stacks, `Brick` and `Pavement` hub plaza,
  `LeafyGrass` planters, `Water` sea.

## Shape language

- Chunky silhouettes from far away: tall thin verticals (coil, lighthouse,
  pylons, chimneys, the Thunder Spire) against low flat fields.
- Stacked rings: insulators, coil tori and banded chimneys are always piles
  of discs, so every tower reads as "electric" at any distance.
- Riveted rectangles for anything man-made (decks, boxes, plates) with
  brass trim lines. Round, wobbly, layered shapes for anything natural:
  coastlines, cliffs, terraces and sea stacks are never straight or circular.
- Lots of detail up close (bulbs, rivets, bolts, tufts, debris) but no
  detail at all on the catch floors, which stay flat and patterned.

## Lighting mood

- **Calm (cozy)**: ClockTime 15.4, warm sun, peach haze, soft cream clouds,
  teal water, gentle bloom so the amber lamps and cyan lanterns glow.
  Saturation +0.15, warm tint.
- **Storm (dramatic)**: StormBrightness 0.55, StormAmbient deep teal-indigo,
  StormAtmosphereColor slate blue, StormCloudColor near-black indigo. The
  scene goes dark and cold so the neon (cables, orbs, light trails, border
  cables) becomes the brightest thing on screen.

## Hub: Bottleworks Plaza

- Round, terraced island at y = 12 with slate cliffs, a sand beach and
  shallows. Brick plaza with a pavement core and flush copper rings.
- **Hero landmark: the Grand Coil** in the middle, about 90 studs tall: a
  copper drum, a lattice tower with an insulator column, a tori crown and
  a cyan orb. Glowing cables run from its crown to the capacitors.
- **Sell station: the Volt Exchange**, right in front of the coil and facing
  the spawn: an amber diamond-plate pad with "SELL" on it, a brass gantry
  with a giant marquee "SELL" sign lined with bulbs, two glass capacitor
  towers glowing cyan, and an amber chevron border. It is the brightest,
  warmest thing in the hub.
- Spawn: brass pad south of the Exchange, facing it. Every spawn sees SELL,
  the coil, and signposts to the zones. Below it, a little harbour with a
  pier and a moored storm skiff.
- Wayfinding: a light trail in each zone's colour runs from the coil ring
  to its bridge, with chevrons (the teaser's trail and lamps are grey: not
  open yet). A bridgehead arch with the zone's name
  stands at each exit, and arrow signs by the spawn point to every zone and
  to "Coming Soon".
- Hub props sit only on the "quiet" bearings halfway between the eight
  spiral bearings, so future zone exits are never blocked: Bottle Foundry
  with smokestacks, gasometer, water tower, storm siren, weather mast,
  bottle kiosk, a garden with benches, planters and lamps. A brass ring
  frames the pavement core, and a chained bollard promenade runs round the
  rim with gaps where trails leave.
- Scenery: little basalt islets on quiet bearings, each with a Tesla
  pylon, strung together with power lines around the hub, plus grass-capped
  basalt sea stacks further out. Terrain costs no parts, so the big
  silhouettes (cliffs, stacks, the Thunder Spire, the arch) are terrain.

## Zones

Every zone gets the same shared kit (riveted catwalk connector, insulator
fence border, insulator arch gate) plus its theme. Themes work for any slot
position, rotation, size and height because everything is placed in the
slot's own frame (`Kit.footprintPoint`, `Kit.perimeter`).

- **Border**: copper posts on the footprint edge carrying white insulator
  stacks and a lamp cap in the zone colour, joined by glowing cables in the
  zone colour. There is a gap at the gate.
- **Gate**: two banded copper pylons with insulator stacks, a brass arch
  beam, a dark sign board with the zone name in its colour and the tagline
  in white, and a Jacob's ladder of cyan arcs on top.
- **Connector**: a riveted catwalk on copper piles, brass handrails, lamp
  posts with cyan lanterns, glowing cables between lamps, and the zone's
  light trail down the middle. Any length or slope works; piles and lamps
  are spaced along whatever length the slot gives. A connector to a
  low (sea-level) zone gets a channel of sea carved under it so it never
  stands on dry sand.

### Beach -> Shoreline ("Tidewire Beach", tagline "Everyone in the circle catches")
- Ground: flat sand field at the floor height, sloping beaches, an uneven
  coastline (bays and points, not even bumps) with shallows, grassy dunes,
  and layered basalt and slate headlands.
- Floor: two-tone tide stripes. Patina bands whose back edges are scalloped
  like rolling waves, over warm sand, inside a brass frame.
- Hero: **the Tidewire Lighthouse** on a headland behind the field, with
  ceramic and copper bands, a glass lantern with a cyan core, and a lightning
  rod.
- Edge: palms, a pier with a lamp and a moored skiff, striped bathing huts,
  crates and barrels, buoys with lamps, driftwood, rocks and dune grass.

### Canyon -> Mesa ("Thunderhead Mesa", tagline "One catcher per bolt - 4x Volts")
- Ground: a raised plateau over shifted terraces of striped sandstone,
  limestone and rock cliffs (sandstone ledge, then a green ledge, then
  sand), hoodoo pillars and a natural rock arch. High mesas keep at most
  three terraces with taller cliffs, so they never sprawl into neighbours.
- Floor: two-tone sage and cream checkerboard inside a brass frame.
- Hero: **the Thunder Spire**, a tall layered rock pinnacle behind the mesa
  topped with a brass lightning rod and a cyan orb, with cables down to
  the mesa rim.
- Edge: a mine headframe, ore carts on rails, a windpump, copper "cactus"
  rods, pipes down the cliff, crates, rocks and scrub.

### Default (any future theme): "Generator Yard"
- Ground: a slate and rock island with stepped cliffs.
- Floor: riveted plate grid with two-tone diamond plates and dark grout
  lines.
- Hero: **the Dynamo Stack**, a banded smokestack beside a big generator
  drum with an orb.
- Edge: transformers, pipe runs, barrels and rocks.

## Teaser: Coming Soon

The next empty slot is a tall basalt island with scaffolding and a
construction crane, as its own hero. A catwalk leaves the hub and stops
halfway at an amber and black barricade with a big "COMING SOON" sign.
Bare piles carry on toward the island with a girder hanging off them.

## Proposed display names (ids stay)

| id | Display name | Tagline |
| --- | --- | --- |
| Shoreline | Tidewire Beach | Everyone in the circle catches |
| Mesa | Thunderhead Mesa | One catcher per bolt - 4x Volts |

Signs read `displayName` and `tagline` from `Config.ZONES`, so renaming
there updates the world.

## Stacking rules (how new zones stay safe)

- Every placement is in the slot's own frame, so any position, rotation,
  size or floor height works.
- Raised terrain is clipped (`Geo.landSafe`) wherever it would rise above
  a connector deck or into another zone's footprint above that zone's
  floor. Catwalks always meet flush ground at both ends, both ways.
- After all zone landmasses are down, the hub's upper terrain is laid again
  so the plaza always wins where shores merge.
- Each zone draws from its own seeded Random (one number from `ctx.rng` +
  the zone id), so adding a zone never reshuffles earlier zones' props.
- Dressing density comes from the zone's own spiral index (zones 1-2 full,
  then leaner, like a distance LOD). The current 2-zone map is about 1,800
  parts. Each extra zone adds about 300-450.
- Tested with 5 extra zones (unknown themes, a raised beach at y = 68, a
  132 x 132 Default zone at y = 84, a zone at y = 100): every floor is flat,
  reachable from spawn, and walkable back to spawn and the sell pad.

## Layout

`hubFloor 12, hubRadius 52, firstRadius 148, radiusStep 54, firstAngle
100, angleStep 135, teaser 96 x 88, teaserFloorStep 16`. Exits fall on 8
bearings (10 + 45k degrees). Footprints stay 70+ studs apart and
connectors never cross another zone, even with 5 more zones of up to 132 x
132.
