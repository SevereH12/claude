# Prompt 21: goals for research and Ascension

Follow the rules in `docs/prompts/README.md`. **One run.**

- [ ] The goal card also tracks hiring and promoting researchers and the
  next Ascension, picks the goal closest to done, and opens the right
  panel when tapped

The goal card (top of the HUD) shows only the next bottle, boots or zone
today (`Progression.nextGoals`), and it disappears once you own the top
bottle and boots. After this prompt it always has a goal.

## Read only

- `src/shared/Util/Progression.luau`: `Goal`, `GoalKind`, `nextGoals` and
  `bottleCost`
- `src/shared/Util/Research.luau`: `maxRank`, `tierZone`, `glintsFor`,
  `canPromote`, `nextThreshold` and `rankBonus`
- `src/shared/Util/Ascension.luau`: `topTier`, `cost`, `bonusText`,
  `stars` and `canAscend`
- in `src/shared/Types.luau`: `Snapshot` (`volts`, `researchers`,
  `glints`, `ascension`)
- in `src/client/Controllers/HUD.luau`: `buildGoalCard`, `GOAL_TITLES` and
  `renderGoal`
- in `src/client/Controllers/ShopUI.luau` and `ResearchUI.luau`: the
  `open` functions, and grep for where Ascend is shown in the Shop
- `tools/harness/test_progression.luau` (the `nextGoals` tests must keep
  passing)

## Build

1. **`src/shared/Util/Goals.luau`** (pure): `Goals.list(snapshot)` and
   `Goals.pick(snapshot)`.
   - **The goals in the list**:
     - everything `Progression.nextGoals` gives today (bottle, boots,
       zone or world), unchanged
     - **hire**: the next researcher not yet hired (they're hired in
       `Config.RESEARCHERS` order), for their price in Volts. Detail:
       their perk. When it's ready: "Hire at the Research Center".
     - **promote**: for each hired researcher at the top level with a rank
       still to gain, Glints toward `glintCost[rank + 1]`
       (`Research.glintsFor`). Detail: "Rank N: works in <zone>, +X% perk".
       Only the one closest to done goes in the list. When it's ready:
       "Promote at the Research Office".
     - **ascend**: once they own the top bottle, Volts toward
       `Ascension.cost(level)`. Detail: `bonusText` for the next level and
       "resets bottle and boots". When it's ready: "Ascend in the Shop".
   - **Each goal has**: `kind`, `title`, `detail`, `current`, `target`
     and `unit` ("volts" or "glints", plus the Glint tier's zone name),
     plus `ready` (current ≥ target, and for promote, `canPromote` too).
   - **`pick`**: the goal closest to done (`current / target`, highest
     first). For Volts goals that's the same as cheapest first. Ties
     (including every ready goal at 100%) go by kind: ascend, promote,
     zone, bottle, boots, hire. So a zone still beats a bottle at the same
     price, as today.
   - **`Progression.nextGoals` stays as it is**; Goals builds on it.
2. **The goal card** (`HUD.renderGoal` uses `Goals.pick`):
   - **Titles**: add "HIRE:", "PROMOTE:" and "ASCEND:" to `GOAL_TITLES`
     ("ASCEND: LEVEL 2 ★★").
   - **The amount**: "1.2K / 5K ⚡" for Volts, or "37 / 65 ✨ Mesa" for
     Glints; when ready, the "READY!" line above.
   - **Always shown** from now on, since ascend is always there at the top.
   - **Tapping it** opens where the goal is done: the Shop (bottle, boots,
     zone, ascend; on the right tab or row if ShopUI can), or Research
     (hire, promote). Make the card a button with `UI.clickSound` and keep
     its look. Check for require cycles before HUD requires those panels;
     if there is one, pass the open functions in from `init.client`.
3. **Tests**: `tools/harness/test_goals.luau` covers:
   - a new player (the first bottle is the pick)
   - hire appears and moves on in order
   - promote uses `glintsFor`, only for researchers at the top level, and
     only the closest one
   - ascend appears only with the top bottle, and is the pick when every
     other goal is done
   - the tie order
   - the card is never empty for any bottle tier

## Done means

- stylua and selene are clean; the new test and the existing harness tests
  pass (`test_progression`, and `test_layout` for the HUD).
- Report the "check in Studio" steps:
  1. a fresh player sees the first bottle
  2. with enough Volts for a researcher, the card says HIRE and tapping
     opens Research
  3. with the top bottle, it says ASCEND and tapping opens the Shop
- Tick it, commit and push.
