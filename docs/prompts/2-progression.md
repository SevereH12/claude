# Prompt 2: progression

Follow the rules in `docs/prompts/README.md`.

**Needs prompt 1**: `Config.BOOTS` must exist. If it doesn't, stop and tell
the user.

Make progression clear and steady. There are **two upgrade lines**,
bottles and boots, each bought in order. **Each zone needs a minimum bottle
tier to enter.** There's always a visible next goal.

## Read only

- `src/shared/Config.luau`, `Types.luau`, `Util/Formulas.luau`,
  `Util/Zones.luau`
- in `src/server/Systems/Strikes.luau`, only `resolve` and the
  candidate loop
- in `src/server/Systems/Research.luau`, grep `onPostResearcher` (or the
  post handler)
- `src/server/Systems/Movement.luau`
- in `src/server/World/Builder.luau`, the zone loop and the
  `ResearchCamps` block, as the pattern to copy
- in `src/server/World/Layout.luau`, grep `gate`
- `src/client/Controllers/HUD.luau` and `ZoneBanner.luau`

## Build

1. **More in-between tiers**, so no step feels like a wall. Indexes only
   ever grow at the end, so existing saves keep their tier.
   - Bottles: Jar 5/0, Vial 10/80, Flask 15/250, Battery Pack 40/1,500,
     Storm Cell 100/8,000. Because Vial is inserted at tier 2, migrate
     saved `bottleTier` values of 2 or more up by one.
   - Boots already have their in-between tiers from prompt 1.
2. **Zone gates**:
   - Add `requiresBottle: number` to `ZoneDef`: Shoreline 1, Mesa 3 (the
     Flask).
   - Add `src/shared/Util/Progression.luau` with:
     - `canEnter(profile, zoneDef)`: one place for every entry rule. Prompt
       3 adds Premium here.
     - `lockReason(profile, zoneDef)`, for example "Needs a Flask"
     - `nextGoals(profile)`: the next bottle, the next boots and the next
       locked zone, with their prices or requirements
3. **Server enforcement** (the real lock):
   - `Strikes` ignores players inside a zone they can't enter.
   - `Movement` moves a player standing in a locked zone back to just
     outside that zone's gate.
   - Posting a researcher to a locked zone is refused.
4. **The gate barrier**, so the lock is visible:
   - For each zone that has an entry rule (`requiresBottle` above 1, or
     premium from prompt 3), `Builder` creates `Map.ZoneGates.<ZoneId>`: a
     glowing, non-colliding barrier across the end of the connector at
     `slot.gate`, with a sign showing the requirement.
   - A new client controller makes your own copy of each barrier solid
     while you can't enter that zone. Your character is simulated on your
     client, so a local collision blocks you. When you can enter, it
     dissolves into sparks and turns green.
   - The server lock above stays the real rule.
5. **Next-goal tracker**:
   - A small HUD card under the Volts panel shows the closest next goal
     from `nextGoals` and a progress bar of Volts against its price.
   - When something unlocks, show a short banner, for example
     "MESA UNLOCKED".
   - `ZoneBanner` shows the lock reason when you walk up to a locked gate.
6. **Test**: `tools/harness/test_progression.luau` (run with `lune run`)
   covers `canEnter`, `lockReason`, `nextGoals` and the tier migration.

## Done means

- `stylua src` and `selene src` are clean.
- The new test and `test_formulas.luau` pass.
- `tools/check_world.sh WeatherLab <scratch dir>` passes. Look at the top
  render once: every zone gate has its barrier.
- Commit and push.
