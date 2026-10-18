# Researchers part 4: perks II (Chemist and Storm Chaser)

Follow the rules in `docs/prompts/researchers/README.md`. Read
`design.md` sections 2 and 3, the last two bullets.

**Needs part 3**: a `Forecast` remote in `src/shared/Remotes.luau`. If it
isn't there, stop and tell the user.

## Read only

- `src/server/Systems/Strikes.luau` and `Research.luau`
- the loop in `src/server/Systems/Selling.luau` (the position-check
  pattern)
- `src/shared/Types.luau` (the strike types) and
  `src/shared/Util/ResearchSites.luau`
- in `src/client/Controllers/StrikeFX.luau`, only `onWarning`, `onLanded`
  and `popup`
- in `src/client/Controllers/HUD.luau`, grep for `BottleBar`

## Build

1. **Chemist**:
   - In `resolve`, a full player with tank room
     (`Research.active(player, "Chemist")` level gives the capacity) is a
     normal candidate, in `Single` zones too. Their charge and value go to
     `tankCount` and `tankValue`, and their UserId goes in a new `tanked`
     list on `StrikeLanded`.
   - In `Research`, add a loop like Selling's: a player standing at the camp
     of the zone their Chemist is posted to, with room in their bottle, has
     the tank moved into the bottle. Call `Sync.markDirty` after.
2. **Storm Chaser**:
   - Refactor `randomGroundPoint` to optionally take a centre and a distance
     range (12 to 20 studs). It still raycasts and still stays inside the
     catch area.
   - In `Research`, run a per-player balloon timer during storms while the
     Storm Chaser is active. When it fires, call a new `Strikes.spawnFor`
     with that player.
   - The strike carries an `ownerId` on `StrikeWarning` and `StrikeLanded`,
     and `resolve` only lets the owner catch it.
   - At most one balloon bolt is in flight per player. The zone's normal
     pacing doesn't change.
3. **Client**:
   - StrikeFX draws other players' balloon bolts muted grey.
   - A "+1 → TANK" popup when you're in `tanked`.
   - A small tank count beside the bottle bar while you own the Chemist.

## Done means

- `stylua src` and `selene src` are clean.
- `tools/check_world.sh Legacy <scratch dir>` still passes.
- The part 4 box is ticked, and the work is committed and pushed.
