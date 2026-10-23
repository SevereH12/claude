# Prompt 12: the AFK Lounge (earn Volts overnight, never get kicked)

Follow the rules in `docs/prompts/README.md`.

**Run it twice.** Each run does the first part below that isn't ticked,
then ticks it:

- [ ] Part A: the AFK rate maths, the lounge on the map, earning, and the
  AFK screen
- [ ] Part B: never getting kicked for being idle (with a backup), the
  Teleport entry, and stats

**Needs prompts 8, 9 and 10**: `src/shared/Util/Passes.luau` (with
`withBoosts` and `sellMultiplier`) and `src/shared/Util/Boosts.luau` must
exist. If they don't, stop and tell the user.

## The rule

A player standing in the AFK Lounge earns Volts at a steady rate equal to
**10% of what they'd earn grinding** (90% less), worked out from **their
best zone**, their bottle, their boots, **and every pass and running
boost**. AFK is always worth it, and always clearly worse than playing.

## The maths (one pure function: `src/shared/Util/Afk.luau`)

`Afk.rate(progress, effects)` returns Volts per second plus a breakdown for
the UI. `effects` is the exact set the sale path uses:
`Passes.withBoosts(owned, boosts)` plus the group bonus and a running Server
Storm. Find how `Selling` builds it and reuse that; never rebuild it
differently.

| Step | Formula |
| --- | --- |
| Best zone | `zone = Progression.bestZone(progress)` (non-premium, the highest `chargeValue` the bottle opens) |
| Bottle size | `capacity = Passes.capacity(Formulas.capacity(bottleTier), effects)`, so Big Bottles counts |
| Strikes to fill | `strikes = ceil(capacity / chargeSize)` (the zone's `chargeSize`, via `Progression.chargeSize`) |
| What one bag sells for | `bag = capacity / chargeSize × boltValue × Passes.sellMultiplier(effects) × (1 + Passes.luckChance(effects))`, so 2x Volts, VIP, the group bonus and Server Storm multiply, and Lucky adds its expected 15% |
| Boot speed | `speed = Formulas.walkSpeed(true, bootTier)` (in-zone speed: boots count; Jet Boots only change speed outside zones, so they don't) |
| Reach | `reach = STRIKE_RADIUS + speed × WARNING_TIME`: how far away a warning ring can be and still be reached |
| Chance a strike is reachable | `p = min(1, π × reach² / strikeArea)`, where `strikeArea = (width − 2 × (STRIKE_RADIUS + 2)) × (depth − 2 × (STRIKE_RADIUS + 2))`, the rectangle `Strikes` picks strike centres from |
| Time to fill a bag | `fill = strikes × strikeInterval / p × (STORM_DURATION + CALM_DURATION) / STORM_DURATION` (strikes only fall during storms) |
| Grinding rate | `grind = bag / fill` |
| AFK rate | `afk = grind × Config.AFK.rateFraction` (0.10) |

Notes:
- "Closest catcher wins" zones are counted as if the player were alone
  there.
- The time spent walking to sell isn't counted, which follows the rule as
  given.
- Researcher perks are left out.
- Write each assumption in a comment above the function.

**Expected results.** `tools/harness/test_afk.luau` must reproduce these
(Volts per hour, within 1%). They use the current Config, a typical bottle
and boots for each stage, and passes as named. "All passes" means 2x Volts,
VIP, Lucky Charges and Big Bottles.

| Best zone | Boots | Bottle | No passes | 2x Volts | All passes | All + group | + Server Storm |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Shoreline | +0 | Jar | 575 | 1,149 | 1,454 | 1,600 | 3,199 |
| Mesa | +3 | Flask | 3,017 | 6,035 | 8,143 | 8,957 | 17,914 |
| Generator Yard | +4 | Storm Cell | 10,830 | 21,660 | 27,948 | 30,743 | 61,485 |
| Thunderhead Mesa | +7 | Dynamo Drum | 96,724 | 193,449 | 243,630 | 267,993 | 535,986 |
| Ember Mesa | +10 | Storm Core | 2,447,204 | 4,894,408 | 6,191,426 | 6,810,568 | 13,621,137 |

If Config numbers have changed since this table was written, recompute it
with the formula and say so, rather than forcing the old numbers.

## Part A: maths, lounge, earning, AFK screen (run 1)

### Read only

- `src/shared/Config.luau`: `ZONES`, `BOTTLES`, `BOOTS`,
  `STRIKE_RADIUS`, `WARNING_TIME`, `STORM_DURATION`, `CALM_DURATION`,
  `GROUP_BONUS` and `SERVER_STORM`
- `src/shared/Util/Passes.luau`, `Boosts.luau` and `Formulas.luau`; in
  `Progression.luau`, `bestZone`, `boltValue` and `chargeSize`
- `src/server/Systems/Selling.luau`, for how the sale's effects set and
  multiplier are built (copy that path), and the position-check loop
- in `src/server/World/Kit.luau`, grep `sellArea` and `sign`
- in `src/server/World/Styles/WeatherLab/Hub.luau`, grep for where the
  village ring places buildings (`village`) and the corridor helpers
- in `src/server/Systems/PlayerData.luau`, grep `totalVolts`; in
  `Analytics.luau`, grep `sold`

### Build

1. **`Config.AFK`**:
   - `rateFraction = 0.10`: 90% less than grinding (the user's choice; the
     formula's grinding rate is already higher than real play)
   - `enterSeconds = 10`: seconds inside before AFK starts
   - `payEverySeconds = 60`
   - `recomputeSeconds = 15`
2. **`Util/Afk.luau`** as above, plus `tools/harness/test_afk.luau`
   covering:
   - the table
   - the `p` cap at 1
   - picking the best zone
   - Big Bottles changing only the rounding of the strike count
   - an expiring boost lowering the rate
3. **The lounge**:
   - **Kit**: `Kit.afkZone(parent, pad)`, modelled on `Kit.sellArea`: an
     invisible box tagged `AfkZone` over a clearly marked area.
   - **Placement**: in the WeatherLab hub, a cosy "Night Shift Lounge"
     building in the village ring. It goes in a free gap between boardwalk
     corridors, the same way the cottages are placed, so it never blocks a
     current or future zone path.
   - **Look**:
     - a covered pavilion with hammocks and benches, warm lanterns
     - a tall lightning rod feeding a glass tank that pulses slowly
     - a sign: "AFK LOUNGE: earn Volts while you rest"
   - **Checks**: it must be outside every zone and sell area, and reachable
     on foot. Add both to `tools/harness/test_gameplay.luau`, and make
     `walkcheck.py` reach `AfkZone` boxes the same way it reaches sell
     areas. Check the sign with `tools/render_view.py --signs`.
4. **Earning** (`src/server/Systems/Afk.luau`):
   - **Starting**: a position check every second, like `Selling`. After
     `enterSeconds` inside, the player is AFK.
   - **The rate**: recomputed every `recomputeSeconds` with `Afk.rate`, so a
     boost running out, a purchase or a Server Storm changes it straight
     away.
   - **Paying**: whole Volts every `payEverySeconds`, with the fraction
     carried over, added to `volts` and `totalVolts`, then
     `Sync.markDirty`. Log it as an economy Source `"AFK"`.
   - **Boosts while AFK**: they keep counting down and keep counting in the
     rate; they're being used. The AFK screen says so.
   - **Stopping**: leaving the box stops AFK straight away.
   - **Snapshot**: AFK state, the rate and Volts earned this AFK session go
     in it.
5. **The AFK screen** (client): while AFK, a calm full-width card.
   - **Headline**: "💤 AFK: +12,345 Volts/hour", with "10% of your best
     grinding (Ember Mesa)" under it.
   - **Earned so far**: Volts earned, and time AFK.
   - **"How is this worked out?"**, which expands the breakdown: best zone,
     bottle and capacity, strikes to fill, fill time, bag value, and each
     multiplier applied with its value (2x Volts ×2, VIP ×1.1, Group ×1.1,
     Server Storm ×2, Lucky +15%, Big Bottles). If a boost is running, a line
     says "2x Volts boost: 12:31 left (counts down while AFK)".
   - Use `UI` helpers and the device layout. Nothing covers the menu
     button.

### Done means (part A)

- `stylua src` and `selene src` are clean.
- `test_afk.luau` and the existing harness tests pass.
- `tools/check_world.sh Game` passes, including the walkcheck to the lounge
  and the sign check.
- If the Studio MCP is connected:
  - stand in the lounge for 70 s and get paid once, at the shown rate
  - turn on a pretend pass, and the rate jumps within 15 s
- Tick part A, commit and push.

## Part B: never kicked for idling, Teleport entry, stats (run 2)

**Needs part A**: `src/server/Systems/Afk.luau` must exist. If it doesn't,
stop and tell the user.

### Read only

- `src/server/Systems/Afk.luau` and the AFK screen controller
- `src/server/Systems/Travel.luau` (how players are moved) and
  `src/client/Controllers/TeleportUI.luau`
- in `src/server/Systems/PlayerData.luau`, the save and release on leave
- `src/server/Systems/Analytics.luau`
- in `src/server/Systems/DevCommands.luau`, the TEST toggle pattern

### Build

1. **Stay connected**: Roblox disconnects players after about 20 minutes
   without input.
   - **What to do**: while AFK, the client listens to
     `Players.LocalPlayer.Idled` and, in `pcall`, calls
     `VirtualUser:CaptureController()` then
     `VirtualUser:ClickButton2(Vector2.new())`. This is the usual
     AFK-lounge method.
   - **Scope**: only while in the lounge; anywhere else the normal idle kick
     stays.
   - **If the call errors**, log it once and use the backup below.
2. **The backup**: if the client reports idle time of 17 minutes or more
   while AFK (from `Idled`'s argument), or VirtualUser failed, send
   `AfkRejoin`. It's rate-limited and only works while the server agrees the
   player is AFK.
   - **Moving them**: the server saves the profile, then moves the player to
     a fresh server of the same place with `TeleportService:TeleportAsync`,
     passing teleport data `{ afk = true }`.
   - **Arriving**: on arrival with `afk = true`, put them straight back in
     the lounge, and AFK resumes after `enterSeconds`.
   - **Locking**: profile session locking already waits for the old
     server's save.
   - **Failure**: if the teleport fails, retry once after 30 s; after that,
     let Roblox's kick happen and log it.
3. **Teleport panel**: an "AFK Lounge" destination in the Teleport panel.
   It goes to the lounge pad in world 1 with the same server check and
   cooldown as the world entries.
4. **Stats** in `Analytics.luau`:
   - custom events `AfkMinutes` (value = minutes, sent when AFK ends or the
     player leaves) and `AfkRejoin` (value 1)
   - the economy Source `"AFK"` from part A
5. **Studio testing**: a "Simulate idle 17 min" TEST button (Studio only)
   that runs the idle handler, so the VirtualUser path and the backup can
   both be checked without waiting.
6. **README**: a short "AFK Lounge" section covering the 10% rule, what
   counts (passes, boosts, the group, Server Storm), and
   `Config.AFK.rateFraction` for tuning.

### Done means (part B)

- `stylua src` and `selene src` are clean.
- The existing harness tests pass.
- `tools/check_world.sh Game` still passes.
- If the Studio MCP is connected: "Simulate idle 17 min" while AFK shows
  the VirtualUser path working, or the backup trying a teleport (teleports
  don't work in Studio; check the log line). The Teleport panel's "AFK
  Lounge" works.
- Tick part B, commit and push.
