# SkyIsles: the Stormspire Isles

A sky archipelago. Floating rock islands are chained to a central storm
temple, the **Stormspire**, high above an endless sea of clouds. Glowing rune
bridges link the islands, and crystals drink in the lightning. Every catch
floor is a big, flat, two-tone field you can read from far away (Bee Swarm
style), and the fields climb outward and upward around the spire.

Code: `src/server/World/Styles/SkyIsles/` (`init.luau` is the StylePack;
`Palette`, `Ground`, `Pieces`, `Sky`, `Hub`, `Zone`, `Teaser`, `Themes/*`).

The style is block-built (`ground = "Blocks"`): every island, field bed,
headland, ridge and hanging rock is a chunky SmoothPlastic part in
`Map.Ground`, and no terrain is filled. It reads like a clean, hand-built
diorama: colour carries the look, with no unions, meshes, decals or
textured materials on the ground.

## Style guide

### Palette (10 colours)

| Name | RGB | Used for |
| --- | --- | --- |
| Skystone | 150, 138, 176 | Main masonry: temple, posts, bridge decks, arches. Lilac-grey, so it sits in the haze. |
| Dusk Plum | 84, 68, 108 | Trim, shadow side, sign boards, island undersides (deep rock). |
| Cloud Cream | 246, 238, 224 | Marble caps, rails, lighthouse, sign frames, the cloud sea. |
| Meadow | 110, 186, 86 | Lawns, foliage, palm fronds, garden beds. |
| Storm Cyan | 90, 228, 255 | Energy: crystals, rune inlays, bridge rails, the spire crystal. |
| Volt Gold | 255, 204, 72 | Selling and money: the SELL altar, gold trims, important signs. |
| Sunset Coral | 255, 122, 104 | Warm accent: banners, roof tiles, lighthouse stripes, flowers. |
| Seaglass | 70, 170, 140 | Cloudshore field, shallow water, cool foliage. |
| Ember | 208, 106, 66 | Canyon cliffs, hoodoos, strata. |
| Twilight | 118, 98, 166 | Mesa field, storm accents, crystal shells. |

Zone colours from `Config.ZONES` (Shoreline yellow, Mesa orange) are used
for each zone's rune cables, light trail, gate glow and crystals, so a zone
and its trail always match. Catch floors are always tinted in colours that
contrast with that zone colour (cool greens under yellow, violets under
orange; the Default theme picks the complementary hue automatically), so
the warning circles stand out.

### Ground (blocks)

`Ground.luau` builds all of it, and logs every ground part so the style can
ask "is this inside land?" (waterfall lips, tether checks) or "how high is
the ground here?" without reading parts back.

- **Polygons.** Islands, lobes, lawns, tiers and headlands are regular
  8 to 16-sided polygons. An even 2k-gon is exactly the union of k
  rectangles turned pi/k apart, so a 12-gon costs only 6 parts. The pieces
  of one layer share one exact colour (no jitter), so their coplanar
  overlaps merge into one shape and never flicker.
- **Layers.** Every island is a light **cap** 1 stud thick that overhangs
  its darker **soil** band by 0.6 studs, over a stepped, tapering
  **underside**: stacked polygon (or chamfered-rectangle) tiers shrinking
  downward in two alternating rock tones, ending in **hanging points** (two
  shrinking blocks turned 45 degrees apart and a cube balanced on its
  corner).
- **Colours** (`Palette.GROUND`): grass caps over plum soil, sand caps over
  wet sand, ember caps over sandstone; cliffs in pale skystone, skystone and
  slate (ochre and dark ember in the canyon); basalt or slate points.
- **Water** is see-through, non-collidable `Blocks.water` sheets: pools on
  lawns and beaches and spill channels that feed the beam waterfalls.
- **Props** stay as they were (Slate and Cobblestone masonry, Marble caps,
  Neon energy, Glass crystal shells, Wood, Fabric); rocks are `Blocks.rock`
  clusters, and the field carpets, turf patches and hoodoos are
  SmoothPlastic.

### Shape language

- **Chunky and tapering.** Islands are wide on top and taper to a rocky
  point, with hanging rock and crystal stalactites. Towers taper too.
- **Layered.** Every landmass has a light cap over a soil band over rock
  strata that step inward, with lobes and headlands breaking its outline,
  so the edge reads as stacked cliffs, never a plain rectangle or circle.
- **Eight-fold compass.** The hub is a compass rose: eight lanes, eight
  pillars, an eight-point star dais. Zones arrive on those lanes.
- **Shards and rings.** Energy is shown with tilted crystal shards and
  rings of glowing rune cable.
- Big shapes are simple and bold from far away; detail (rocks, shells,
  flowers, lanterns, cables) is small and only shows up close.

### Lighting mood

- **Calm (cozy):** late-afternoon sun (ClockTime 15.6), warm tint, lilac
  haze, soft white clouds above and a cream cloud sea below. Neon is
  subtle in daylight.
- **Storm (dramatic):** the sky drops to deep indigo
  (`StormAtmosphereColor` 46,40,84; `StormCloudColor` 44,40,72;
  `StormAmbient` 70,74,120; `StormBrightness` 0.55). Neon crystals,
  rune trails and cables suddenly become the brightest things in view, so
  the paths home light up just when you need them.

## Layout

`hubFloor 0, hubRadius 56, firstRadius 168, radiusStep 28, firstAngle 90,
angleStep 135`. A 135 degree step puts slots on the eight compass
directions (E, SW, N, SE, W, NE, S, NW), each a little further out and (by
Config) higher than the last: a spiral staircase of floating fields. Seven
zones plus the teaser fit with no overlaps and every connector under 24
degrees.

## Hub: Stormspire

- **Landmass:** a compass-rose island. A paved sixteen-sided plaza
  (apothem 58, y=0) over a skystone band, with grassy octagon lawns one
  step (1 stud) lower between the eight lanes, two of them holding pools
  that spill waterfalls into the clouds. Under it, six polygon tiers shrink
  downward in alternating rock tones to a basalt spike about 105 studs
  down, with glowing crystals hanging from the ledges and a big cluster at
  the tip. Lanes stay clear out to the rim so future bridges can attach
  anywhere; bridge decks lie 0.2 studs above the plaza.
- **Hero landmark and sell station (one piece):** the Stormspire stands
  over the hub centre. Eight pillars hung with coral and cyan banners hold
  up a canopy over the **Charge Altar**, a gold star dais with a 20x20
  glowing gold SELL pad lettered "SELL" along all four edges (readable from
  every approach). Four big two-sided SELL boards hang under the canopy,
  and a column of light pours from a gold crystal down onto the pad. Above
  the canopy a tapering star tower with glowing window slits rises to about
  110 studs, rune stones drift around it, and a giant floating storm
  crystal (a fat 10x22 glass octahedron with a neon heart) on four prongs, with four large rune stones orbiting below, is ringed by three rune rings and crackling arcs.
  A snapped iron tether hangs from the tower toward the teaser (it hangs
  snapped).
- **Spawn:** a rune circle on the plaza beside the first zone's lane,
  facing the altar, with a compass signpost (arrows to SELL, every zone and
  the teaser; it grows taller as zones are added) and a welcome board
  behind it. Nothing in the hub ever stands on a lane, current or future.
- **Wayfinding:** every active lane has a light trail in the zone's colour
  (a glowing centre line with chevrons pointing outward), a rune gateway
  with the zone's name at the rim, and a lane stone at the altar. The
  teaser lane has a dim grey trail and a COMING SOON gateway. Lanes for
  future zones are plain paved strips that light up when a zone arrives.

## Zones

Shared by all themes (`Zone.luau`), so any slot, size or rotation works:

- **Ground:** a floating island built around the footprint: a plateau
  (footprint plus a 10-stud rim, plus `spec.shore` on the sides and back,
  corners chamfered 6 studs) whose cap top is exactly the floor, four to
  six 10-gon coast lobes pushing the outline out round the sides and back,
  a themed backdrop ridge on the land edge behind the field (so it sits in
  a cove), and a tapering underside (a chamfered slab, a stepped slab, a
  12-gon and an octagon) with two hanging points and three crystal
  clusters hanging from its ledges. Nothing rises inside the footprint, and
  every lobe and lump is checked against the hub, other zones' footprints
  and every bridge corridor. All placement is slot-relative, so new
  Config zones get the same island.
- **Catch floor:** the plateau cap is one flat block surface exactly at
  the floor across the whole footprint. The pattern is a carpet of flush
  SmoothPlastic rings, checks or bands framed by a chunky 4-stud rim of
  alternating zone-colour tiles with clipped dark corners and a cream inner
  line (top at floor+0.2, under the warning circles, can't be collided
  with), plus a glowing edge line in the zone colour.
- **Border:** rune posts on the footprint edge with crystal caps in the zone
  colour, linked by glowing sagging rune cables. Every fourth post is a
  taller pylon with a light. There's a gap at the gate.
- **Gate:** twin pillars with a stepped arch, the zone's name and tagline
  on a framed board facing the hub, and lanterns.
- **Connector:** a rune bridge: stone deck with curbs, a glowing centre
  inlay in the zone colour, posts with crystal lanterns, glowing rail
  cables, and keystones hanging underneath. Flat landings at both ends
  (lying 0.2 studs above the ground they land on), a ramp between.

### Themes

| Theme | Field | Edge dressing | Hero landmark |
| --- | --- | --- | --- |
| Beach (Shoreline) | concentric ripple rings of pale mint and deep teal (cool and high contrast, so yellow circles pop) | a broad sand rim (6 studs wider on the sides and back) over wet sand, stepped sand dunes with grass crowns behind, rock spires, palms leaning off the field, parasols, dune-grass turf, shoreline boulders, tide pools spilling waterfalls into the clouds, shells and driftwood, a cabana, a pier and a moored sky-skiff on a headland | **Sky Lighthouse**: striped tower on a two-tier rock point at the end of a sandy headland, cyan storm-lamp throwing two light beams |
| Canyon (Mesa) | bold 16-stud checker of lilac and plum (complementary to orange) | ember rim over a sandstone band and ochre / dark-ember strata, tilted sandstone slabs behind, corner strata buttes with crystals, a block arch, hoodoos, cacti, ochre turf, a crystal mine-cart headland, lantern posts | **Crystal Butte**: a 35-stud stack of octagon strata under a slate caprock with a talus apron, crowned with a giant amber crystal, a lightning rod and a rune ring |
| Default (any new theme) | checkerboard in the complementary hue of the zone colour | grassy rim over plum soil, stepped grassy mounds behind, a standing-stone rune circle headland, a pond headland with a waterfall, crystal trees, turf and flowers, lanterns | **Rune Obelisk**: tiered obelisk on a stepped knoll (two 1-stud steps) with a floating crystal and rune rings in the zone colour |

A theme reused by a zone whose colour is close to the theme's field hue
switches its field to that colour's complement automatically
(`Palette.fieldTones`), so circles stay readable whatever the Config says.

### Teaser

The next slot is an unfinished, storm-veiled island: a sixteen-sided storm
rock isle over basalt with a three-tier underside and hanging points,
violet crystals, a 28-stud violet crystal spire in a three-level scaffold
(the isle's silhouette from spawn), a lower slate terrace 8 studs down,
crates and a survey flag under rolling violet mist; a half-built rune bridge stops at a
glowing (solid) rune barrier with a **COMING SOON** board, loose bridge
stones drift in the gap, and a stub reaches out from the island side.

## Stacking and budgets

- Tested with four extra Config zones (themes Volcano and Ice, which fall
  back to Default, plus Beach and Canyon, at floors 32 to 68): every zone
  lands on its compass lane, every catch floor is covered by block ground
  at exactly its floor height and stays 100% flat, open and reachable, and
  the teaser moves out along the spiral.
- The current world (2 zones + teaser) is about 1,900 parts, of which about
  610 are ground (hub ~115, each zone ~200 with its theme's landforms,
  teaser ~45, eight drifting islets ~90). Each extra zone adds roughly 460
  parts (about 200 of them ground), so one more zone fits under 2,500
  parts; beyond that the budget has to grow or the islands get cheaper
  (octagon lobes, fewer drifters).
- Lights (86) and particle emitters (24) are hard-capped per world; the
  counters live on the Map folder.

### Proposed display names (ids stay the same)

| Id | Proposed display name | Tagline |
| --- | --- | --- |
| Shoreline | Cloudshore | Everyone in the circle catches |
| Mesa | Ember Mesa | One catcher per bolt - 4x Volts |
| (teaser) | Uncharted Isle | Coming soon |

Signs use `Config.ZONES[id].displayName`, so renaming in Config updates the
gates, the lane signs and the HUD banner together.
