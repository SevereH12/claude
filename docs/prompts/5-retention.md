# Prompt 5: retention stats on the Creator Dashboard

Follow the rules in `docs/prompts/README.md`.

**Needs prompt 2**: `src/shared/Util/Progression.luau` must exist. If it
doesn't, stop and tell the user.

Track how long players play, how far they progress before they quit, and
**where they are when they leave**. These are overall stats, shown on the
Roblox Creator Dashboard through `AnalyticsService`. We don't build our own
per-player tracking. Roblox totals the events. The only per-player thing we
save is how far each player got through onboarding, so those steps aren't
sent twice.

## Read only

- `src/server/Systems/PlayerData.luau`: `DEFAULT_PROFILE`, `MIGRATIONS`,
  `migrate`, and the `Loaded` signal
- grep the places that change progress, to add one-line calls:
  - the buy handlers in `src/server/Systems/Shop.luau`
  - the sell in `Selling.luau`
  - the catch loop in `Strikes.luau`
  - the zone check in `Movement.luau`
  - the hire handler in `Research.luau`
- `src/shared/Util/Zones.luau` and `ResearchSites.luau`, for working out
  the location
- in `src/server/Systems/Selling.luau`, grep `isAtStation`

## AnalyticsService (server only)

These are the current signatures, but check the docs before relying on
them:

```luau
LogOnboardingFunnelStepEvent(player, step, stepName, customFields?)
LogProgressionCompleteEvent(player, progressionPathName, level, levelName, customFields?)
LogCustomEvent(player, eventName, value, customFields?)
LogEconomyEvent(player, flowType, currencyType, amount, endingBalance, transactionType, itemSku, customFields?)
```

- `customFields` uses the keys `Enum.AnalyticsCustomFieldKeys.CustomField01`
  to `03`.
- Values across those three fields may make at most **8,000 unique
  combinations**, so only use small fixed sets of values.
- Wrap every call in `pcall`, so analytics can never break gameplay.

## Build

1. **`src/server/Systems/Analytics.luau` (new)**: the only file that calls
   `AnalyticsService`. Other systems call its small functions.
2. **Onboarding funnel** (each step once per player, ever):
   1. Joined
   2. Entered a zone
   3. First catch
   4. First sell
   5. First upgrade (bottle or boots)
   6. Entered a second zone
   7. Hired a researcher

   Save `onboardStep` in the profile (migration), so steps are never sent
   twice.
3. **Progression**: `LogProgressionCompleteEvent` on these paths, with the
   tier index and the item or zone name:
   - `"Bottles"` and `"Boots"` when bought
   - `"Zones"` when a bottle purchase unlocks a zone (compare
     `Progression.canEnter` before and after, so no extra saved state is
     needed)
4. **Session end**: on `PlayerRemoving`, send
   `LogCustomEvent(player, "SessionMinutes", minutes, fields)` with:
   - `CustomField01`, **where they left**. One of:
     - the zone id
     - `"Camp:<ZoneId>"`
     - `"SellStation"`
     - `"ResearchCenter"`
     - `"Hub"`
     - `"Boardwalk"`
     - `"Water"` (below the sea surface)
     - `"Respawning"` (no character)

     Work it out from `Zones.at`, `ResearchSites`, `Selling.isAtStation` and
     height, in that order. Treat the Research Office box as the Research
     Center.
   - `CustomField02`, the bottle tier as `"Bottle <n>"`
   - `CustomField03`, the storm phase (`"Storm"` or `"Calm"`)

   Also send the same fields with a `"Left"` event (value 1), so the
   dashboard can count leaves by place without averaging minutes.
5. **Economy**: `LogEconomyEvent` for Volts earned at the sell station
   (Source) and spent in the shop and on researchers (Sink), with the item
   as `itemSku`.
6. **Admin notes**: add a short "Reading the stats" section to the README:
   - where each chart lives on the Creator Dashboard (Analytics: Funnels,
     Progression, Custom events, Economy)
   - that data shows up after the place is published and played, not from
     Studio
   - that the built-in Retention and Engagement pages already show D1/D7
     retention and average session time

## Done means

- `stylua src` and `selene src` are clean.
- `tools/check_world.sh WeatherLab <scratch dir>` still passes.
- If the Studio MCP is connected: play once and check the Output has no
  analytics errors. Every call is wrapped, so look for the warnings.
- Commit and push.
