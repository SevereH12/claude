# Researchers part 1: Research Office and camps on the map

Follow the rules in `docs/prompts/researchers/README.md`. Read
`design.md` sections 1 and 5 only.

Goal: the world framework gives every zone a Research Camp automatically,
and the live `WeatherLab` hub gets a Research Office. A shared module finds
them both. There's no gameplay yet; later parts use these.

## Read only

- `CLAUDE.md`
- in `src/server/World/`: `Layout.luau`, `Builder.luau` and `Types.luau`
- in `src/server/World/Kit.luau`, grep for `sellArea`, `sign` and `strut`
- in `src/server/World/Blocks.luau`, grep `^function Blocks` for the
  signatures
- `village()` in `src/server/World/Styles/WeatherLab/Hub.luau`. Grep
  `Pieces.luau` for `function Pieces.dome` (and the comment above it).
- `src/shared/Util/Volumes.luau` and `Zones.luau`
- the zones and selling sections of `tools/harness/test_gameplay.luau`
- for `tools/walkcheck.py`, grep for how `SellArea` targets are found
  (around the `sells =` line and the "sell area not reachable" check)

## Build

1. **`src/shared/Util/ResearchSites.luau` (new)**: `camp(zoneId)`,
   `offices()`, `inOffice(position)` and `campAt(position)`, which returns
   the zone id or nil. Use `Volumes.contains`, the same way `Zones` does.
2. **Layout**:
   - Every zone slot gets a `camp` CFrame: a flat pad of about 14 x 28 at
     floor height, just outside the footprint on the hub-facing edge, beside
     the gate and clear of the connector.
   - `Layout.plan` includes camps in its overlap and clearance checks, so
     adding a zone still never breaks anything.
   - Add `camp` to the `Slot` type.
3. **Builder**: after the zones are built, create a `Map.ResearchCamps`
   model (ModelStreamingMode Persistent).
   - It holds one invisible box per zone, named after the zone, with a
     `ZoneId` attribute. Set it up like `SellArea`: Transparency 1, no
     collide, query or touch, about 12 tall.
   - Then call an optional `StylePack.buildCamp(ctx, zone)`, falling back
     to `Kit.researchCamp(ctx, zone)`. Add `buildCamp` to `Types.luau`.
   - Warn (don't error) if the map has no part tagged `ResearchOffice`,
     because the alternate styles don't have one yet.
4. **Kit**:
   - `researchCamp`, using `Blocks`:
     - a deck in `ctx.folders.ground` on piles down to whatever is below,
       joined to the gate landing so players can walk onto it
     - a canvas tent, an instrument mast with an anemometer shape, and a
       "<ZONE> FIELD CAMP" sign in the zone colour (`Kit.sign`)
     - 30 parts or fewer, using neutral wood and canvas colours that suit
       any style
   - `researchOffice(parent, pad)`, modelled on `Kit.sellArea`: an invisible
     box tagged `ResearchOffice` over the pad.
5. **WeatherLab office**: the first research dome placed in `village()` is
   the observatory. Make it the Storm Society Research Office.
   - Put a marked doorstep pad in front of its door (in
     `ctx.folders.ground`).
   - Add a "RESEARCH" sign.
   - Call `Kit.researchOffice` over the pad.
   - Keep it off every boardwalk corridor, the same way the village already
     does.
6. **Harness**:
   - `test_gameplay.luau` checks that:
     - every zone has a camp box outside every zone volume and every
       `SellArea`
     - standing on each camp deck makes `ResearchSites.campAt` return that
       zone
     - for WeatherLab, a `ResearchOffice` exists outside every zone, and
       standing on its pad makes `ResearchSites.inOffice` true
   - `walkcheck.py` treats camp and office boxes as places that must be
     reachable from spawn, like sell areas.
7. **`CLAUDE.md`**: add two lines to the map rules about the office and
   camp contract.

## Done means

- `stylua src` and `selene src` are clean.
- `tools/check_world.sh` passes for WeatherLab, Blockout, StormPunk and
  SkyIsles. If a camp doesn't fit in an alternate style, fix the placement
  in Layout, not in that style's files.
- Look only at `WeatherLab_top.png`: the office and every camp sit clear of
  zones, boardwalks and buildings.
- The part 1 box in the README is ticked, and the work is committed and
  pushed.
