# Prompt: build the map out of blocks instead of terrain

Copy everything below the line into a new Claude Code session on this repo.

---

Rebuild Storm Bottler's live map (the `Legacy` style) out of parts instead
of Roblox Terrain. Same layout and heights, so nothing about gameplay moves.
The result should look hand-built, like a chunky, clean diorama. Follow
`CLAUDE.md`.

## Keep it cheap

- Read only these files:
  - `CLAUDE.md`
  - `src/server/Lib/LegacyMapBuilder.luau`
  - `randomGroundPoint` in `src/server/Systems/Strikes.luau`
  - the "catch floors must stay clear" block in
    `tools/harness/test_gameplay.luau`

  For anything else, grep; don't open whole files.
- Don't open or edit:
  - the other styles (`src/server/World/Styles/*`)
  - `src/server/World/Kit.luau`
  - `docs/styles`, the client and the plugin
- Plan once, then write each file in a single pass. No refactors beyond
  what's listed here.
- Run the checks once at the end. Fix and re-run at most once. Look at the
  render images at most twice.
- If `lune`, `stylua` or `selene` is missing, add it to `rokit.toml` and run
  `rokit install`, one try only. If that fails, skip that check and say so.

## Changes

**1. `src/server/World/Blocks.luau` (new).** A small helper module that a
future style can reuse. Every function takes a parent and a colour, makes
anchored `SmoothPlastic` parts, and returns them. It needs:
- `box`
- `wedge` (a ramp)
- `ring`: an N-sided ring of rotated blocks, for round islands
- `strata`: stacked layers, each slightly inset, alternating two tones
- `rock`: a cluster of 2 or 3 rotated chunky blocks
- a seeded colour jitter of about ±4% brightness per part, so surfaces
  aren't flat. Use a fixed seed so every build is identical.

No unions, meshes, decals or textured materials. Colour carries the look.

**2. `LegacyMapBuilder.luau`.** Replace `buildTerrain()` with
`buildGround()`. It builds the same shapes from `Blocks` and requires the
module by absolute path (`ServerScriptService.Server.World.Blocks`). Put
every walkable ground part in a `Workspace.Map.Ground` folder.

- **Sea**:
  - one big teal water part with its top at y = -2: Transparency about 0.3,
    `CanCollide` and `CanQuery` off, not in `Ground`
  - a solid sand seabed at about y = -6, so anyone who falls in can wade
    back
  - wedge beaches all round, so you can walk out of the water anywhere
- **Island** (radius 195, top at y = 0): a 20-sided `ring` of soil blocks
  with 1-stud grass caps on top. The caps overhang slightly and are lighter
  than the sides. A sand ring steps down to the water.
- **Shoreline** (x 60 to 160, z -80 to 80, floor 0): a flat sand catch
  floor in two soft tones, laid as a few wide beach-towel stripes.
- **Mesa** (x -160 to -70, z -55 to 55, floor 12):
  - a `strata` plateau in two sandstone tones
  - a flat top in a low-contrast two-tone checker
  - the ramp up its east side kept as a wedge in the same place, with the
    same slope and the same 16-stud width
- **Paths**: the four cobble paths as stone-coloured strips 0.2 studs
  above the grass, each with a darker edging strip.
- **Rocks**: `rock` clusters at the same spots as the old terrain balls.
- Keep `workspace.Terrain:Clear()` so old voxels go away. Fill no terrain.
  Leave the Terrain's `Clouds` alone, because the storm controller uses it.
- Add the ground colours (grass, soil, sand, wet sand, two sandstones, rock,
  path, water, seabed) to the `COLORS` table. Keep catch floors low
  contrast so the warning circles stand out.

**3. `Strikes.randomGroundPoint`.** The raycast must also include
`Workspace.Map.Ground` (keep Terrain in the include list too, so the
terrain-based styles still work).

**4. Harness.** Add one check to `tools/harness/test_gameplay.luau`: each
zone's catch rectangle is covered by parts in `Map.Ground` whose tops sit at
that zone's floor height. Use plain box math, like the existing checks.

## Rules that must still hold

- Catch floors are flat, with one surface at exactly floor height and no
  lips or gaps. Nothing sits above floor + 0.3 inside a zone except its
  outer 2-stud border band.
- Ground parts are `Anchored`, with `CanTouch` off and `CanQuery` on (the
  strike raycast needs it).
- Anything a player crosses is a wedge or a step of 1 stud or less, and
  ramps are no steeper than 28°.
- Zone volumes, the spawn, the Power Plant and `SellArea` are unchanged.
- The whole map stays under 2,500 parts, with the new ground adding no more
  than about 350.

## Done means

- `stylua src` and `selene src` are clean.
- `tools/check_world.sh Legacy <scratch dir>` passes, including the
  walkcheck.
- Look at `Legacy_top.png` and `Legacy_side.png`. The island, beach, mesa
  layers and ramp should read clearly, with nothing floating or
  overlapping.
- Add one line to the README saying the Legacy map is built from parts.
- Commit and push. Report the part count and show the two render images.
