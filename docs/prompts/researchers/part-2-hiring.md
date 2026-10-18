# Researchers part 2: hiring, posting, levels and the Research panel

Follow the rules in `docs/prompts/researchers/README.md`. Read
`design.md` sections 1, 2, 4 and 6.

**Needs part 1**: `src/shared/Util/ResearchSites.luau` must exist. If it
doesn't, stop and tell the user.

Goal: players can hire researchers at the office, post them to zones, and
watch them gain data and levels. Perks come in parts 3 and 4, so for now a
researcher only exists as data and the panel.

## Read only

- `src/shared/Config.luau`, `Types.luau`, `Remotes.luau`
- `src/server/Systems/PlayerData.luau`: `DEFAULT_PROFILE`, `MIGRATIONS` and
  `migrate`
- `src/server/Systems/Shop.luau` and `Sync.luau`, the patterns to copy
- `resolve` in `src/server/Systems/Strikes.luau`
- `src/client/Controllers/ShopUI.luau` (the panel pattern)
- in `src/client/Controllers/HUD.luau`, grep for `buildShopButton`
- `src/client/Lib/UI.luau`: grep for the function names you need

## Build

1. **Config**:
   - `RESEARCHERS`: an ordered list of `{ id, name, role, price, perk,
     values }`, where `values` holds the five per-level numbers from
     design section 2
   - `RESEARCH_LEVELS`
   - `RESEARCH_SETUP_TIME`
   - `RESEARCH_DATA_WATCH = 1` and `RESEARCH_DATA_CATCH = 3`
2. **Types**:
   - add `ResearcherSave`
   - add `researchers`, `tankCount` and `tankValue` to `Profile` (the tank
     fields are added now so part 4 doesn't need a v3)
   - add `researchers` and `setupUntil` to `Snapshot`
3. **`src/shared/Util/Research.luau` (new, pure math)**: `def(roleId)`,
   `levelFor(data)`, `nextThreshold(level)`, `perkValue(roleId, level)`,
   `isValidPost(post)`.
   Add `tools/harness/test_research.luau` (run with `lune run`) covering the
   thresholds and the perk values.
4. **PlayerData**: bump `CURRENT_VERSION` to 2, add the v1 to v2 migration
   (`researchers = {}`, tank 0), and update `DEFAULT_PROFILE`.
5. **`src/server/Systems/Research.luau` (new)**:
   - `HireResearcher` and `PostResearcher` handlers, rate-limited and with
     every check from design section 6. Hiring requires
     `ResearchSites.inOffice(root)` on the server.
   - set-up timers
   - `Research.onStrikeLanded(zoneId, catchers)`: adds data, levels up, and
     fires a toast through `StateSnapshot` or a small field.
   - `Research.active(player, roleId)`: the researcher's level when they're
     posted to the zone the player is standing in and set up, otherwise nil.
     Parts 3 and 4 use only this.
   - sets the player attributes `Research_<RoleId> = "<post>:<level>"`
   - calls `Sync.markDirty` on every change
6. **Strikes**: `resolve` calls `Research.onStrikeLanded` once per strike.
   Don't change anything else in Strikes.
7. **Remotes**: add `HireResearcher` and `PostResearcher`.
8. **`src/client/Controllers/ResearchUI.luau` (new)**: a "RESEARCH" button
   under the shop button that opens a panel with one card per role.
   - Each card shows the name, role, the perk now and at the next level, a
     data bar, a post picker (Office plus each zone in Config order) and a
     Hire button.
   - Hire is disabled with "Visit the Research Office to hire" unless
     `ResearchSites.inOffice` is true for your character.
   - Show a level-up toast.
   - Match `ShopUI` and `Lib/UI`. No portraits yet (part 5 adds them).

## Done means

- `stylua src` and `selene src` are clean.
- `lune run tools/harness/test_research.luau` passes.
- `tools/check_world.sh Legacy <scratch dir>` still passes.
- The part 2 box is ticked, and the work is committed and pushed.
