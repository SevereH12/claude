# Prompt 3: Premium-only zone

Follow the rules in `docs/prompts/README.md`.

**Needs prompt 2**: `src/shared/Util/Progression.luau` with `canEnter` must
exist. If it doesn't, stop and tell the user.

Add a zone that only **Roblox Premium members** can enter. There's no Game
Pass. Non-members see it, can walk up to its gate, and get Roblox's
official Premium upsell. It should feel special, without making free play
feel worse.

## Read only

- `src/shared/Config.luau`, `Types.luau`, `Util/Progression.luau`
- in `src/server/Systems/Strikes.luau`, only `resolve`
- `src/server/Systems/DevCommands.luau`
- the client gate-barrier controller from prompt 2 (grep `ZoneGates`)
- `src/server/World/Styles/WeatherLab/Themes/init.luau` and
  `Themes/Default.luau`
- in `src/server/World/Styles/WeatherLab/WLTypes.luau`, the `Theme` type

## Build

1. **The zone**: add a Config entry, `Aurora` ("Aurora Reef", tagline
   "Premium members only, 1.5x your best zone").
   - `premium = true`, `mode = "Shared"`, a fast `strikeInterval` of about
     0.6, a premium gold-violet colour, `requiresBottle = 1`, a size of
     about 100 x 110, and a floor of about 12. If `Layout.plan` says a
     connector is too steep, change only the floor.
   - Give it the next `order`, so it lands in the next spiral slot and the
     Research Center moves one slot out.
   - Its catch value is per player: 1.5x (`PREMIUM_VALUE_MULTIPLIER`) the
     `chargeValue` of the best non-premium zone that player can enter. That
     keeps it worth visiting at every stage. `resolve` works the value out
     per catcher.
2. **Who's Premium**: `Progression.canEnter` also needs
   `player.MembershipType == Enum.MembershipType.Premium` for `premium`
   zones.
   - Pass the membership into the pure function, so it stays testable.
   - Re-check on `Players.PlayerMembershipChanged`, which fires when
     someone subscribes in-game, and open the gate straight away.
   - **Studio testing**: in Studio only, the TEST button panel gets a
     "Pretend Premium" toggle (a player attribute the server only honours
     when `RunService:IsStudio()`).
3. **The upsell**: when a non-member touches the closed barrier (a client
   position check, at most once per 30 seconds), call
   `MarketplaceService:PromptPremiumPurchase(localPlayer)`.
   - Show Roblox's Premium icon, `utf8.char(0xE001)`, on the gate sign and
     in the lock reason ("Premium members only").
   - Check that the icon renders, and drop it if it doesn't.
4. **How it looks**: a new WeatherLab theme `Premium` (`Themes/Premium.luau`,
   registered in `Themes/init.luau`).
   - Build the island with `Default`'s functions, then add premium dressing:
     - gold-trimmed boardwalk posts and violet border ropes
     - an aurora ribbon in the sky above it (a few Beams)
     - lanterns, and a "PREMIUM" arch
   - Keep the catch floor low contrast.
5. **Test**: extend `test_progression.luau` with premium entry for a
   member, a non-member and the Studio pretend flag.

## Done means

- `stylua src` and `selene src` are clean.
- `test_progression.luau` passes.
- `tools/check_world.sh WeatherLab <scratch dir>` passes. Look at the top
  render once: the new zone sits in the next slot and the Research Center
  moved out.
- Report (don't fix) whether `check_world.sh` still passes for `StormPunk`
  and `SkyIsles`.
- Commit and push.
