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
- Ground: no terrain. All land is chunky anchored `SmoothPlastic` blocks in
  `Workspace.Map.Ground` (built with `World/Blocks` through `Land.luau`), and
  colour carries the look (`Palette.ground`): sand beaches and aprons, wet
  sand shore slopes, limestone and sandstone mesa strata, slate and basalt
  cliffs and columns, light grass caps, a brick and pavement hub plaza. The
  sea is one see-through teal water part at y = 0 over a solid seabed at
  y = -3 (walkable: anyone who falls in wades to a shore slope).

## Shape language

- Chunky silhouettes from far away: tall thin verticals (coil, lighthouse,
  pylons, chimneys, the Thunder Spire) against low flat fields.
- Stacked rings: insulators, coil tori and banded chimneys are always piles
  of discs, so every tower reads as "electric" at any distance.
- Riveted rectangles for anything man-made (decks, boxes, plates, and the
  stepped field platforms) with brass trim lines. Faceted polygons for
  anything natural: islands are 10-16-sided blocks unioned from overlapping
  lobes, cliffs are two-tone strata that step out as they go down, with a
  light grass cap overhanging a little, and sea stacks and crags are
  clusters of hexagonal basalt columns.
- How the blocks are built: a regular polygon with 2k sides is k boxes,
  each spanning two opposite faces (a 12-gon is 6 parts, a hex column 3).
  Shapes that meet at the same height share one colour key, so overlapping
  tops never flicker. Shore slopes are one wedge per face at 24 degrees.
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

- Round terraced citadel of 16-gons turned so a face looks down every exit
  and quiet bearing: a brick plaza at y = 12 on a slate band, a green
  terrace at y = 8 on slate and basalt strata, a sand beach at y = 1 with a
  shore slope all round (plus two lobes the crags stand on while the world
  is small). Pavement core and a flush brass ring on the plaza; path strips
  (0.2 up, darker edging) run out to every exit and carry the light trails.
- **Hero landmark: the Grand Coil** in the middle, about 90 studs tall: a
  copper drum, a lattice tower with an insulator column, a tori crown and
  a cyan orb. Glowing cables run from its crown to the capacitors.
- **Sell station: the Volt Exchange**, right in front of the coil and facing
  the spawn: an amber diamond-plate pad with "SELL" on it, a brass gantry
  with a giant marquee "SELL" sign lined with bulbs, two glass capacitor
  towers glowing cyan, and an amber chevron border. It is the brightest,
  warmest thing in the hub.
- Spawn: brass pad south of the Exchange, facing it. Every spawn sees SELL,
  the coil, and signposts to the zones. Below it, a paved harbour path
  (two ramps, 23 and 26 degrees, with a landing on the terrace) down to the
  beach, a pier and a moored storm skiff.
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
- Scenery: little grass-capped basalt islets on quiet bearings, each with a
  Tesla pylon, strung together with power lines around the hub; clusters
  of basalt columns standing in the sea further out; and three basalt
  column crags behind the coil. Islets and stacks keep to open water
  (clear of every island) and thin out as zones are added.

## Zones

Every zone gets the same shared kit (block island, riveted catwalk
connector, insulator fence border, insulator arch gate) plus its theme. Themes work for any slot
position, rotation, size and height because everything is placed in the
slot's own frame (`Kit.footprintPoint`, `Kit.perimeter`).

- **Border**: copper posts on the footprint edge carrying white insulator
  stacks and a lamp cap in the zone colour, joined by glowing cables in the
  zone colour. There is a gap at the gate.
- **Gate**: two banded copper pylons with insulator stacks, a brass arch
  beam, a dark sign board with the zone name in its colour and the tagline
  in white, and a Jacob's ladder of cyan arcs on top.
- **Island** (`Zone.island`): the catch floor is a rectangular slab exactly
  at the floor over the whole footprint + 4.5 studs (the gate pillars and
  the catwalk's last studs stand on it). Under it the strata step out: a
  field near sea level gets 1-stud walkable steps down to the beach, a
  raised one gets two-tone cliff bands (optionally leaning to one side, or
  with a grass-capped shelf). Round the foot is a sand apron at beach level,
  and behind and beside it polygon beach lobes with shore slopes. Nothing
  lands on the hub side, so low catwalks cross open water.
- **Connector**: a riveted catwalk on copper piles, brass handrails, lamp
  posts with cyan lanterns, glowing cables between lamps, and the zone's
  light trail down the middle. Any length or slope works; piles and lamps
  are spaced along whatever length the slot gives. Long spans hop across
  grass-capped rock columns. Both ends meet the ground within a stud.

### Beach -> Shoreline ("Tidewire Beach", tagline "Everyone in the circle catches")
- Ground: sand field on limestone and sandstone steps, a wide back beach
  and a side bump, grassy two-tier dunes, a slate-and-basalt headland with
  a grass cap for the lighthouse, and basalt column clusters breaking the
  coast.
- Floor: two-tone tide stripes. Patina bands whose back edges are scalloped
  like rolling waves, over warm sand, inside a brass frame.
- Hero: **the Tidewire Lighthouse** on a headland behind the field, with
  ceramic and copper bands, a glass lantern with a cyan core, and a lightning
  rod.
- Edge: palms, a pier with a lamp and a moored skiff, striped bathing huts,
  crates and barrels, buoys with lamps, driftwood, rocks and dune grass.

### Canyon -> Mesa ("Thunderhead Mesa", tagline "One catcher per bolt - 4x Volts")
- Ground: a raised plateau over sandstone and limestone strata that step
  out a stud all round plus a wide ledge on one side and the back (the
  other side drops sheer); the second ledge is green. A ridge of rock
  columns behind, two-tone hoodoo columns, a natural arch (two hex legs and
  a lintel block), talus rocks on the sand. At most 3-4 bands however high.
- Floor: two-tone sage and cream checkerboard inside a brass frame.
- Hero: **the Thunder Spire**, four twisting hex tiers behind the mesa
  topped with a brass lightning rod and a cyan orb, with cables down to
  the mesa rim.
- Edge: a mine headframe, ore carts on rails, a windpump, copper "cactus"
  rods, pipes down the cliff, crates, rocks and scrub.

### Default (any future theme): "Generator Yard"
- Ground: a concrete yard on slate and basalt strata with a wide grassy
  shelf, a basalt column crag behind, and a concrete pad flush with the
  yard for the hero.
- Floor: riveted plate grid with two-tone diamond plates and dark grout
  lines.
- Hero: **the Dynamo Stack**, a banded smokestack beside a big generator
  drum with an orb.
- Edge: transformers, pipe runs, barrels and rocks.

## Teaser: Coming Soon

The next empty slot is a tall basalt island (a sand beach with shore
slopes, a rock-capped ledge, then a grass-capped top) with scaffolding and
a construction crane, as its own hero, and column stacks around it. A catwalk leaves the hub and stops
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
- Every ground shape passes `Geo.guard` along its outline: a shape that
  would rise above a connector deck or into another zone's footprint is
  shrunk (`Land.fit`) or, for a stratum, keeps the band above's outline (a
  sheer face). Catwalks always meet the ground within a stud at both ends.
- Shores that meet do so at the same height and colour key, so merged
  beaches are one surface. Scenery (crags, islets, stacks) is placed after
  every zone island, in open water.
- Each zone draws from its own seeded Random (one number from `ctx.rng` +
  the zone id), so adding a zone never reshuffles earlier zones' props.
- Part budget (`Geo.zoneDetail`, `Geo.worldDetail`): a zone's optional
  ground pieces depend only on its own spiral index (zones 1-2 full, later
  zones lean: one beach lobe, fewer columns, a lighter hero pad), so adding
  a zone never changes an earlier zone's ground or props; the hub's
  scenery thins as zones are added. The 2-zone map is about 1,330 parts
  (about 500 of them ground); a 7-zone test world is about 2,440.
- Tested with 5 extra zones (unknown themes, a raised beach at y = 68, a
  132 x 132 Default zone at y = 84, a zone at y = 100): every floor is flat,
  reachable from spawn, and walkable back to spawn and the sell pad.

## Layout

`hubFloor 12, hubRadius 52, firstRadius 148, radiusStep 54, firstAngle
100, angleStep 135, teaser 96 x 88, teaserFloorStep 16`. Exits fall on 8
bearings (10 + 45k degrees). Footprints stay 70+ studs apart and
connectors never cross another zone, even with 5 more zones of up to 132 x
132.
