# World styles

The map is built by `src/server/World/Builder.luau`: one world per
`Config.WORLDS` entry, each with its own style pack from
`src/server/World/Styles/`. Every pack builds the same gameplay layout (hub
with spawn, sell station and portals, one zone per `Config.ZONES` entry in
that world, and a "Coming Soon" teaser).

All three are built from blocks: the ground is chunky SmoothPlastic parts
(`src/server/World/Blocks.luau`) rather than Roblox Terrain, for a clean,
hand-built diorama look. Lightning lands on the `Map.Ground` parts.

## Worlds and styles

World 1, Barometer Bay, is built in WeatherLab; world 2, Voltcliff Works, in
StormPunk. SkyIsles is unused, kept for a future world. A world's `style` in
`Config.WORLDS` picks its pack; push, then click **Update Game** in Studio.
To review a pack on its own, `tools/check_world.sh <Style>` builds the first
world's zones in it. A pack used for a world must build its hub's portals
(`ctx.portals`, `Kit.portal`).

## WeatherLab (live)

A seaside weather-research station. The hub island has a lighthouse hero,
a big yellow SELL pad facing the spawn under a 30-stud SELL board, a
fingerpost pointing to each zone, and zone-coloured trails along boardwalk
bridges. Shoreline is a striped sand-and-teal beach field; Mesa is a
terracotta-and-cream checker on a canyon plateau. Its part budget is split
fairly across zones so it keeps working as zones are added (about 2,350
parts with two zones). Chosen by 2 of 3 judges for first impressions,
wayfinding and room to grow. Style guide: `docs/styles/WeatherLab.md`.

## StormPunk (world 2, Voltcliff Works)

"Voltcliff Works": copper coils, insulators and factory islands. A Grand
Coil hero with the Volt Exchange sell station, insulator-post borders with
glowing cables, and zones that spiral up around the hub like a mountain.
The lightest pack (about 1,300 parts). Style guide: `docs/styles/StormPunk.md`.

## SkyIsles (unused, for a future world)

Floating sky islands with rune bridges and the Stormspire crystal tower over
the sell altar. Boldest field patterns (tile frames with neon corners,
ripple rings, big checkers). About 1,900 parts. Style guide:
`docs/styles/SkyIsles.md`.

## Ideas to graft onto WeatherLab later

- SkyIsles' chunky field frame and higher-contrast field colours.
- StormPunk's steeper spiral climb and insulator caps on border posts.
