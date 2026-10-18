# SkyIsles: the Stormspire Isles

A sky archipelago. Floating rock islands are chained to a central storm
temple, the **Stormspire**, high above an endless sea of clouds. Glowing rune
bridges link the islands, and crystals drink in the lightning. Every catch
floor is a big, flat, two-tone field you can read from far away (Bee Swarm
style), and the fields climb outward and upward around the spire.

Code: `src/server/World/Styles/SkyIsles/` (`init.luau` is the StylePack;
`Palette`, `Pieces`, `Sky`, `Hub`, `Zone`, `Teaser`, `Themes/*`).

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

### Materials

- Terrain (recoloured per material in `Palette.TERRAIN`): Rock (lilac
  skystone cliffs), Slate and Basalt (plum undersides getting darker toward
  the tips), Pavement (hub plaza), Grass (hub lawns only, never a catch
  floor, because grass blades would hide warning circles), Sand (beaches),
  Sandstone and Ground (canyon strata), Limestone (pale ledges), Water
  (tide pools).
- Parts: Slate and Cobblestone for masonry, Marble for caps, Neon for
  energy, Glass for crystal shells, Wood for palms and the skiff, Fabric for
  banners and parasols, Grass/Ground for the field bands.

### Shape language

- **Chunky and tapering.** Islands are wide on top and taper to a rocky
  point, with hanging rock and crystal stalactites. Towers taper too.
- **Layered.** Every landmass has a flat top, a lower terrace or two and
  raised outcrops, so the edge reads as stacked cliffs, never a plain
  rectangle or circle.
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

`hubFloor 12, hubRadius 56, firstRadius 168, radiusStep 28, firstAngle 90,
angleStep 135`. A 135 degree step puts slots on the eight compass
directions (E, SW, N, SE, W, NE, S, NW), each a little further out and (by
Config) higher than the last: a spiral staircase of floating fields. Seven
zones plus the teaser fit with no overlaps and every connector under 24
degrees.

## Hub: Stormspire

- **Landmass:** a compass-rose island. The paved plaza (radius 56, y=12)
  grows grassy lobes between the eight lanes, with lower terraces at y=8 and
  y=4 hanging off them, and tapers into an inverted mountain about 90 studs
  deep with glowing crystal stalactites underneath. Lanes stay clear out to
  the rim so future bridges can attach anywhere.
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

- **Ground:** a floating island built around the footprint: a rounded rim
  of flat land (10 studs) with an uneven coast of mostly small lobes and the
  odd big bulge, a rock shelf 4 studs lower, terraces 8 and 12 studs lower,
  two peninsulas, a themed backdrop ridge behind the field (so it sits in a
  cove), and a tapering underside with stalactites and hanging crystals.
  Nothing rises inside the footprint, and every lump is checked against the
  hub, other zones' footprints and every bridge corridor.
- **Catch floor:** terrain sits exactly at the floor. The pattern is a carpet
  of flush part rings, checks or bands framed by a chunky 4-stud rim of
  alternating zone-colour tiles with clipped dark corners and a cream inner
  line (top at floor+0.2, under the warning circles,
  can't be collided with), plus a glowing edge line in the zone colour.
- **Border:** rune posts on the footprint edge with crystal caps in the zone
  colour, linked by glowing sagging rune cables. Every fourth post is a
  taller pylon with a light. There's a gap at the gate.
- **Gate:** twin pillars with a stepped arch, the zone's name and tagline
  on a framed board facing the hub, and lanterns.
- **Connector:** a rune bridge: stone deck with curbs, a glowing centre
  inlay in the zone colour, posts with crystal lanterns, glowing rail
  cables, and keystones hanging underneath. Flat landings at both ends, a
  ramp between.

### Themes

| Theme | Field | Edge dressing | Hero landmark |
| --- | --- | --- | --- |
| Beach (Shoreline) | concentric ripple rings of pale mint and deep teal (cool and high contrast, so yellow circles pop) | golden sand rim, rocky ridge behind, palms leaning off the field, parasols, dune grass, shoreline boulders, tide pools spilling waterfalls into the clouds, shells and driftwood, a cabana, a pier and a moored sky-skiff on a headland | **Sky Lighthouse**: striped tower on a rock point at the end of a sandy headland, cyan storm-lamp throwing two light beams |
| Canyon (Mesa) | bold 16-stud checker of lilac and plum (complementary to orange) | ember rim over an ochre shelf, banded sandstone walls behind, corner strata buttes with crystals, a natural arch, hoodoos, cacti, a crystal mine-cart headland, lantern posts | **Crystal Butte**: a 35-stud layered butte crowned with a giant amber crystal, a lightning rod and a rune ring |
| Default (any new theme) | checkerboard in the complementary hue of the zone colour | grassy rim, rolling hills behind, a standing-stone rune circle headland, a pond headland with a waterfall, crystal trees, meadows of flowers, lanterns | **Rune Obelisk**: tiered obelisk on a knoll with a floating crystal and rune rings in the zone colour |

A theme reused by a zone whose colour is close to the theme's field hue
switches its field to that colour's complement automatically
(`Palette.fieldTones`), so circles stay readable whatever the Config says.

### Teaser

The next slot is an unfinished, storm-veiled island: dark basalt with rock
boulders, violet crystals, a 28-stud violet crystal spire in a three-level scaffold (the isle's silhouette from spawn), a lower slate terrace, crates and a
survey flag under rolling violet mist; a half-built rune bridge stops at a
glowing (solid) rune barrier with a **COMING SOON** board, loose bridge
stones drift in the gap, and a stub reaches out from the island side.

## Stacking and budgets

- Tested with five extra Config zones (themes Volcano, Ice, Beach, Canyon,
  Sky at floors 32 to 80): every zone lands on its compass lane, every lane
  lights up with its own trail and gateway, all catch floors stay 100% flat,
  open and reachable, and the teaser moves to the eighth lane.
- The current world (2 zones + teaser) is about 1,510 parts, 42 lights,
  9 particle emitters and about 200 beams. Each extra zone adds roughly
  330 parts (zone) + 70 (bridge) + 30 (hub lane), so about four zones fit
  under 2,500 parts; beyond that the budget has to grow.
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
