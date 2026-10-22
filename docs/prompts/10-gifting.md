# Prompt 10: gift passes and boosts, buy boosts, and Server Storms

Follow the rules in `docs/prompts/README.md`.

**Run it twice.** Each run does the first part below that isn't ticked,
then ticks it:

- [x] Part A: gifting game passes to anyone by username (inbox,
  cross-server delivery, the gift window)
- [ ] Part B: boosts for yourself or as gifts, the Boost Bundle, Server
  Storms and gift announcements

**Needs prompt 8 part C and prompt 9 part A**:
`src/server/Systems/Receipts.luau` and `src/server/Systems/Boosts.luau` must
both exist. If either doesn't, stop and tell the user which prompt to run.

## How gifting works on Roblox

- **Nobody can buy a game pass for someone else.** So each pass has a
  matching **"Gift: <pass>" Developer Product** at the same price. The giver
  buys that, and the game unlocks the pass's effect for the receiver inside
  the game.
- **What the receiver owns**: they don't own the real Roblox pass, only the
  in-game effect, and that's all that matters in this game.
- **Receipts don't name the receiver.** `ProcessReceipt` only says who paid,
  so the server must remember who the gift is for before the purchase
  window opens.

## The products (already created, off sale)

Every id is in `tools/store/store_ids.json`, made by
`tools/store/create_store.py` from `tools/store/store_items.json`. Their
icons are under `icons` in the same file, and the art is in
`tools/store/icons/`. Never create products from game code.

| Group in `store_ids.json` | Products | Price |
| --- | --- | --- |
| `giftPasses` | `GiftDoubleVolts` ... `GiftJetBoots`, one per pass | same as the pass |
| `boosts` | `DoubleVoltsBoost`, `LuckyBoost`, `BigBottlesBoost`: 30 minutes each | 49 each |
| `boosts` | `BoostBundle`: all three boosts for 1 hour | 149 |
| `boosts` | `ServerStorm`: 2x Volts for everyone in the server for 15 minutes | 199 |

## Rules that keep it safe

- **Every gift arrives exactly once**: no losses and no doubles, even if the
  receiver is offline, in another server, or leaves while the giver is
  paying.
- **No free text**: gifts carry the giver's name, but there's no message
  box, so there's nothing to filter.
- **No gifting to yourself**: for yourself, use FOR ME on boosts, or buy
  the pass.
- **No gift the receiver already has**: you can't gift a pass someone
  already owns (as a real pass or a gift). Check this **before** the purchase
  window opens.
- **The server decides everything.** Every remote is rate-limited and
  validated.
- **The purchase window only opens from a tap**, as in prompt 8.

## Part A: gifting passes to anyone (run 1)

### Read only

- `src/shared/Config.luau` (`PASSES`) and `Types.luau` (`Profile`)
- `src/shared/Util/Passes.luau`
- `src/server/Systems/Passes.luau` and `Receipts.luau`
- in `src/server/Systems/PlayerData.luau`, `DEFAULT_PROFILE`,
  `MIGRATIONS`, `migrate`, the store name and key format, and `saveNow`
- `tools/store/store_ids.json`
- `src/client/Controllers/BoostsUI.luau`
- in `src/client/Lib/UI.luau`, grep `toast` and `window`

### Build

1. **Config**: `GIFT_PASS_PRODUCTS` (pass key to product id) and
   `GIFT_ICONS`, both from `store_ids.json`.
2. **Gifted passes count as owned**:
   - the profile gets `giftedPasses` (key to true) and `receivedGiftIds`
     (the last 200 gift ids), in a migration
   - `Passes.owns` is true for a real pass or a gifted one, so every effect
     works with no other changes
   - the store card shows OWNED (gift)
   - an owned or gifted pass never offers BUY
3. **The gift window** (from a GIFT button on every pass card):
   - "Who's this for?", with a list of players in this server (avatar and
     display name) and a username box
   - for a username, the client sends `FindPlayer(username)`, rate-limited.
     The server resolves it with `Players:GetUserIdFromNameAsync` and
     `GetNameFromUserIdAsync` (both in `pcall`), and returns the user id,
     name and display name. The client shows the avatar
     (`Players:GetUserThumbnailAsync`).
   - **Confirm screen**: "Gift VIP to DisplayName (@name)?", then BUY.
4. **Remembering who it's for**: BUY sends
   `PrepareGift(productKey, recipientUserId)`, rate-limited. The server
   checks:
   - the product is a real gift product
   - the receiver exists and isn't the giver
   - the receiver doesn't already have the pass. Use
     `MarketplaceService:UserOwnsGamePassAsync(recipientId, passId)`, plus
     their `giftedPasses`: read from their live profile if they're in this
     server, otherwise a read-only `GetAsync` of their saved profile.

   On success it stores the intent `{ recipientId, productKey, expires }`
   (5 minutes) per giver, and tells the client to call
   `PromptProductPurchase`. On failure, the client shows why ("They already
   have VIP").
5. **The receipt** (in `Receipts.luau`; still the only `ProcessReceipt`):
   - **With a matching, unexpired intent**: write the gift to the receiver's
     inbox, then return `PurchaseGranted`. Only return it after the inbox
     write succeeded; if the write fails, return `NotProcessedYet`.
   - **With no intent** (it expired, or the server restarted): give the giver
     a gift credit for that product (`giftCredits` in their profile) and tell
     them "Choose who gets your gift". Sending a credit uses the same window,
     with no purchase. Nothing is ever lost.
   - **Duplicates**: record the `PurchaseId` the same way prompt 8 does, so a
     receipt is never handled twice.
6. **The inbox**: a separate DataStore, `StormBottler_Gifts`, key
   `inbox_<userId>`, holding a list of
   `{ id = PurchaseId, kind, key, fromId, fromName, time }`.
   - **Writing**: always with `UpdateAsync`, capped at 100 entries.
   - **Delivering** (on join, and on a MessagingService message): apply each
     gift to the profile, skipping any id already in `receivedGiftIds`;
     `saveNow`; only then remove those ids from the inbox with `UpdateAsync`.
     If the server dies halfway, the next join re-applies and the id check
     stops doubles.
   - **Live delivery**: after the inbox write, publish
     `{ recipientId }` on the MessagingService topic `Gifts`. Every server
     listens, and the one with that player delivers straight away. If
     publishing fails, the gift just waits for their next join.
7. **Telling people**:
   - the receiver gets a celebration toast, "🎁 Name gifted you VIP!", or on
     join "You received 2 gifts!" with the list
   - the giver gets "Gift sent to Name", plus "they'll get it next time they
     join" if they're offline
8. **Studio testing**: Studio purchase windows are test purchases, and
   MessagingService works only partly in Studio. Add a "Send test gift to
   me" TEST-panel button (Studio only) that writes a fake gift to your own
   inbox, so delivery can be checked.
9. **Test**: `tools/harness/test_gifts.luau` covers:
   - intent matching and expiry
   - the no-intent credit path
   - inbox apply with duplicate ids skipped
   - owned = real or gifted
   - every refusal rule

### Done means (part A)

- `stylua src` and `selene src` are clean.
- `test_gifts.luau` and the existing harness tests pass.
- `tools/check_world.sh Game` still passes.
- If the Studio MCP is connected: "Send test gift to me" with a pass, and
  the pass works and shows OWNED (gift).
- Tick part A, commit and push.

## Part B: boosts for me or a friend, the Bundle, Server Storm (run 2)

**Needs part A**: `StormBottler_Gifts` must be used in the code. If it
isn't, stop and tell the user.

### Read only

- `src/shared/Util/Boosts.luau` and `src/server/Systems/Boosts.luau`
- `src/server/Systems/Receipts.luau` and the gift code from part A
- `src/server/Systems/Analytics.luau`
- `src/client/Controllers/BoostsUI.luau`
- `tools/store/store_ids.json`

### Build

1. **Config**: `BOOST_PRODUCTS`, each with its product id, what it grants
   (boost keys and minutes) and its icon id, from `store_ids.json`.
2. **A BOOSTS tab** in the store: one card per boost product, each with
   **FOR ME** and **GIFT**.
   - **FOR ME** buys it for yourself.
   - **GIFT** uses the part A window, with the same intent, inbox and
     delivery; the inbox entry's `kind` is `"boost"`.
   - A boost received while offline starts counting down when the receiver
     next plays (the prompt 9 timers only count while online).
   - Owning a pass for that effect doesn't block a boost; the card says
     "you own 2x Volts, so this adds nothing for you".
3. **Server Storm** (FOR ME only, because it's for the whole server):
   - **The effect**: 2x Volts for everyone in this server for 15 minutes,
     including people who join during it. It isn't saved.
   - **Stacking**: a second purchase adds 15 minutes, up to 60.
   - **Multipliers**: it multiplies with passes and personal boosts through
     `Util/Passes`.
   - **Announcement**: "⚡ Name started a SERVER STORM! 2x Volts for
     everyone, 15:00", as a big banner, a system chat line, and a server-wide
     HUD chip showing the buyer's name and the time left.
   - **Late receipts**: if the receipt arrives after the buyer left the
     server, it applies in whichever server they're in when Roblox retries
     it.
4. **Social proof**:
   - a system chat line in the receiver's server, "🎁 Name gifted VIP to
     Name2"
   - the giver's server shows "🎁 Name sent a gift!"
5. **Stats** in `Analytics.luau`:
   - custom events `GiftSent` and `GiftReceived` (`CustomField01` = the
     product key), and `ServerStorm`
   - Robux purchases are already counted by Roblox, so log only Volts
     movements as economy events
6. **Test**: extend `test_gifts.luau` with:
   - boost gifts adding time
   - Server Storm stacking and its cap
   - the sell multiplier with a pass, a personal boost, the group bonus and
     a Server Storm

### Done means (part B)

- `stylua src` and `selene src` are clean.
- `test_gifts.luau` and the existing harness tests pass.
- `tools/check_world.sh Game` still passes.
- If the Studio MCP is connected:
  - buy a 2x Volts Boost FOR ME (a test purchase): the chip shows 30:00
  - buy a Server Storm: everyone gets 2x and the banner shows
- **Putting it on sale**: when both parts work, ask the user before putting
  the gift and boost products on sale (`isForSale=true`, through Open Cloud
  or the Creator Dashboard). They were created off sale on purpose.
- Tick part B, commit and push.
