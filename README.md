# Storm Bottler Simulator

Catch lightning in bottles on a stormy island, sell the charges at the Power
Plant for Volts, and buy bigger bottles.

## MVP features

- **Storm cycle**: 90s storms, 20s calm (first storm 8s after the server starts).
- **Strikes**: a glowing circle appears 1.5s before each bolt. Stand in it
  with your Bottle equipped to catch a charge.
  - **Shoreline** (yellow circles): everyone in the circle catches. 5 Volts per charge.
  - **Mesa** (orange circles, up the ramp): only the closest player catches. 20 Volts per charge.
- **Selling**: step on the yellow pad at the Power Plant.
- **Bottles**: Jar (5) → Flask (15) → Battery Pack (40) → Storm Cell (100).
- **Saving**: Volts, bottle tier and held charges save (retries, session
  locking, autosave every 60s, save on leave and shutdown).
- **HUD**: Volts, storm timer, bottle fill bar, server city meter (placeholder).

Every number (timings, values, prices, radius) is in `src/shared/Config.luau`.

## Getting it into Roblox Studio

### Option A: Claude Code on your PC (no extra tools)

1. Get the code onto your PC:
   ```
   git clone https://github.com/SevereH12/claude.git StormBottler
   cd StormBottler
   git checkout claude/sweet-planck-ea1ob4
   ```
2. Open Roblox Studio with a new **Baseplate** place and make sure the MCP
   server is on (Assistant > ... > Manage MCP Servers).
3. Run `claude` in the folder and say:
   > Sync src into my open Roblox Studio place following CLAUDE.md, then build the map and playtest it.

### Option B: Rojo

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then run `rokit install`.
2. Run `rojo serve`.
3. In Studio, install the Rojo plugin and click **Connect**.

### Making the map editable

The game builds the placeholder map itself when you press Play. To keep it
in your place (so you can see and edit it in Edit mode), paste this into
Studio's command bar (View > Command Bar) and press Enter, then save:

```lua
require(game.ServerScriptService.Server.Lib.MapBuilder).build()
```

Keep the names `Map/Zones/Shoreline`, `Map/Zones/Mesa` and
`Map/PowerPlant/SellPad` when you replace the art.

### Testing saving in Studio

Publish the place, then Game Settings > Security > **Enable Studio Access to
API Services**. Without it the game still runs, but uses a temporary profile
that doesn't save (a warning in Output says so).

## Code layout

- `src/shared` → ReplicatedStorage.Shared: Config, Types, Remotes, Net, formulas
- `src/server` → ServerScriptService.Server
  - `Systems/`: PlayerData (saving), Map, StormCycle, Strikes, Bottles, Selling, Shop, Sync
  - `Lib/`: MapBuilder, RateLimit
- `src/client` → StarterPlayerScripts.Client
  - `Controllers/`: State, Storm, StrikeFX, HUD, ShopUI
  - `Lib/`: UI helpers

## Checks

- Format: `stylua src`
- Lint: `selene src`
