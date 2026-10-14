# ClickSimulator

A Roblox clicker simulator: click to earn coins, buy upgrades, rebirth for a
permanent multiplier. Progress saves with session-locked DataStores.

## What's in the game so far

- **Click button**: each click earns coins (server caps at 15 clicks/sec).
- **Upgrades shop**: Click Power (+1 per click), Auto Clicker (+1/sec),
  Golden Hands (+10% to everything). Prices grow each level.
- **Rebirth**: reset coins and upgrades for +50% coins forever.
- **Leaderboard**: Coins and Rebirths.
- **Saving**: autosave every 60s, on leave and on server shutdown.

All balance numbers are in `src/shared/Config.luau`.

## Getting it into Roblox Studio

### Option A: Claude Code on your PC (no extra tools)

1. Get the code onto your PC:
   ```
   git clone https://github.com/SevereH12/claude.git ClickSimulator
   cd ClickSimulator
   git checkout claude/sweet-planck-ea1ob4
   ```
2. Open Roblox Studio with a Baseplate place and make sure the MCP server is
   on (Assistant > ... > Manage MCP Servers).
3. Run `claude` in the folder and say:
   > Sync src into my open Roblox Studio place following CLAUDE.md, then playtest it.

### Option B: Rojo

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then run `rokit install`.
2. Run `rojo serve`.
3. In Studio, install the Rojo plugin and click **Connect**.

### To test saving in Studio

Game Settings > Security > **Enable Studio Access to API Services** (the
place must be published first). Without it, the game still runs but uses a
temporary profile that doesn't save.

## Code layout

- `src/shared` → ReplicatedStorage.Shared: types, config, formulas, remotes
- `src/server` → ServerScriptService.Server: PlayerData (saving), Economy
- `src/client` → StarterPlayerScripts.Client: State, HUD (all the UI)

## Checks

- Format: `stylua src`
- Lint: `selene src`
