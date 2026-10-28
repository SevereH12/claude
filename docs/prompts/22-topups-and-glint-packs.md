# Prompt 22: Glint packs, and buy buttons that offer a top-up

Follow the rules in `docs/prompts/README.md`. **Run it twice**; each run
does the first unticked part, then ticks it.

- [x] Part A: Glint packs (new developer products, sold in the store)
- [x] Part B: every buy button stays tappable; when you're short, it offers
  the cheapest pack that covers the difference

The user's choices:
- 3 Glint packs for **every zone tier that promotions use**: 25 Glints for
  49 Robux, 75 for 129, and 200 for 299
- each pack gives Glints of its own tier, named after that tier's zone
  ("75 Mesa Glints")
- the products are created **on sale**

## Part A: Glint packs (run 1)

### Read only

- in `src/shared/Util/Research.luau`: `maxRank`, `tierZone` and
  `glintsOf`. Promotions to rank r use Glints of tier r or higher, so
  tiers 1 to `maxRank()` are sold; tier 0 is never needed.
- in `src/shared/Config.luau`: `VOLT_PACKS` (the pattern to copy) and
  `STORE`
- `src/server/Systems/Receipts.luau` and, in `src/server/Systems/Research.luau`,
  `Research.addGlints`
- `src/shared/Util/Store.luau` (`receiptDecision` and `recordPurchase`:
  every receipt is paid once)
- in `src/client/Controllers/BoostsUI.luau`: the tab where Volts packs are
  shown
- `tools/store/store_items.json`, `items.py`, `create_store.py`,
  `make_icons.py`, `upload_icons.py` and `store_ids.json`

### Build

1. **`Config.GLINT_PACKS`**: one entry per tier from 1 to `maxRank()` ×
   the 3 sizes, each with `key`, `tier`, `glints`, `productId` and `image`.
   Work the tiers out from `Research` so a new zone tier only needs new
   entries.
2. **The products**:
   - add them to `store_items.json` (a "glintPacks" group: name like
     "75 Mesa Glints", a one-line description, the price, and a colour from
     that zone)
   - make their icons with `make_icons.py` in the existing style: a gem in
     the zone's colour with the count
   - create them **on sale** with `create_store.py` (it uses the Open Cloud
     key the network adds for `apis.roblox.com`; never print or commit a
     key), upload the icons, and put the ids in `store_ids.json` and Config
   - if creating products is refused, stop this step, leave `productId = 0`
     (shown as COMING SOON) and say so in the report
3. **Paying out**: `Receipts` pays a Glint pack through
   `Research.addGlints(player, tier, glints)`, once per purchase id (the
   same rule as Volts packs). It saves and syncs like the others, and logs
   an Economy analytics event like the Volts packs do.
4. **In the store**: a GLINTS section next to the Volts packs, grouped by
   zone. It shows each tier's Glints you own, and dims (but still sells)
   tiers you haven't reached, with "for promotions to rank N".
5. **Tests**: extend `tools/harness/test_rewards.luau` (or a new
   `test_store.luau`): every tier 1 to `maxRank()` has 3 packs, keys and
   product ids are unique across all products, and a receipt pays once.

## Part B: top-ups (run 2)

**Needs part A**: `Config.GLINT_PACKS` must exist. If it doesn't, stop and
tell the user.

### Read only

- in `src/client/Controllers/ShopUI.luau`: how bottle, boots and Ascend
  rows set their buttons (`UI.setEnabled`)
- in `src/client/Controllers/ResearchUI.luau`: the HIRE and PROMOTE buttons
- `src/client/Controllers/Offers.luau` (the existing offer card) and
  `src/shared/Util/Store.luau` (`packVolts`: a Volts pack's Volts depend
  on the player's progress)
- in `src/shared/Util/Research.luau`: `glintsFor` and `canPromote`

### Build

1. **`Util/TopUp.luau`** (pure):
   - `TopUp.volts(short, progress)`: the Volts pack to offer for `short`
     missing Volts, the **cheapest in Robux whose `Store.packVolts` covers
     it**; if none covers it, the biggest pack
   - `TopUp.glints(short, rank, glints)`: the same for a promotion to
     `rank`, from the Glint packs of tier `rank` (the cheapest that covers
     the shortfall, or the biggest)
   - only packs with a real `productId`
2. **Buy buttons stay tappable**: a bottle, boots, Ascend, HIRE or PROMOTE
   button the player can't afford looks like a normal buy button with the
   price, not greyed out.
   - **Still greyed out** for reasons Volts can't fix: owned already,
     needs an earlier item, not at the Research Office, level too low.
     Keep those messages.
   - **Tapping one you can't afford** shows a small confirm card:
     "You need 1.2K more ⚡. Get the Storm Jar (+2.4K ⚡) for 199 R$?"
     with BUY and NO. BUY prompts the product
     (`MarketplaceService:PromptProductPurchase`). It never buys anything
     by itself, and the item isn't bought for them afterwards: they tap
     the item again.
   - **For PROMOTE**, the same with Glints: "You need 12 more Mesa
     Glints. Get 25 Mesa Glints for 49 R$?"
   - Reuse the offer card's look (`Offers`), or `UI.window`, and the
     device layout rules. Sounds through `Sfx`.
3. **The server is unchanged**: buying still checks Volts and Glints on
   the server, as now.
4. **Tests**: `tools/harness/test_topup.luau` covers:
   - the cheapest pack that covers the shortfall, at several progress
     levels (pack Volts change with progress)
   - the biggest pack when nothing covers it
   - products with no id are skipped
   - Glint packs of the right tier

## Done means (every part)

- stylua and selene are clean; the new tests and the existing harness
  tests pass, including `test_layout`.
- Re-read the diff for wrong argument counts, unused names, lines over 100
  columns and require cycles.
- Part A: the products exist on sale (or the report says why not), and
  their ids are in Config and `store_ids.json`.
- Report the "check in Studio" steps:
  - Part A: buy a Glint pack in Studio, where it's a test purchase, and
    check the Glints arrive
  - Part B: with 0 Volts, tap the Vial and see the top-up offer naming the
    cheapest pack that covers it
- Tick the part, commit and push.
