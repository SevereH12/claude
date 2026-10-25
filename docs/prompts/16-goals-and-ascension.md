# Prompt 16: quests, the Storm Log and Ascension

Follow the rules in `docs/prompts/README.md`. **Run it three times**; each
run does the first unticked part, then ticks it.

- [x] Part A: stat counters, plus daily and weekly quests
- [x] Part B: the Storm Log (a collection book)
- [ ] Part C: Ascension (rebirth)

**Needs prompt 15 part A**: `Config.BOLT_TYPES` must exist. If it doesn't,
stop and tell the user.

## Part A: stats and quests (run 1)

### Read only

- in `src/server/Systems/Analytics.luau`: the function list (grep
  `^function Analytics`)
- the `Reward` type in `src/shared/Types.luau`
- `src/shared/Util/Rewards.luau`: `resolve`, `today` and `untilNextDay`
- `src/server/Systems/Rewards.luau`: how claims work
- `src/client/Controllers/RewardsUI.luau`
- in `src/server/Systems/PlayerData.luau`: `DEFAULT_PROFILE`,
  `MIGRATIONS` and `migrate`

### Build

1. **Stat counters** (`Util/Stats.luau` and `Systems/Stats.luau`): one
   place that counts things.
   - **Calls**: `Stats.add(player, key, n)`, called next to the existing
     `Analytics.*` calls, with no extra hooks.
   - **What it counts**:
     - bolts caught, overall and by type and zone
     - sales, bottles filled and Volts earned
     - playtime in minutes
     - researcher promotions and gifts sent
   - **Three sets**: lifetime, today (reset each UTC day) and this week
     (reset each Monday, UTC). All saved in the profile (a migration).
   - Prompts 16 C and 17 read these counters, so name the keys clearly.
2. **Quests**:
   - **How many**: 3 daily quests and 1 weekly quest, picked from
     `Config.QUESTS` templates.
   - **Picking**: seeded by userId plus the day (or week), so the same
     player always gets the same quests that day.
   - **Templates**:
     - catch N bolts
     - catch N bolts in a named zone they can enter
     - sell N full bottles
     - catch a golden bolt
     - earn V Volts
     - play N minutes
     - promote a researcher
   - **Scaling**: amounts grow with progress (V is minutes of their
     best-zone grinding rate, from `Util/Afk`).
   - **Rewards**: through `Rewards.resolve` (charges and boosts). The weekly
     quest is worth about 5 daily ones.
   - **Reroll**: one free reroll per day.
3. **UI**: a QUESTS tab in the REWARDS panel.
   - **Each quest card**: its progress bar, the reward, and a CLAIM button.
   - **Progress toast**: shows at 100% (through the toast queue).
   - **Menu dot**: lights up when a quest can be claimed.
4. **Tests**: `tools/harness/test_quests.luau` covers:
   - deterministic picking
   - the resets on the day and week edges
   - scaling
   - each template's completion check

## Part B: Storm Log (run 2)

### Read only

- `src/shared/Util/Stats.luau`
- `src/client/Controllers/RewardsUI.luau`
- `src/shared/Util/Passes.luau` (`sellMultiplier`)
- in `src/shared/Util/Research.luau`: the rank helpers

### Build

1. **Pages** (`Util/StormLog.luau`), all worked out from the lifetime
   stats, so there's no new saved data except claimed rewards:

   | Page | Entries |
   | --- | --- |
   | Bolts | every bolt type × every zone |
   | Places | each zone and world visited |
   | Team | each researcher at each rank |
   | Weather | Supercell and each event seen |

2. **Rewards**:
   - **Per row**: completing a row (for example, all bolt types in Mesa)
     gives a one-time reward to claim (charges or a boost).
   - **Per page**: each fully completed page gives +2% Volts for good,
     through `Passes.sellMultiplier` (up to +8%).
3. **UI**: a LOG tab in the REWARDS panel.
   - **Entries** are a grid: found entries show their icon, and missing ones
     show a "?" silhouette with a hint.
   - **Progress**: shown per page.
4. **Tests**: `test_quests.luau` also covers row and page completion, and
   the bonus cap.

## Part C: Ascension (run 3)

### Read only

- in `src/server/Systems/PlayerData.luau`: `DEFAULT_PROFILE` and
  `MIGRATIONS`
- `src/shared/Util/Passes.luau` (`sellMultiplier`)
- `src/shared/Util/Progression.luau`
- in `src/server/Systems/Travel.luau`: the function that moves a player to
  a world's spawn
- in `src/server/Systems/Shop.luau`: the remote pattern

### Build

1. **Rules** (`Config.ASCENSION`):
   - **Requirement**: owning the top bottle, plus Volts equal to
     `baseCost × (level + 1)` (start with `baseCost` at 10M).
   - **What resets**: Volts, bottle, boots, bottle contents and the tank go
     back to the starting values, and the player moves to Barometer Bay's
     spawn.
   - **What stays**: passes, gifts, researchers (with their ranks and
     levels), Glints, quests, Log progress, settings and rewards streaks.
   - **The reward**: +50% Volts for good per Ascension level, added
     (level 3 = +150%), through `Passes.sellMultiplier`. So AFK, quests and
     everything else follow automatically.
2. **Ascending**: an `Ascend` remote, rate-limited.
   - **Checks**: the server checks the requirements, then asks the client to
     confirm on a second step. Use a server-made token that expires in 30 s.
   - **The confirm screen** lists exactly what resets and what stays.
3. **Showing it**:
   - an ASCEND button in the Shop when the player is ready
   - Ascension stars on the name tag and in the stats
   - a big celebration (Celebrate, plus the level-up sound)
4. **Tests**: `test_quests.luau` also covers the requirements, what
   resets and stays, and the multiplier stacking with passes, events and
   the Log.

## Done means (every part)

- stylua and selene are clean; the new tests and the existing harness tests
  pass.
- `tools/check_world.sh Game` still passes.
- In Studio (if the MCP is connected), try that part's feature once, using
  the TEST buttons where needed. Add "complete quest", "+Log entry" and
  "ready to ascend" TEST buttons (Studio only).
- Tick the part, commit and push.
