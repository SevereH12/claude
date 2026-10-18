# Researchers part 6 (later): camps and office in the world framework

Only do this when a new world style is about to replace `Legacy`. Until
then the Legacy map's hand-placed camps and office (part 1) are all the
game needs.

Follow the rules in `docs/prompts/researchers/README.md`. Read
`design.md` section 5.

**Needs part 1**: `src/shared/Util/ResearchSites.luau` must exist. If it
doesn't, stop and tell the user.

Goal: every style built by `World/Builder` gets a camp per zone
automatically, so a new zone always gets a camp with no extra work.

## Read only

- `src/server/World/Layout.luau`, `Builder.luau` and `Types.luau`
- in `src/server/World/Kit.luau`, grep for `sellArea`, `spawn`, `sign` and
  `strut`
- the `buildHub` function in `src/server/World/Styles/Blockout.luau`
- in the style that's about to go live, its hub file only (ask the user
  which style)

## Build

1. **Layout**:
   - Every slot gets a `camp` CFrame: a flat pad of about 14 x 28 at floor
     height, just outside the footprint on the hub-facing edge, beside the
     gate and clear of the connector.
   - `Layout.plan` includes camps in its overlap and clearance checks.
2. **Builder**:
   - Create `Map.ResearchCamps.<ZoneId>` boxes with the same contract as
     Legacy.
   - Call an optional `StylePack.buildCamp(ctx, zone)`. Fall back to a new
     `Kit.researchCamp`: a deck on piles down to whatever is below, a tent,
     a mast and a sign.
3. **Office**:
   - Add `Kit.researchOffice(parent, pad)`, modelled on `Kit.sellArea`.
   - Builder warns (doesn't error) when a style built no `ResearchOffice`.
     Turn that into an error once every live style has one.
   - Add an office to Blockout's hub and to the style that's going live.

## Done means

- `stylua src` and `selene src` are clean.
- `tools/check_world.sh` passes for Blockout and the style that's going
  live.
- In both renders, the camps sit beside the gates and nothing overlaps.
- The part 6 box is ticked, and the work is committed and pushed.
