# Storm Bottler Simulator

Roblox simulator: catch lightning in bottles during storms, sell charges at
the Power Plant for Volts, buy bigger bottles. All game code lives in `src/`
as Luau files laid out for Rojo (`default.project.json`). Use the roblox-dev
skills when writing Luau.

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

## The map

`src/server/Lib/MapBuilder.luau` builds the placeholder map. The game builds
it at runtime if `Workspace.Map` is missing. To save it into the place so it
can be edited in Studio, run in Edit mode (execute_luau, or the command bar):

    require(game.ServerScriptService.Server.Lib.MapBuilder).build()

Code only depends on `Workspace.Map.Zones.<ZoneId>` (invisible strike-area
boxes) and `Workspace.Map.PowerPlant.SellPad`; everything else is art.

## Conventions

- `--!strict` at the top of every file.
- Server owns all state; every client->server remote handler rate-limits and
  validates its arguments (`src/server/Systems/Shop.luau` is the example).
  Catching and selling are decided by the server with no client request.
- Systems that change a profile call `Sync.markDirty(player)`.
- Remotes are listed in `src/shared/Remotes.luau` and created by the server.
- Balance numbers live in `src/shared/Config.luau`.
- Player data is only touched through `PlayerData.get(player)`.
- Checks: `stylua src` (format) and `selene src` (lint).
