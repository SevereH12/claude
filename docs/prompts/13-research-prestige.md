# Prompt 13: promote (prestige) researchers to work in new zones

Follow the rules in `docs/prompts/README.md`.

**Run it twice.** Each run does the first part below that isn't ticked,
then ticks it:

- [x] Part A: ranks, promotion rules, Glints, saved data and the balance
  calculator
- [ ] Part B: the Promote screen, rank stars, the Glint counter and the
  promotion moment

## The design (the user's choices)

- **Ranks**: every researcher has a **rank**, starting at 0. A researcher
  can only be posted to zones whose **tier** is at or below their rank.
- **Tiers**: a zone's tier is the position of its `requiresBottle` among
  the distinct `requiresBottle` values of the non-premium zones, counting
  from 0:

  | Tier | Zones |
  | --- | --- |
  | 0 | Shoreline (and Aurora Reef, which needs the Jar) |
  | 1 | Mesa |
  | 2 | Generator Yard |
  | 3 | Tidewire Beach |
  | 4 | Thunderhead Mesa and Rune Spire (same bottle) |
  | 5 | Cloudshore |
  | 6 | Ember Mesa |

  The tiers are worked out from Config, so a new zone gets a tier by
  itself.
- **Promotion to rank r needs both:**
  1. **Level 5 at their current rank.** Data per level grows with rank (the
     table below).
  2. **Glints**: a new currency. Each bolt you catch yourself (normal,
     balloon or tank) gives 1 Glint of that zone's tier. Promotion to rank
     r spends the rank's Glint cost from Glints of tier r **or higher**,
     lowest tier first. So you have to play the new zone to bring your team
     in, and Glints from better zones also pay for older ranks.
- **What a promotion does**: the researcher goes back to **level 1 with 0
  data** and gains a rank.
- **What a rank gives**: it lets them work in the next tier, and makes their
  perk **10% stronger for good** (+60% at rank 6). For "lower is better"
  perks, like the Storm Chaser's seconds between balloon bolts, divide by
  the bonus instead of multiplying. Each rank also adds a gold star to their
  name tag.
- **New hires start at rank 0** (Shoreline), even late in the game. That's
  deliberately hard: a late Storm Chaser hire has to climb every rank. Lab
  Grant's 2x data helps.
- **Promotions happen at the Research Office**, like hiring.

## The maths: everyone is ready about halfway through a zone

These targets come from the game's own numbers.

- **Time spent in each zone**: the Volts needed for the next zone's bottle,
  divided by a realistic grinding rate. That's the AFK prompt's formula,
  with players earning 60% of it because of selling trips and missed rings,
  and typical boots per stage.
- **Data**: while you play a new zone, your team can't follow you yet, so
  they keep training in your previous zone. They get +1 data per strike
  there, or +3 while you were still there catching.
- **The data target** for each promotion is what they earn from their last
  promotion (halfway through the previous zone) to halfway through the new
  one.
- **The Glint target** is the catches you make in the new zone's first
  half, split across the 5 researchers.

| Promotion | Unlocks | Time in that zone | Data for level 5 at the rank below | Glints per promotion |
| --- | --- | --- | --- | --- |
| Rank 1 | Mesa | 30 min | 1,150 (1.15× today's 1,000) | 45 |
| Rank 2 | Generator Yard | 36 min | 1,800 (1.8×) | 65 |
| Rank 3 | Tidewire Beach | 44 min | 2,850 (2.85×) | 130 |
| Rank 4 | Thunderhead Mesa, Rune Spire | 34 min | 3,700 (3.7×) | 85 |
| Rank 5 | Cloudshore | 72 min | 3,700 (3.7×) | 165 |
| Rank 6 | Ember Mesa | about 20 min (end game) | 4,500 (4.5×) | 50 |

Level thresholds within a rank are today's `RESEARCH_LEVELS`
`{0, 40, 150, 400, 1000}` times that rank's scale, so level 5 lands on the
table's data. At rank 6 (the top), keep the 4.5× scale for levelling.

## Part A: rules, Glints, data, calculator (run 1)

### Read only

- `src/shared/Config.luau`: `RESEARCHERS`, `RESEARCH_*`, `ZONES`,
  `BOTTLES`, `BOOTS` and `FORECAST_MAX_LEAD`
- `src/shared/Util/Research.luau` and `Progression.luau`, and the
  `Researchers` part of `Types.luau`
- `src/server/Systems/Research.luau`
- in `src/server/Systems/Strikes.luau`, the catch loop only (grep `catchers`)
- in `src/server/Systems/PlayerData.luau`, `DEFAULT_PROFILE`, `MIGRATIONS`
  and `migrate`
- `tools/harness/test_research.luau`

### Build

1. **`tools/balance/prestige.py`** recomputes the table above from Config.
   - **Settings**: the 60% efficiency and the boots per stage are named
     constants at the top.
   - **Output**: it prints the data scale and Glint cost for each rank,
     suggests rounded values, and checks that Config matches them within
     10%.
   - **Future zones**: run it whenever zones, bottles or strike settings
     change. Mention it in the README.
2. **`Config.RESEARCH_PRESTIGE`**:
   - `dataScale = { 1.15, 1.8, 2.85, 3.7, 3.7, 4.5, 4.5 }`, indexed by
     current rank + 1
   - `glintCost = { 45, 65, 130, 85, 165, 50 }`, indexed by the target rank
   - `perkBonusPerRank = 0.10`
3. **Pure maths in `Util/Research.luau`**:
   - `zoneTier(zone)` and `maxRank()`
   - `levelFor(data, rank)` and `nextThreshold(level, rank)`
   - `perkValue(roleId, level, rank)`, with the rank bonus and the
     lower-is-better rule
   - `canPost(rank, zone)`
   - `canPromote(save, glints)`, which returns ok and a reason
   - `spendGlints(glints, rank)`, lowest eligible tier first
4. **Saved data** (migration):
   - each `ResearcherSave` gets `rank`
   - the profile gets `glints`, a count per tier
   - **Existing saves**: each researcher's rank = the tier of the zone they're
     posted to now (0 if at the Office), so nothing gets kicked out of its
     zone. Keep their data, and recompute their level with
     `max(old level, levelFor(data, rank))`.
5. **Server**:
   - **Posting**: `PostResearcher` refuses zones above the researcher's
     rank, with the reason "Needs rank 3".
   - **Glints**: catches add Glints of the zone's tier, through the catch
     loop's existing hook.
   - **`PromoteResearcher(roleId)`**:
     - rate-limited
     - only at the Research Office (the same check as hiring)
     - checks `canPromote`, spends the Glints, then sets level 1, data 0,
       rank + 1
     - `Sync.markDirty`
   - **The Snapshot** carries ranks and Glints.
6. **The Forecaster**: rank bonuses can make the Forecaster's lead longer
   than `FORECAST_MAX_LEAD`. Raise `FORECAST_MAX_LEAD` to the top value
   (1.2 s × 1.6 = 1.92 s). This only makes the public warning wait
   slightly longer after the server picks a spot, which nobody sees.
7. **Studio testing**: TEST-panel buttons (Studio only) for "+500 data to
   all researchers" and "+100 Glints (current tier)".
8. **Tests** in `test_research.luau`:
   - zone tiers come from Config
   - level thresholds per rank
   - the perk bonus, including the lower-is-better case
   - `canPost`
   - `canPromote`, with each refusal reason
   - Glint spending, lowest eligible tier first and using higher tiers
   - the migration

### Done means (part A)

- `stylua src` and `selene src` are clean.
- `python3 tools/balance/prestige.py` passes its check.
- `test_research.luau` and the other harness tests pass.
- `tools/check_world.sh Game` still passes.
- Tick part A, commit and push.

## Part B: Promote screen, stars, Glints, the promotion moment (run 2)

**Needs part A**: `PromoteResearcher` must be in `src/shared/Remotes.luau`.
If it isn't, stop and tell the user.

### Read only

- `src/client/Controllers/ResearchUI.luau`
- in `src/client/Controllers/Researchers.luau`, the name-tag code (grep
  `BillboardGui`)
- in `src/client/Lib/UI.luau`, grep `toast` and `pop`
- the `Sfx` module, if prompt 11 has run (grep `src/client/Lib/Sfx.luau`)

### Build

1. **Research cards** show:
   - the rank as gold stars next to the name
   - "Lv 3 / 5" with the data bar for the current rank
   - the perk now, including its rank bonus ("+30% from rank 3")
2. **Glints**: shown at the top of the Research panel per tier, with the
   zone name ("Mesa Glints: 37").
3. **The PROMOTE button** on a card when the researcher is level 5:
   - **When ready**: it shows the cost ("PROMOTE: 65 Glints") and works at
     the Research Office.
   - **When not ready**: it's disabled, with the reason as a toast on tap,
     for example "Needs 28 more Generator Yard Glints" or "Visit the
     Research Office".
   - **Confirming**: it explains the reset ("Back to level 1, rank 2, +10%
     perk, can work in Generator Yard").
4. **The post picker** shows zones above the researcher's rank as locked,
   with "Needs rank N".
5. **The promotion moment**: a short celebration on the card (stars pop in,
   sparks), plus the researcher model at its camp or the office doing a
   little jump.
   - If prompt 11's sound system exists, play the level-up fanfare, since
     it's already in the palette; don't add new sounds here.
6. **Name tags** above researcher models show their rank stars.
7. **Feeling the target**: a one-time tip the first time you unlock a zone
   your team can't enter yet: "Your researchers can't work here yet: catch
   bolts here for Glints and promote them at the Research Office."

### Done means (part B)

- `stylua src` and `selene src` are clean.
- The harness tests pass.
- `tools/check_world.sh Game` still passes.
- If the Studio MCP is connected:
  - use the TEST buttons to get a researcher to level 5 and add Glints
  - promote at the office: the stars show, the level resets, and the post
    picker unlocks the next tier
- Tick part B, commit and push.
