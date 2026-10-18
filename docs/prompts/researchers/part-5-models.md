# Researchers part 5: the researchers you can see

Follow the rules in `docs/prompts/researchers/README.md`. Read
`design.md` sections 1 and 7.

**Needs part 2**: players must have `Research_<RoleId>` attributes, which
are set in `src/server/Systems/Research.luau`. If they aren't, stop and tell
the user.

Goal: researchers appear at their camps and at the office, drawn by each
client.

## Read only

- `src/shared/Util/ResearchSites.luau`
- `src/server/Systems/Bottles.luau`, as the example of a model built from
  parts
- in `src/client/Controllers/Storm.luau`, grep for `Storm.current`,
  `Storm.Changed` and `phase`
- `src/client/Controllers/ResearchUI.luau`, only to add portraits
- for perk reactions, grep `src/shared/Remotes.luau` for `Forecast` and
  `src/shared/Types.luau` for `assayed`, `tanked` and `ownerId`. React only
  to what exists.

## Build

1. **`src/client/Lib/ResearcherModels.luau` (new)**: `build(roleId)`
   returns a Model of 14 parts or fewer, made from parts only, following
   design section 7. Each role's instrument is the silhouette. Add named
   parts for the animator to move: `Instrument`, `Arm`, `Hood` and, for the
   Chemist, `TankFill`.
2. **`src/client/Controllers/Researchers.luau` (new)**:
   - Read every player's `Research_*` attributes, and update on
     `AttributeChanged`, `PlayerAdded` and `PlayerRemoving`.
   - Place models on spots across each camp deck (up to 8 per camp) and
     around the office pad. Your own researchers take the front spots and
     get a name tag ("Dr. Isobar · Forecaster Lv3"). Extra researchers show
     as a "+N more on site" board.
   - Use one `Heartbeat` loop for idle and storm motions. Only animate
     within 250 studs of the camera, allocate nothing per frame, and clean
     up everything when players leave.
   - React to perks that exist: the Forecaster points, the Analyst prints
     tape, the balloon jerks before a balloon bolt, and the Chemist's tank
     fill follows `tankCount`.
3. **ResearchUI**: add a ViewportFrame portrait to each card, using
   `ResearcherModels.build`.

## Done means

- `stylua src` and `selene src` are clean.
- `tools/check_world.sh Legacy <scratch dir>` still passes. The models are
  client-only, so the map part count doesn't change.
- If the Studio MCP is connected: hire the Forecaster and post them to
  Shoreline; they appear at the Shoreline camp and react to a storm.
- The part 5 box is ticked, and the work is committed and pushed.
