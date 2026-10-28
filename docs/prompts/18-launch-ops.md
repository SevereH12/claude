# Prompt 18: launch and operations

Follow the rules in `docs/prompts/README.md`. **Run it twice**; each run
does the first unticked part, then ticks it.

- [x] Part A (in-game): admin tools, error reporting, and streaming and
  memory
- [x] Part B (outside the game): data deletion, store page art, and private
  servers

## Part A: admin tools, error reporting, streaming (run 1)

### Read only

- `src/server/Systems/DevCommands.luau` (the owner check and the TEST
  panel)
- in `src/server/Systems/PlayerData.luau`: `get`, the save functions, and
  the store name
- in `src/server/Systems/Analytics.luau`: grep `LogCustomEvent`
- in `src/server/Lib/MapBuilder.luau` and `src/server/World/Builder.luau`:
  where the map root and Persistent models are made
- grep `src/client` for `WaitForChild(` and `workspace.Map`, to find code
  that assumes map parts exist on the client

### Build

1. **Admin panel**, for admins only.
   - **Who's an admin**: the group owner, plus group ranks at or above
     `Config.ADMIN_RANK` (`Player:GetRankInGroupAsync`), and Studio. The
     TEST panel's tools move into it; keep TEST for Studio-only test
     buttons.
   - **Actions**:
     - kick (with a reason)
     - ban and unban with `Players:BanAsync` and `UnbanAsync` (duration
       and reason)
     - give Volts or a boost
     - reset a player's profile (with a confirm)
     - look up any player's saved data by username, read-only
   - **The `Admin` remote**: rate-limited, checked on the server for every
     call.
   - **Logging**: every admin action goes to an `AdminLog` DataStore,
     covering who, what, when and the target.
2. **Error reporting**:
   - **Server errors**: `ScriptContext.Error`.
   - **Client errors**: `ScriptContext.Error` too, sent through a
     rate-limited `ClientError` remote (5 a minute per player, 300 a minute
     per server).
   - **Grouping**: errors are grouped by a short fingerprint (script plus
     the first line of the message, with numbers stripped).
   - **Reporting**: each new fingerprint becomes a custom analytics event
     `Error` (`CustomField01` = the fingerprint, `CustomField02` = server or
     client), at most once per fingerprint per server.
   - **The admin panel** shows this server's 20 most recent errors.
3. **Streaming** (lower memory on phones):
   - **Turning it on**: `MapBuilder` turns on `Workspace.StreamingEnabled`
     with a sensible target radius. It runs in the updater plugin, which is
     allowed to set it; check that it is.
   - **What must always load**: anything gameplay needs everywhere is made
     Persistent: zone volumes (already), sell areas, research camps and
     offices, portals, gates and the AFK box.
   - **Fixing the client**: client code that assumes far-away parts exist
     has to wait for them with a timeout, or work without them. Before a
     teleport or portal trip, call `Player:RequestStreamAroundAsync` on the
     arrival spot.
4. **Tests**:
   - `tools/harness/test_ops.luau` covers the admin rank check and the
     error fingerprints.
   - `tools/check_world.sh Game` still passes.

## Part B: data deletion, store art, private servers (run 2)

These are tools and steps outside the game. They use the Open Cloud key
that the network adds for `apis.roblox.com`, the same as `tools/store/`.

### Read only

- `tools/store/create_store.py` (the Open Cloud call pattern)
- grep `src/server` for `GetDataStore(` and `GetOrderedDataStore(`, to list
  every store and its key formats
- `tools/store/make_icons.py` (art style and the font)
- `tools/render_view.py` (map views)

### Build

1. **Data deletion**: `tools/ops/erase_user.py <userId> [--dry-run]`.
   - **What it deletes**: that user's entries in every DataStore and
     OrderedDataStore the game uses (player data, gift inbox, leaderboards,
     and so on), through the Open Cloud DataStores API, printing what it
     deleted.
   - **Keeping it complete**: a check fails if the code uses a DataStore the
     script doesn't know about.
   - **README section "Data deletion requests"**:
     - Roblox sends right-to-erasure requests to a webhook you set up on the
       Creator Dashboard (or as a notice)
     - when one arrives, run this script (or ask Claude to) within the
       deadline Roblox gives
2. **Store page art**: `tools/store/make_store_art.py` makes:
   - a **512×512 game icon**: a glowing bottle full of lightning on the
     storm-navy background, with the "STORM BOTTLER" wordmark in Luckiest
     Guy
   - **three 1920×1080 thumbnails**:
     1. a Barometer Bay storm view, made with `render_view.py` from a nice
        angle, with title text
     2. a collage of the three worlds
     3. a "catch, sell, upgrade" strip using the store icons

   Show them to the user before uploading.
   - **Uploading**: if Open Cloud supports setting the experience icon or
     thumbnails with this key, upload them. Otherwise, tell the user where
     to upload them on the Creator Dashboard.
3. **Private servers**: ask the user for a price (suggest 100 Robux a
   month).
   - **Turning them on**: set `privateServerPriceRobux` with
     `PATCH /cloud/v2/universes/{id}` (universe 10772352394). If the key
     can't, tell the user where to turn them on.
   - **In the game**: private-server owners (`game.PrivateServerOwnerId`)
     get a small "Owner" tag. No other code is needed.

## Done means (every part)

- stylua and selene are clean; the tests and existing harness tests pass.
- Part A: in Studio (if the MCP is connected), the admin panel works for
  the owner, a forced test error shows in it, and play mode runs with
  streaming on and no errors.
- Part B:
  - `erase_user.py --dry-run` on a test user lists the right keys
  - the art is shown to the user
  - private servers are on, or the user knows how to turn them on
- Tick the part, commit and push.
