# Researchers part 3: perks I (Forecaster, Rod Tech and Analyst)

Follow the rules in `docs/prompts/researchers/README.md`. Read
`design.md` sections 2 and 3, the first three bullets.

**Needs part 2**: `Research.active` in `src/server/Systems/Research.luau`
must exist. If it doesn't, stop and tell the user.

## Read only

- `src/server/Systems/Strikes.luau`
- `src/shared/Types.luau` (the strike types) and `Remotes.luau`
- `src/shared/Util/Research.luau`
- in `src/client/Controllers/StrikeFX.luau`, read only `groundRing`,
  `popup`, `onWarning`, `onLanded` and `init`. Grep for the rest.

## Build

1. **Rod Tech**: `distanceInside` takes the player's own radius:
   `STRIKE_RADIUS` plus the perk value when `Research.active(player,
   "RodTech")` returns a level. Candidates are still sorted by real
   distance, so in `Single` zones the closest player still wins.
2. **Analyst**: in `resolve`, roll the perk chance for each catcher with
   the server's `Random`. Double that charge's value and add an `assayed`
   list of UserIds to `StrikeLanded`.
3. **Forecaster**:
   - Add a `Forecast` remote and type: `{ id, zoneId, position, radius,
     warnsAt }`.
   - In `spawnStrike`, pick the position, then send the public warning
     `FORECAST_MAX_LEAD` seconds later (the top perk value). Each eligible
     owner gets their forecast `lead` seconds before the public warning.
   - Bolt timing after the public warning is unchanged.
   - Only `FireClient`, only to eligible owners.
4. **StrikeFX**:
   - **Forecast**: a faint, dashed version of the warning ring that only you
     see, which fades out when the public warning appears.
   - **Rod Tech reach**: when your Rod Tech is active, draw a faint outer
     ring showing your reach around each warning in your zone. Work out
     "active" on the client from the snapshot and `Zones.at`; it's display
     only.
   - **Analyst**: an "x2 ASSAYED" popup when you're in `assayed`.

## Done means

- `stylua src` and `selene src` are clean.
- `test_research.luau` also covers the radius and lead math, if you put
  that math in `Util/Research`.
- `tools/check_world.sh WeatherLab <scratch dir>` still passes.
- The part 3 box is ticked, and the work is committed and pushed.
