# Prompt 8: Game Passes, Volts packs and fair nudges

Follow the rules in `docs/prompts/README.md`.

**Run it three times.** Each run does the first part below that isn't
ticked, then ticks it:

- [x] Part A: the pass system, the store, and 2x Volts, Remote Sell, Big
  Bottles and Lucky Charges
- [x] Part B: Lab Grant, VIP, Bolt Colours and Jet Boots
- [ ] Part C: Volts packs, offers at the right moment, the free trial and
  store stats

## Why these passes

They fit this game's loop, and none of them lets a buyer take bolts away
from other players:
- **Selling** means walking back to the sell station every time the bottle
  fills. Remote Sell and Big Bottles cut that chore.
- **Earning** goes up with 2x Volts and Lucky Charges, and only for the
  buyer.
- **Researchers** are this game's own feature, which no other game can sell.
  Lab Grant speeds them up.
- **Your bottle** is always in your hand and lightning arcs into it, so
  everyone sees VIP's gold and Bolt Colours on every catch. That makes other
  players want them.
- **Speed in zones** stays earned with bought boots. Jet Boots only speed up
  travel outside zones.

## Fair-play rules (Roblox policy, and good for trust)

- A purchase window only ever opens because the player tapped BUY. Offers
  never open one by themselves.
- No fake timers, fake discounts or fake scarcity. Show real numbers (the
  Lucky Charges chance, the real Robux price).
- An offer never blocks play and is easy to close.
- Grant purchases on the server, never because the client says so.

## The passes

Prices are in Robux. Put them in Config as the fallback display price only;
the real price always comes from Roblox (see "Prices" below).

| key | Name | Price | What it does |
| --- | --- | --- | --- |
| `DoubleVolts` | 2x Volts | 249 | Every sale pays 2x |
| `RemoteSell` | Remote Sell | 199 | A SELL button that works anywhere |
| `BigBottles` | Big Bottles | 149 | Every bottle holds 50% more (rounded down) |
| `LuckyCharges` | Lucky Charges | 149 | Each charge you catch has a 15% chance to be worth double |
| `LabGrant` | Lab Grant | 199 | Researchers set up instantly and gain field data 2x as fast |
| `VIP` | VIP | 399 | Golden bottle and golden lightning arcs, a VIP chat tag and title, and 10% more Volts |
| `BoltColours` | Bolt Colours | 99 | Choose the colour of the lightning that arcs into your bottle |
| `JetBoots` | Jet Boots | 99 | 50% faster outside storm zones only, with a jet trail |

Multipliers multiply: 2x Volts with VIP pays 2 × 1.1 = 2.2x.

## Part A: the pass system, the store and four passes (run 1)

### Read only

- `src/shared/Config.luau` (the `STORE` table at the bottom),
  `Types.luau` (`Snapshot`), `Remotes.luau` and `Util/Formulas.luau`
- `src/server/Systems/Selling.luau`, `Sync.luau` (`toSnapshot`) and
  `DevCommands.luau`
- in `src/server/Systems/Strikes.luau`, `resolve` (the catch loop and the
  Analyst assay roll)
- in `src/server/Systems/Research.luau` and `Bottles.luau`, the lines that
  call `Formulas.capacity` (grep)
- `src/client/Controllers/BoostsUI.luau` (the store layout already exists)
- in `src/client/Controllers/HUD.luau`, the bottle bar
- in `src/client/Controllers/Shortcuts.luau` and `DevCommands.luau`, grep
  how keys and the TEST panel are added
- in `src/shared/Util/Progression.luau`, grep `PRETEND_PREMIUM` (the
  pattern for Studio test toggles)

### Build

1. **Config**: replace `STORE.passes` with `PASSES`, a list of
   `{ key, id, name, icon, detail, price }` for the four part A passes.
   - Take each `id` from `tools/store/store_ids.json` if it exists. That
     file is written by `tools/store/create_store.py`, which creates every
     pass and pack through Open Cloud, off sale.
   - Otherwise `id = 0`, and the card says COMING SOON.
   - The same file holds the ids for parts B and C.
   - Leave `STORE.volts` for part C.
2. **`src/shared/Util/Passes.luau` (pure)**:
   - `sellMultiplier(owned)`
   - `capacity(baseCapacity, owned)`
   - `luckChance(owned)`
   - `owned` is a set of pass keys

   Part B adds to it. Add `tools/harness/test_passes.luau`.
3. **`src/server/Systems/Passes.luau`**:
   - **Checking ownership**: on join, check every pass with an id using
     `MarketplaceService:UserOwnsGamePassAsync`, in a `pcall` with one
     retry, and cache the result.
   - **Granting**: grant straight away on the server's
     `PromptGamePassPurchaseFinished`. Players have reported
     `wasPurchased` coming back false after a real purchase, so when it's
     false, re-check with `UserOwnsGamePassAsync` once, about 2s later.
   - **What it exposes**:
     - `Passes.owns(player, key)` and `Passes.owned(player)`
     - player attributes `Pass_<key> = true`, for other clients to show
     - the owned set added to the `Snapshot`
   - **Studio testing**: the TEST panel gets one "Pretend owns <pass>"
     toggle per pass. It's honoured only when `RunService:IsStudio()`,
     exactly like Pretend Premium.
4. **The four effects**, each through `Util/Passes`:
   - **2x Volts**: `Selling` multiplies what each sale pays.
   - **Big Bottles**: every capacity check uses the player's own capacity
     (Strikes room and full checks, the Chemist decant, the bottle glow).
     Add `capacity` to the `Snapshot`, so the HUD and shop show the real
     number. Make `Formulas.isFull` take the capacity rather than work it
     out.
   - **Remote Sell**:
     - A `RemoteSell` remote: rate-limited, the player must own the pass, be
       alive and have charges, with a 5s cooldown. It sells through the same
       function as the sell station (refactor `sell` so the position check
       is the station path only), so Analytics and the `Sold` popup work
       unchanged.
     - On the client, owners get a SELL button by the bottle bar, with a
       1.5s charge-up ring before it fires, and a shortcut in `Shortcuts`
       (keyboard V, gamepad L1).
   - **Lucky Charges**: in `resolve`, roll the luck chance per catch, next
     to the Analyst roll. Each roll that hits doubles the charge, so both
     hitting gives x4. Add a `lucky` list to `StrikeLanded`. The client
     pops "x2 LUCKY", or "x4 JACKPOT" when both hit.
5. **Store (`BoostsUI`)**: the GAME PASSES tab is built from
   `Config.PASSES`.
   - **Price**: each card shows the price from
     `MarketplaceService:GetProductInfo(id, Enum.InfoType.GamePass)`, read
     on the client, cached and wrapped in `pcall`. Roblox price
     optimization can personalise prices, so the client must ask, and the
     Config price is only the fallback.
   - **Icon**: each card shows the item's real icon as an ImageLabel
     (`rbxassetid://` + the id under `icons` in `tools/store/store_ids.json`),
     falling back to the emoji if there's no id. The art lives in
     `tools/store/icons/` and is redrawn with `make_icons.py`.
   - **BUY** calls `MarketplaceService:PromptGamePassPurchase` on tap.
   - Owned passes show OWNED, and `id = 0` shows COMING SOON.
6. **README**: a short "Selling passes" section:
   - create each pass on the Creator Dashboard (Monetization, then Passes:
     a 512x512 image, name and description)
   - copy its asset id into `Config.PASSES`
   - test in Studio with the Pretend toggles; Studio purchase windows should
     say they're test purchases
   - check sales under Monetization, then Passes, then Analytics

### Done means (part A)

- `stylua src` and `selene src` are clean.
- `test_passes.luau` and the existing harness tests pass.
- `tools/check_world.sh Game` still passes.
- If the Studio MCP is connected, use the Pretend toggles to check four
  things:
  - a sale pays 2x
  - the bottle bar shows 50% more capacity
  - Remote Sell works away from the station
  - luck popups appear
- Tick part A, commit and push.

## Part B: Lab Grant, VIP, Bolt Colours and Jet Boots (run 2)

**Needs part A**: `src/server/Systems/Passes.luau` must exist. If it
doesn't, stop and tell the user.

### Read only

- `src/shared/Util/Passes.luau`, `Config.luau` (`PASSES`) and
  `Util/Formulas.luau` (`walkSpeed`)
- in `src/server/Systems/Research.luau`, the setup time and the data gain
  in `onStrikeLanded`
- `src/server/Systems/Bottles.luau`, `Boots.luau` and `Movement.luau`
- in `src/server/Systems/PlayerData.luau`, `DEFAULT_PROFILE`, `MIGRATIONS`
  and `migrate`
- in `src/client/Controllers/StrikeFX.luau`, the arc into each catcher's
  bottle (grep `bottlePosition`)
- `src/client/Controllers/BoostsUI.luau`

### Build

1. Append the four passes to `Config.PASSES`. Their effects go through
   `Util/Passes`, with tests.
2. **Lab Grant**: setup time is 0 and field data counts double, for the
   owner's researchers.
3. **VIP**:
   - **Volts**: 10% more on every sale, multiplied with 2x Volts.
   - **Golden bottle**: `Bottles` tints the glass and charge gold.
   - **Golden arcs**: StrikeFX draws a VIP catcher's arc in gold.
   - **Chat tag**: a gold `[VIP]` tag in chat, added on each client with
     `TextChatService.OnIncomingMessage`, using the sender's `Pass_VIP`
     attribute.
   - **Title**: a small "⚡ STORM VIP" BillboardGui over the head, made on
     the server and seen up to about 60 studs away.
4. **Bolt Colours**:
   - **Colours**: eight in `Config.BOLT_COLOURS`, each named and bright
     enough to read in a storm.
   - **Picking**: owners get a CHOOSE COLOUR picker on the pass card. The
     `SetBoltColour(index)` remote is rate-limited, needs the pass, and
     checks the index is in range.
   - **Saving**: the choice saves in the profile as `boltColour` (a
     migration, 0 = default), and goes on a `BoltColour` player attribute.
   - **Showing it**: StrikeFX uses it for that player's arcs, and `Bottles`
     for their charge glow.
   - **With VIP**: a chosen colour wins over VIP gold, and VIP gold wins over
     the default.
5. **Jet Boots**:
   - **Speed**: `Formulas.walkSpeed` takes the pass, and
     `WALK_SPEED_OUTSIDE` becomes 1.5x outside zones only. In-zone speed is
     unchanged.
   - **Trail**: `Boots` adds a jet trail while the owner runs outside zones.

### Done means (part B)

- `stylua src` and `selene src` are clean.
- `test_passes.luau` covers the new maths.
- `tools/check_world.sh Game` still passes.
- If the Studio MCP is connected, use the Pretend toggles to check:
  - researchers set up instantly
  - the VIP tag, title and gold appear
  - a chosen bolt colour shows on catches
  - Jet Boots are faster between zones only
- Tick part B, commit and push.

## Part C: Volts packs, offers, the free trial and store stats (run 3)

**Needs part B**: `JetBoots` must be in `Config.PASSES`. If it isn't, stop
and tell the user.

### Read only

- `src/shared/Config.luau` (`STORE.volts`) and `Util/Passes.luau`
- in `src/shared/Util/Progression.luau`, grep `boltValue`
- `src/server/Systems/Passes.luau` and `Selling.luau`
- in `src/server/Systems/PlayerData.luau`, the profile schema, migrations
  and save functions
- `src/server/Systems/Analytics.luau`
- `src/client/Controllers/BoostsUI.luau`
- in `src/client/Lib/UI.luau`, grep `toast`
- in `src/client/Controllers/Menu.luau`, grep how a panel opens

### Build

1. **Volts packs (Developer Products)**: `Config.VOLT_PACKS` is a list of
   `{ key, productId, name, icon, charges }`. `productId` is 0 until the
   user creates it.
   - **Amount**: the Volts a pack gives scale with progress: `charges` ×
     the bolt value of the best non-premium zone the player can enter. The
     card shows that player's real number and "about N minutes of
     catching".
   - **Suggested packs**:

     | Pack | Charges | Price |
     | --- | --- | --- |
     | Pocket Charge | 200 | 49 |
     | Storm Jar | 1,000 | 199 |
     | Thunder Crate | 6,000 | 899 |
     | Lightning Vault | 40,000 | 3,999 |

   - **Price on the card**: from `GetProductInfo` with
     `Enum.InfoType.Product`, on the client.
   - **Receipts** (`src/server/Systems/Receipts.luau`, the only place that
     sets `MarketplaceService.ProcessReceipt`):
     - The profile keeps the last 100 `PurchaseId`s (a migration).
     - An id it has already seen returns `PurchaseGranted`.
     - No loaded profile returns `NotProcessedYet`.
     - Otherwise grant the Volts, record the id, and save right away (add
       `PlayerData.saveNow` if there isn't one). Return `PurchaseGranted`
       only after the save worked; otherwise return `NotProcessedYet`.
   - **Stats**: log it as an economy Source with transaction type IAP.
2. **Offers at the right moment** (`Controllers/Offers.luau`): a small card
   with the pass icon, one line of text, SEE (opens Boosts scrolled to that
   pass) and ✕.
   - **When an offer may show**: put this in a pure `canOffer` function.
     - never in the first 3 minutes of a session
     - at most one offer every 5 minutes
     - each offer at most once per session
     - never while the menu or a panel is open
     - never for a pass the player owns
   - **Triggers**:
     - **Bottle full, far from a sell station** (more than about 60 studs):
       Remote Sell, or Big Bottles if they own Remote Sell. The locked SELL
       button also shows by the bottle bar at that moment, and tapping it
       opens the Remote Sell card.
     - **After a sale**, without 2x Volts: "That sale would have paid +N with
       2x Volts".
     - **Hiring a researcher or a level-up**: Lab Grant.
     - **An Analyst assay**: Lucky Charges ("Like doubles? 15% of catches
       with Lucky Charges").
3. **Free trial of 2x Volts**, once per player ever (`trialUsed` in the
   profile):
   - **Offering it**: after the player's third sale in a session, if they
     don't own 2x Volts, offer "Try 2x Volts free for 3 minutes".
   - **Starting it**: TRY sends a `StartTrial` remote. The server checks it's
     unused and not owned, then sets a server-time end.
   - **While it runs**: `Selling` applies 2x, and a small "2x TRIAL 2:41"
     chip shows on the HUD.
   - **When it ends**: a toast says "The trial earned you +N Volts", with
     SEE.
   - **Leaving early**: the rest of the trial is lost; say so on the offer.
4. **Real value on the store**: the server adds up the extra Volts 2x would
   have paid this session. The 2x Volts card shows "+N Volts this session
   with 2x". Only show true numbers.
5. **Thanks and social proof**: when anyone buys a pass, every client shows
   a system chat line ("⚡ Name got VIP!"), and the buyer gets a short
   celebration (sparks and a toast).
6. **Store stats** in `Analytics.luau`:
   - a "Store" funnel, with one funnel session id per store visit:
     1. opened Boosts
     2. tapped a card
     3. purchase window opened
     4. bought
   - custom events `OfferShown` and `OfferTapped` (`CustomField01` = the
     offer key), plus `TrialStarted` and `TrialEnded`
7. **Tests**: `tools/harness/test_offers.luau` covers:
   - every `canOffer` rule
   - the receipt decision (seen id, no profile, new id)
   - pack scaling
8. **README**: add creating Developer Products and pasting their ids to the
   "Selling passes" section.

### Done means (part C)

- `stylua src` and `selene src` are clean.
- `test_offers.luau`, `test_passes.luau` and the existing harness tests
  pass.
- `tools/check_world.sh Game` still passes.
- If the Studio MCP is connected, check four things (a Studio test purchase
  needs the pack's id set):
  - fill your bottle far from the station and the Remote Sell offer appears
    once
  - start the trial and a sale pays 2x
  - the trial ends with its summary
  - a pack purchase grants Volts once
- In your final message, list everything the user must create on the
  Creator Dashboard (8 passes and 4 products), with the names and
  suggested prices.
- **Turn the items on sale.** They were created off sale, so that nobody
  could buy them before their code was live. Once all three parts work, ask
  the user before switching them on (a PATCH of `isForSale=true` per item
  through Open Cloud, or on the Creator Dashboard).
- Tick part C, commit and push.
