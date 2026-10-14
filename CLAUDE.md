# ClickSimulator

Roblox clicker/simulator game. All game code lives in `src/` as Luau files
laid out for Rojo (`default.project.json`). Use the roblox-dev skills when
writing Luau.

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

Rules:
- The instance name is the file name without `.luau`.
- `Server` is a Script and `Client` is a LocalScript, each with child
  folders inside it (that's how the code finds `script.Systems` etc.).
- Don't create any other Script/LocalScript: everything else is a ModuleScript.
- Delete instances under these containers that no longer have a file.
- After syncing, start play mode and check the output for
  `[ClickSimulator] server started` and `[ClickSimulator] client started`
  with no errors, then stop play mode.

## Conventions

- `--!strict` at the top of every file.
- Server owns all state; every remote handler rate-limits and validates its
  arguments (`src/server/Systems/Economy.luau` is the example to copy).
- Remotes are listed in `src/shared/Remotes.luau` and created by the server.
- Balance numbers live in `src/shared/Config.luau`.
- Player data is only touched through `PlayerData.get(player)`.
- Checks: `stylua src` (format) and `selene src` (lint).
