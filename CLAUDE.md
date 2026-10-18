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

`Lib/MapBuilder.build(style?)` is the entry point (the updater plugin and the
Map system call it). It builds the world with `src/server/World/Builder.luau`
and the style pack `src/server/World/Styles/<Config.WORLD_STYLE>` (a module,
or a folder with `init.luau`). The live style is `WeatherLab`; `StormPunk` and
`SkyIsles` are kept as alternates (see `docs/world-styles.md`).

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
  there is no SpawnLocation or no part tagged `SellArea`.
- `World/Kit.luau`: shared building pieces (parts, struts, walkways, cables,
  signs, rocks, terrain landmasses, `Kit.sellArea`, `Kit.spawn`).
- `World/Blocks.luau`: part-built ground (boxes, ramps, polygon discs and
  rings, strata, rocks, the sea surface). All three styles set
  `ground = "Blocks"`: their ground is SmoothPlastic parts in
  `ctx.folders.ground` (`Workspace.Map.Ground`) and they fill no terrain.
  Strikes raycast against `Map.Ground` and Terrain. Pieces that overlap on
  the same plane must share one exact colour, or they flicker.
- `World/Types.luau`: the StylePack interface and slot/zone contexts.
- `World/Styles/Blockout.luau`: the reference style pack to copy.

Map rules: catch floors are flat and clear (nothing above floor + 0.3 inside
a zone except its outer 2-stud band); in a Blocks style every catch floor is
covered by `Map.Ground` parts whose top is exactly at floor height; selling
is a position check against `SellArea` boxes; the spawn is outside every
zone; stay under 2,500 parts.

## Testing without Studio

`tools/harness/` runs the real modules in a stand-in DataModel with Lune
(https://github.com/lune-org/lune):
- `lune run tools/harness/buildmap.luau map.json` builds the map with
  MapBuilder and fails if required pieces (zones, sell station, spawn) are missing.
- `lune run tools/harness/test_gameplay.luau` checks gameplay contracts
  (zone volumes, sell station detection, spawn placement, and for Blocks
  styles: no terrain fills and catch floors covered at floor height).
- `python3 tools/render_map.py map.json out` draws top-down and side views
  (needs Pillow) so map layout can be reviewed as images.
- `tools/walkcheck.py map.json out` checks you can walk from spawn to every
  zone and sell area and that catch floors are flat and open.
- `tools/check_world.sh <Style> [outdir]` runs all of the above for a style.
Run it after any map or zone change.

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
