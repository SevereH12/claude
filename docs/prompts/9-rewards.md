# Prompt 9: daily streak, playtime gifts, and a group bonus

Follow the rules in `docs/prompts/README.md`.

**Run it twice.** Each run does the first part below that isn't ticked,
then ticks it:

- [x] Part A: timed boosts, the 7-day login streak, playtime gifts and the
  REWARDS panel
- [x] Part B: the group bonus, "reward ready" nudges and reward stats

**Needs prompt 8 part A**: `src/shared/Util/Passes.luau` must exist. If it
doesn't, stop and tell the user.

## Not included: rewards for liking the game

Roblox gives games no way to see whether a player liked the game. The only
endpoint that shows a like works only for the logged-in person viewing it.
Roblox's rules also say promo codes must not be given "in exchange for a
thumb up on your game". So there is no like reward of any kind: no button,
no codes, no like goals.

## How rewards stay worth it at every stage

- **Volts rewards are counted in charges**: a reward of N charges pays N ×
  the bolt value of the best non-premium zone the player can enter
  (`Progression.boltValue`). That's the same rule as the Volts packs, so a
  reward is worth the same playtime early or late. Put this in one pure
  function.
- **Boosts are timed effects** that reuse the pass effects:
  - `DoubleVolts`: sales pay 2x
  - `Lucky`: the Lucky Charges chance
  - `BigBottles`: 50% more capacity
- **Stacking**: a boost the player already owns as a pass still counts down,
  but it adds nothing. Say so on the card ("you own 2x Volts"), and offer
  Volts instead where that's simple.

## Part A: boosts, daily streak, playtime gifts and the panel (run 1)

### Read only

- `src/shared/Config.luau`, `Types.luau` (`Profile`, `Snapshot`) and
  `Remotes.luau`
- `src/shared/Util/Passes.luau` and, in `src/shared/Util/Progression.luau`,
  grep `boltValue`
- in `src/server/Systems/Passes.luau`, `Selling.luau`, `Strikes.luau` and
  `RemoteSell.luau`, only the lines that call `Passes.` (grep), which is
  where effects are applied
- in `src/server/Systems/PlayerData.luau`, `DEFAULT_PROFILE`, `MIGRATIONS`
  and `migrate`
- `src/server/Systems/Sync.luau` (`toSnapshot`) and `DevCommands.luau`
- in `src/client/Controllers/Menu.luau`, the `ITEMS` list
- `BoostsUI.luau`, as the panel and card pattern to copy
- in `src/client/Lib/UI.luau`, grep `toast` and `window`

### Build

1. **Timed boosts** (`src/shared/Util/Boosts.luau` pure, and
   `src/server/Systems/Boosts.luau`):
   - **Saving**: the profile keeps seconds left per boost key (a migration).
     Time only counts down while the player is in the game, so leaving never
     wastes a boost.
   - **Stacking**: granting a boost the player already has adds to its time,
     up to a 2-hour cap.
   - **Effects**: `Util/Passes` asks `Boosts` whether a boost is active, so
     every place that already applies a pass effect (selling, Remote Sell,
     capacity, luck) also applies the boost, with no new code at those call
     sites.
   - **Snapshot**: active boosts and their seconds left go in the
     `Snapshot`.
   - **HUD**: one small chip per active boost (icon and "14:32"), next to
     the existing HUD pieces.
   - If prompt 8 part C's free trial is already built, move it onto this
     timer. If it isn't, part C must use it, so add one line about that to
     part C in `docs/prompts/8-game-passes.md`.
2. **7-day login streak**:
   - **Day boundary**: a day is a UTC calendar day (`os.time() // 86400`).
     Put the decision in one pure function,
     `daily(lastClaimDay, today, streak)`, which returns whether the player
     can claim and the new streak:
     - claiming on the next day after the last claim continues the streak
     - missing a day resets it to day 1
     - after day 7 it starts again at day 1
   - **Saving**: `dailyStreak` and `lastDailyDay` go in the profile (a
     migration).
   - **Claiming**: a `ClaimDaily` remote, rate-limited; the server decides
     everything.
   - **Rewards** (`Config.DAILY_REWARDS`, suggested):

     | Day | Reward |
     | --- | --- |
     | 1 | 100 charges |
     | 2 | 2x Volts for 10 min |
     | 3 | 250 charges |
     | 4 | Lucky for 15 min |
     | 5 | 500 charges |
     | 6 | 2x Volts for 20 min |
     | 7 | 1,500 charges, 2x Volts for 30 min and Big Bottles for 30 min |

3. **Playtime gifts** (every session):
   - **Gifts** at 5, 10, 20, 30, 45 and 60 minutes into the session
     (`Config.PLAYTIME_GIFTS`, suggested):

     | Minutes | Reward |
     | --- | --- |
     | 5 | 30 charges |
     | 10 | 60 charges |
     | 20 | Lucky for 10 min |
     | 30 | 150 charges |
     | 45 | 2x Volts for 10 min |
     | 60 | 400 charges |

   - **Timing**: session time is counted on the server from the moment the
     profile loaded, and resets when the player rejoins.
   - **Claiming**: a gift is claimed by tapping it with a `ClaimGift(index)`
     remote, rate-limited. It only works if that gift's time has passed and
     it hasn't been claimed this session.
4. **REWARDS panel**: a fifth menu tile, REWARDS (🎁), opening a panel in
   the `BoostsUI` style.
   - **Top row**: the 7 day cards. Claimed days are ticked, today glows with
     a CLAIM button, and later days are dimmed. Under them, "Next reward in
     5h 12m" (the time to the next UTC day).
   - **Below**: the 6 gift cards, each counting down ("in 3:41") or showing
     CLAIM.
   - **Rewards** use the existing icon art where it fits (the bolt and
     bottle styles from `tools/store/icons`, or emoji).
   - **When claimed**: a short celebration (pop, sparks and a toast with
     what you got).
   - **Menu dot**: the REWARDS tile and the MENU button show a dot while
     anything is ready to claim.
5. **Studio testing**, Studio-only toggles in the TEST panel:
   - "Next day" moves this player's daily clock forward by one day
   - "+5 min playtime"
   - "Clear boosts"
6. **Test**: `tools/harness/test_rewards.luau` covers:
   - the `daily` rules (first claim, next day, a missed day, same day, the
     day 7 wrap)
   - gift readiness
   - the boost countdown, stacking and cap
   - reward scaling with progress

### Done means (part A)

- `stylua src` and `selene src` are clean.
- `test_rewards.luau` and the existing harness tests pass.
- `tools/check_world.sh Game` still passes.
- If the Studio MCP is connected:
  - claim day 1, press "Next day" and claim day 2: a 2x boost chip appears
    and a sale pays 2x
  - "+5 min playtime" makes the first gift claimable
- Tick part A, commit and push.

## Part B: group bonus, nudges and stats (run 2)

**Needs part A**: `src/server/Systems/Boosts.luau` must exist. If it
doesn't, stop and tell the user.

### Read only

- `src/shared/Config.luau` and `src/shared/Util/Passes.luau`
- in `src/server/Systems/Passes.luau`, the attribute and ownership pattern
- `src/server/Systems/Analytics.luau`
- the REWARDS panel controller from part A
- in `src/client/Controllers/BoostsUI.luau` (or wherever the VIP chat tag
  lives), grep `OnIncomingMessage`
- in `src/server/Systems/DevCommands.luau`, the toggle pattern

### Build

1. **Group bonus**: `Config.GROUP_ID = 7889739` ("Super Studio", the group
   that owns the game) and `Config.GROUP_BONUS = 0.10`.
   - **Checking membership**: on the server, on join, call
     `Player:IsInGroupAsync(GROUP_ID)` in a `pcall`. Set a `GroupMember`
     player attribute.
   - **The bonus**: members get +10% Volts on every sale, multiplied with
     passes and boosts, through `Util/Passes`, so Remote Sell gets it too.
     The sell popup shows "+10% group bonus".
   - **Joining from the game**: the REWARDS panel gets a group card.
     - Non-members see "Join Super Studio for +10% Volts forever" and a JOIN
       button. It calls `GroupService:PromptJoinAsync(GROUP_ID)` on the
       client, from the tap only.
     - On `Joined`, the client fires `GroupJoined`, rate-limited. The server
       checks again with `IsInGroupAsync`. Roblox may cache the old answer,
       so if it still says no, retry after 10s and 30s, and tell the player
       "Your bonus will switch on in a moment".
     - Never trust the client's word alone.
     - A join request still pending (a group that needs approval) shows "Join
       request sent".
   - **Members** see "Group bonus active: +10% Volts", and a small `[Member]`
     chat tag in the group colour, placed after `[VIP]` when someone has
     both.
2. **Nudges**, gentle and never blocking (use `UI.toast`):
   - on join, "Your daily reward is ready!" with an OPEN button, if it's
     claimable
   - when a playtime gift becomes ready, a toast once per gift
   - the group card is offered in a toast at most once per session, and only
     after the player's first sale
3. **Stats** in `Analytics.luau`:
   - custom events `DailyClaimed` (value = streak day), `PlaytimeGift`
     (value = minutes) and `GroupJoined`
   - Volts from rewards logged as an economy Source with the `TimedReward`
     transaction type (check the enum's current names)
4. **Studio testing**: a "Pretend group member" toggle, honoured only in
   Studio.
5. **Test**: extend `test_rewards.luau` with the sell multiplier for a
   group member with a pass and a boost.
6. **README**: a short "Rewards" section covering the daily streak, gifts and
   the group bonus, and how to change the group (`Config.GROUP_ID`).

### Done means (part B)

- `stylua src` and `selene src` are clean.
- `test_rewards.luau` and the existing harness tests pass.
- `tools/check_world.sh Game` still passes.
- If the Studio MCP is connected:
  - with "Pretend group member" on, a sale shows the +10% group bonus
  - the JOIN button opens Roblox's group prompt (it may say you're already
    a member)
- Tick part B, commit and push.
