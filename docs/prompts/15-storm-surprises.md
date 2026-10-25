# Prompt 15: rare bolts, weather events and server goals

Follow the rules in `docs/prompts/README.md`. **Run it twice**; each run
does the first unticked part, then ticks it.

- [x] Part A: rare bolt types, Supercell storms and scheduled events
- [ ] Part B: the server goal meter and Server Surge

Everything is decided by the server. Clients only draw it.

## Part A: rare bolts, Supercells and events (run 1)

### Read only

- in `src/server/Systems/Strikes.luau`: `spawnStrike`, `resolve` and
  `spawnFor`
- the strike types in `src/shared/Types.luau`
- in `src/server/Systems/StormCycle.luau`: the loop
- in `src/client/Controllers/StrikeFX.luau`: `onWarning`, `onLanded`,
  `bolt` and `popup`
- in `src/client/Controllers/Storm.luau`: the sky and lighting tweens
- `src/shared/Util/Passes.luau` (`sellMultiplier`) and
  `src/client/Lib/Sfx.luau` (play only; no new sounds)

### Build

1. **Rare bolt types** in `Config.BOLT_TYPES`:

   | Type | Chance per strike | Value | How you catch it |
   | --- | --- | --- | --- |
   | Golden | 2% | ×10 | a normal ring |
   | Rainbow | 0.4% | ×25, plus 5 min of a random boost | a normal ring |
   | Ball lightning | 1% | ×5 | an orb that drifts across the catch area for 8 s, and the first player to touch it catches it |

   - **Picking the type**: the server picks it when it spawns the strike and
     sends it in `StrikeWarning`, so a gold ring shows before the bolt
     lands and players race for it.
   - **Value**: the type multiplies that catch's value. Luck and assay
     still stack on top, and the bottle space used stays the same.
   - **Ball lightning** is server-run: a position check every 0.2 s over a
     simple drifting path. Clients draw the orb from its path and start
     time.
   - **Celebrating**: gold, rainbow and orb visuals and popups ("GOLDEN
     ×10!"). A Rainbow catch gets a chat line for the whole server.
2. **Supercell**: about every 60 minutes (`Config.SUPERCELL`: interval,
   ±15 min jitter, 3 min long), a storm turns into a Supercell.
   - **What changes**: twice as many strikes, golden chance ×5, a darker
     purple sky, and a banner.
   - **Warning**: a countdown appears 30 s before, so players can get into
     a zone.
3. **Scheduled events** in `Config.EVENTS`: a list of
   `{ name, startUtc, endUtc, multiplier, banner }`.
   - **Example**: a recurring weekend "Double Volts Weekend", running Sat
     00:00 to Sun 23:59 UTC.
   - **Effect**: while an event is on, sales multiply through
     `Passes.sellMultiplier`, so AFK, Remote Sell and everything else follow
     automatically. A HUD chip shows the event and its time left.
4. **Tests** in a pure `Util/Weather.luau`, with
   `tools/harness/test_weather.luau` covering:
   - the type picker's odds over 100k rolls
   - Supercell timing
   - event windows (including the weekly repeat and the edges)
   - the sale multiplier with an event on

### Done means (part A)

- stylua and selene are clean; the new test and the existing harness tests
  pass.
- `tools/check_world.sh Game` still passes.
- In Studio (if the MCP is connected), a TEST button "Force golden bolt"
  shows the gold ring and pays ×10.
- Tick part A, commit and push.

## Part B: server goal and Server Surge (run 2)

### Read only

- `src/server/Systems/Boosts.luau` (`startStorm`, `stormOn`) and
  `src/shared/Util/Boosts.luau`
- `src/shared/Util/Afk.luau`: the grinding-rate function
- in `src/server/Systems/Selling.luau`, where a sale is paid (and grep
  `RemoteSell`)
- in `src/client/Controllers/HUD.luau`, the top bar layout
- in `src/client/Lib/LayoutMath.luau`, how HUD pieces get placed

### Build

1. **Filling the meter**: every Volt sold in this server (including Remote
   Sell, but not AFK) fills one server meter.
   - **Goal size**: the sum of each present player's grinding rate (from
     `Util/Afk`) × `Config.SERVER_GOAL.minutes` (15). So a full server of
     late-game players and a small early-game server both take about the
     same time.
   - **When players change**: recompute the goal as players join and leave.
   - **Never stuck**: the goal never drops below what's already filled
     plus 10%.
2. **Server Surge**: filling the meter starts a Surge, 10 minutes of 2x
   Volts for everyone. Reuse the Server Storm machinery with no buyer,
   labelled "SERVER SURGE", and stack it with any running Storm.
   - **The next goal** is 1.5× bigger, and the size resets each hour.
3. **HUD**: a slim meter on the top bar ("⚡ Server goal 62%"). Tapping it
   shows who contributed most this round (the top 3), and it fits the
   layout rules (add it to `LayoutMath`, and `test_layout.luau` must pass).
4. **Tests**: add the goal-size maths and the "never stuck" rule to
   `test_weather.luau`.

### Done means (part B)

- stylua and selene are clean; the harness tests pass, including
  `test_layout.luau`.
- In Studio (if the MCP is connected), selling with the TEST Volts fills
  the meter, and filling it starts a Surge.
- Tick part B, commit and push.
