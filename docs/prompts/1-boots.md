# Prompt 1: boots

Follow the rules in `docs/prompts/README.md`.

Add boots: a second thing to buy in the shop. **Boots only make you faster
inside storm zones**, which is where speed decides who reaches a bolt
first. Walking between zones stays at `WALK_SPEED_OUTSIDE` for everyone.

## Read only

- `src/shared/Config.luau`, `Types.luau`, `Remotes.luau`,
  `Util/Formulas.luau`
- `src/server/Systems/Shop.luau` and `Movement.luau`
- `src/server/Systems/PlayerData.luau`: `DEFAULT_PROFILE`, `MIGRATIONS`
  and `migrate`
- `src/server/Systems/Sync.luau`: `toSnapshot`
- `src/server/Systems/Bottles.luau`: `attach` only (how a model is welded
  to a character)
- `src/client/Controllers/ShopUI.luau`

## Build

1. **Config**: add `BOOTS`, an ordered list of `{ name, speedBonus, price }`.
   - Suggested tiers:

     | Boots | Bonus | Price |
     | --- | --- | --- |
     | Rain Boots | +0 | free, everyone starts with them |
     | Puddle Jumpers | +2 | 300 |
     | Squall Skippers | +3 | 900 |
     | Gale Striders | +4 | 2,000 |
     | Thunder Treads | +6 | 10,000 |

   - In-zone speed is `WALK_SPEED_IN_ZONE + speedBonus`, and must always
     stay below `WALK_SPEED_OUTSIDE`. Say so in a Config comment.
2. **Types and data**:
   - add `BootsDef`
   - add `bootTier` to `Profile` and `Snapshot`
   - migrate old profiles with `bootTier = 1`
3. **`Formulas`**: add `boots(tier)`, `nextBoots(tier)` and
   `walkSpeed(inZone, bootTier)`. Add `tools/harness/test_formulas.luau`
   (run with `lune run`) covering `walkSpeed`.
4. **Shop**: add a `BuyBoots(tier)` remote handled exactly like `BuyBottle`:
   - rate limit
   - a whole number in range
   - next tier only
   - the server's price
   - `Sync.markDirty`
5. **Movement**: use `Formulas.walkSpeed`.
6. **How boots look**: a new `Systems/Boots.luau` welds a small pair of
   boots to each character's feet, 4 parts or fewer, coloured by tier.
   Above tier 1, add a faint cyan spark trail while the player is in a zone.
   Use the same character handling as `Bottles.luau`.
7. **ShopUI**: two tabs, BOTTLES and BOOTS. The boots rows work like the
   bottle rows, with the bonus shown as "+4 speed in storm zones".

## Done means

- `stylua src` and `selene src` are clean.
- `lune run tools/harness/test_formulas.luau` passes.
- `tools/check_world.sh WeatherLab <scratch dir>` still passes.
- Commit and push.
