# Storm Bottler Simulator

Roblox simulator: catch lightning in bottles during storms, sell charges at
the Power Plant for Volts, buy bigger bottles. All game code lives in `src/`
as Luau files laid out for Rojo (`default.project.json`). Use the roblox-dev
skills when writing Luau.

## How the code gets into Studio

The user installs `plugin/StormBottlerUpdater.server.luau` once (built with
`rojo build plugin/plugin.project.json -o StormBottlerUpdater.rbxmx`). Its
"Update Game" button downloads `src/` from GitHub (repo SevereH12/claude,
branch `claude/sweet-planck-ea1ob4`, must be public) and installs it with
the layout below, then rebuilds the map if `Map` has `AutoBuilt = true`.
So: commit and push to that branch and the user clicks Update Game.
If the branch changes, update `BRANCH` in the plugin and send a new build.

## Syncing `src/` into Roblox Studio (MCP, no Rojo)

When asked to sync, push, or install the code into Studio, use the
`Roblox_Studio` MCP tools against the open place. Every file maps to one
instance. Create any missing container with the exact class shown, then set
the script's source to the file's full contents (overwrite; never merge).

| File | Studio instance | Class |
| --- | --- | --- |
| `src/shared/` | `ReplicatedStorage.Shared` | Folder |
| `src/shared/Util/` | `ReplicatedStorage.Shared.Util` | Folder |
| `src/shared/<Name>.luau` | `ReplicatedStorage.Shared.<Name>` | ModuleScript |
| `src/shared/Util/<Name>.luau` | `ReplicatedStorage.Shared.Util.<Name>` | ModuleScript |
| `src/server/init.server.luau` | `ServerScriptService.Server` | **Script** |
| `src/server/Systems/` | `ServerScriptService.Server.Systems` | Folder |
| `src/server/Systems/<Name>.luau` | `ServerScriptService.Server.Systems.<Name>` | ModuleScript |
| `src/server/Lib/` | `ServerScriptService.Server.Lib` | Folder |
| `src/server/Lib/<Name>.luau` | `ServerScriptService.Server.Lib.<Name>` | ModuleScript |
| `src/client/init.client.luau` | `StarterPlayer.StarterPlayerScripts.Client` | **LocalScript** |
| `src/client/Controllers/` | `StarterPlayer.StarterPlayerScripts.Client.Controllers` | Folder |
| `src/client/Controllers/<Name>.luau` | `StarterPlayer.StarterPlayerScripts.Client.Controllers.<Name>` | ModuleScript |
| `src/client/Lib/` | `StarterPlayer.StarterPlayerScripts.Client.Lib` | Folder |
| `src/client/Lib/<Name>.luau` | `StarterPlayer.StarterPlayerScripts.Client.Lib.<Name>` | ModuleScript |

Rules:
- The instance name is the file name without `.luau`.
- `Server` is a Script and `Client` is a LocalScript, each with child
  folders inside it (that's how the code finds `script.Systems` etc.).
- Don't create any other Script/LocalScript: everything else is a ModuleScript.
- Delete instances under these containers that no longer have a file.
- After syncing, start play mode and check the output for
  `[StormBottler] server started` and `[StormBottler] client started`
  with no errors, then stop play mode.

## The map (world framework)

`Lib/MapBuilder.build()` is the entry point (the updater plugin and the Map
system call it). It builds every world in `Config.WORLDS` with
`src/server/World/Builder.luau`, each in its own style pack
`src/server/World/Styles/<world.style>` (a module, or a folder with
`init.luau`). `MapBuilder.build(style)` builds only the first world's zones in
that style, to review a style (the tools use it).

Worlds: world 1 is Barometer Bay (`WeatherLab`), world 2 is Voltcliff Works
(`StormPunk`); `SkyIsles` is kept for a future world (see
`docs/world-styles.md`). Each world is built round the origin, then moved to
`world.offset` (5000 studs apart, so the 2048-stud seas never meet). Its zone
volumes, camps, gates and ground join `Map.Zones`, `Map.ResearchCamps`,
`Map.ZoneGates` and `Map.Ground.<WorldId>`; the rest of its art is in
`Map.<WorldId>` (world 1's sits straight in `Map`). Every zone names its
`world`, and `order` counts along that world's spiral. Each hub builds a
`Kit.portal` for every `ctx.portals` entry (onward to the next world, locked
until you own its `requiresBottle`, and back to the previous one); walking
into one is a server position check (`Systems/Travel`), which moves you to
that world's spawn and sets the player attribute `World`. Only world 1's
SpawnLocation spawns players; you respawn in the world you're in. Lighting
comes from world 1's style (it's global). Volts, bottles and boots carry
over.

The framework decides where things go and guarantees the gameplay contracts;
a style pack decides how everything looks:
- `World/Layout.luau`: zones sit on a spiral around the hub in `order`
  (`StylePack.layout` sets the spiral). Adding a zone = adding a
  `Config.ZONES` entry (`theme`, `width`, `depth`, `floor`); it lands in the
  next slot, the "Coming Soon" teaser moves one slot out, nothing else moves.
  `Layout.plan` errors if anything would overlap or a connector is too steep.
- `World/Builder.luau` creates `Workspace.Map.Zones.<ZoneId>` (the zone volume,
  floor + 46 studs) itself, then calls the style: atmosphere, buildBase,
  buildHub, then per zone buildZoneGround/buildConnector/buildBorder/buildGate
  and `themes[def.theme]` (or `themes.Default`), then buildTeaser. It errors if
  a world has no SpawnLocation, no part tagged `SellArea` or a missing portal.
- `World/Kit.luau`: shared building pieces (parts, struts, walkways, cables,
  signs, rocks, terrain landmasses, `Kit.sellArea`, `Kit.spawn`, `Kit.portal`).
- `World/Blocks.luau`: part-built ground (boxes, ramps, polygon discs and
  rings, strata, rocks, the sea surface). All three styles set
  `ground = "Blocks"`: their ground is SmoothPlastic parts in
  `ctx.folders.ground` (`Workspace.Map.Ground`) and they fill no terrain.
  Strikes raycast against `Map.Ground` and Terrain. Pieces that overlap on
  the same plane must share one exact colour, or they flicker.
- `World/Types.luau`: the StylePack interface and slot/zone contexts.
- `World/Styles/Blockout.luau`: the reference style pack to copy.

Research sites (`Util/ResearchSites` is the only code that finds them): every
zone gets a Research Camp from the framework (`Slot.camp` pad, box at
`Map.ResearchCamps.<ZoneId>`, `buildCamp` or `Kit.researchCamp`), and the hub
has a `ResearchOffice`-tagged box over a marked pad (`Kit.researchOffice`).
In WeatherLab the office is the Research Center: the island in the teaser
slot (`Styles/WeatherLab/Teaser.luau`), reached by a full boardwalk, with the
pad at the observatory dome's door; adding a zone moves it one slot out.
Both sit outside every zone and are walkable.

Map rules: catch floors are flat and clear (nothing above floor + 0.3 inside
a zone except its outer 2-stud band); in a Blocks style every catch floor is
covered by `Map.Ground` parts whose top is exactly at floor height; selling
is a position check against `SellArea` boxes; the spawn is outside every
zone. There is no part limit (the user's decision): don't thin or cap
detail to save parts; the build output still reports the count.

## Testing without Studio

`tools/harness/` runs the real modules in a stand-in DataModel with Lune
(https://github.com/lune-org/lune):
- `lune run tools/harness/buildmap.luau map.json [Game|<Style>]` builds the
  map with MapBuilder and fails if required pieces (zones, sell station,
  spawn, portals) are missing. It writes one file per world: `map.json` for
  world 1, `map_<WorldId>.json` for the others.
- `lune run tools/harness/test_gameplay.luau [Game|<Style>]` checks gameplay
  contracts (zone volumes, sell station detection, spawn placement, portals, and for Blocks
  styles: no terrain fills and catch floors covered at floor height).
- `python3 tools/render_map.py map.json out` draws top-down and side views
  (needs Pillow) so map layout can be reviewed as images.
- `tools/walkcheck.py map.json out` checks you can walk from spawn to every
  zone, sell area, camp and portal of that world and that catch floors are
  flat and open.
- `python3 tools/flickercheck.py map.json` fails if two visible parts with
  different colours or materials have overlapping top faces at the same
  height (they flicker in Studio). Offset one, butt them, or match colours.
- `lune run tools/harness/test_layout.luau preview.json` checks the HUD
  layout (Lib/LayoutMath) on phones, tablets, monitors and a console: every
  piece on screen, nothing overlapping or under the thumb controls; then
  `python3 tools/render_ui.py preview.json out.png` draws it per device.
  The UI is laid out in design pixels and scaled by one UIScale per screen.
- `tools/check_world.sh [Game|<Style>] [outdir]` runs all of the above,
  each world on its own: `Game` (the default) is the real game, every world
  in its own style; a style name previews the first world's zones in that
  style. Run `tools/check_world.sh Game` after any map, zone or world change.

## Conventions

- `--!strict` at the top of every file.
- Server owns all state; every client->server remote handler rate-limits and
  validates its arguments (`src/server/Systems/Shop.luau` is the example).
  Catching and selling are decided by the server with no client request.
  Selling is a position check against parts tagged `SellArea` (never Touched).
- Systems that change a profile call `Sync.markDirty(player)`.
- Remotes are listed in `src/shared/Remotes.luau` and created by the server.
- Balance numbers live in `src/shared/Config.luau`.
- Player data is only touched through `PlayerData.get(player)`.
- Checks: `stylua src` (format) and `selene src` (lint).
