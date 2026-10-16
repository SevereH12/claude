# Storm Bottler Simulator

Catch lightning in bottles on a stormy island, sell the charges at the Power
Plant for Volts, and buy bigger bottles.

## Features

- **Storm cycle**: 90s storms, 20s calm (first storm 8s after the server
  starts). The sky darkens, clouds roll in and it rains during storms.
- **Zones** with glowing force-field borders and entrance arches:
  - **Shoreline** (yellow): everyone in the circle catches. 5 Volts per charge.
  - **Mesa** (orange, up the ramp): only the closest player catches. 20 Volts per charge.
- **Strikes**: a ring and light pillar appear 1.5s before each bolt. Stand in
  the ring to catch a charge. The bottle is always in your hand.
- **Speed**: normal speed inside zones, fast everywhere else.
- **Selling**: step on the glowing SELL pad at the Power Plant.
- **Bottles**: Jar (5) → Flask (15) → Battery Pack (40) → Storm Cell (100).
- **Saving**: Volts, bottle tier and held charges save (retries, session
  locking, autosave every 60s, save on leave and shutdown).
- **HUD**: Volts, storm timer, bottle fill bar, server city meter (placeholder).

Every number (timings, values, prices, radius, walk speeds) is in
`src/shared/Config.luau`.

## Getting it into Roblox Studio

**One-time setup**

1. This GitHub repo must be **public** (the plugin downloads from it).
2. Install the updater plugin: in Studio, **Plugins** tab → **Plugins
   Folder**, then drag `StormBottlerUpdater.rbxmx` into the folder that opens.
   Restart Studio.

**Every update**

1. Open your Storm Bottler place in Studio.
2. **Plugins** tab → **Update Game**. Allow the web-access popup the first time.
3. Press **Ctrl+S** to save, then **Play**.

Build the plugin yourself with `rojo build plugin/plugin.project.json -o StormBottlerUpdater.rbxmx`.

### Testing saving in Studio

Publish the place, then Game Settings > Security > **Enable Studio Access to
API Services**. Without it the game still runs, but uses a temporary profile
that doesn't save (a warning in Output says so).

### Protecting a hand-edited map

The updater rebuilds the map each time while `Workspace.Map` has the
attribute `AutoBuilt = true`. Delete that attribute once you start editing
the map by hand and the updater will leave it alone.

## Code layout

- `src/shared` → ReplicatedStorage.Shared: Config, Types, Remotes, Net, formulas, zone geometry
- `plugin/` → the Studio updater plugin (not part of the game)
- `src/server` → ServerScriptService.Server
  - `Systems/`: PlayerData (saving), Map, StormCycle, Strikes, Bottles, Movement, Selling, Shop, Sync
  - `Lib/`: MapBuilder, RateLimit
- `src/client` → StarterPlayerScripts.Client
  - `Controllers/`: State, Storm, StrikeFX, HUD, ShopUI, ZoneBanner
  - `Lib/`: UI helpers

## Checks

- Format: `stylua src`
- Lint: `selene src`
