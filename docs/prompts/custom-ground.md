# Prompt: custom-made ground for Storm Bottler

Copy everything below the line into a new Claude Code session on this repo.

---

Replace Roblox's stock ground textures in Storm Bottler Simulator with ground
textures made for this game. Read `CLAUDE.md` first and follow it. Use the
roblox-dev skills: `roblox-architecture` for where the code goes and
`roblox-performance` for the texture memory budget.

## The goal

Right now every surface uses Roblox's built-in materials. The terrain is
filled with Sand, Grass, Sandstone, Rock, Slate, Cobblestone and so on, then
tinted with `Terrain:SetMaterialColor`. The floor parts are WoodPlanks,
Concrete, DiamondPlate and so on. Anyone who plays Roblox recognises them
instantly.

After this change, **no stock texture shows on any ground a player walks on
or looks at**. Each world style gets its own set of ground textures, painted
from its palette, so the ground looks like part of the game's art instead of
a Roblox default.

"Ground" means all terrain, plus the parts players walk on: boardwalk and
catwalk decks, bridges, plazas, pads and the spawn. Walls, props, signs and
neon stay as they are.

## What Roblox allows (checked against the docs; design around it)

- Custom materials are `MaterialVariant` instances. They only work as
  descendants of `MaterialService`.
- Terrain can't take a variant per voxel. To re-skin a terrain material, set
  a base material override:
  `MaterialService:SetBaseMaterialOverride(Enum.Material.Sand, "<variant name>")`.
  The variant's `BaseMaterial` must match. This changes every terrain voxel
  **and every part** that uses that material.
- Parts can take a variant one at a time with
  `BasePart.MaterialVariant = "<name>"`. Use this for part-built ground, so
  props that share the base material don't change.
- A terrain variant can have up to three `TerrainDetail` children
  (`Face` = Top, Side, Bottom), each with its own maps. Use them: grass on
  top with soil and roots on the sides, or a flat sandstone top with banded
  strata on the sides.
- The texture properties on `MaterialVariant` and `TerrainDetail`
  (`ColorMap`/`ColorMapContent`, `NormalMap...`, `RoughnessMap...`,
  `MetalnessMap...`) are **Plugin Security**. A game script can't set them at
  runtime, but the updater plugin can. `StudsPerTile`, `MaterialPattern` and
  `SetBaseMaterialOverride` can be set from any script.
- `MaterialService.Use2022Materials` must be on, because mixing the legacy
  terrain pack with variants costs performance. Scripts and plugins can't set
  it, so the README tells the user to tick it once in Studio.
- Textures need Roblox asset ids, which images only get by being uploaded.
  There are two ways:
  - **Open Cloud Assets API**:
    - send `POST https://apis.roblox.com/assets/v1/assets` with an
      `x-api-key` header
    - send a multipart body with a `request` field (assetType `"Image"`,
      displayName, `creationContext.creator` with userId or groupId) and a
      `fileContent` field
    - poll `GET https://apis.roblox.com/assets/v1/operations/{id}` until it
      returns `assetId` and a `moderationResult`
    - images must be under 8000x8000 pixels and 20 MB
  - **By hand**: Studio's Asset Manager bulk import.

If any of this has changed by the time you read it, follow the current
Roblox docs and note what changed.

## The pipeline

**1. Make the textures in the repo.**
- `tools/textures/generate.py` (Python with Pillow, plus numpy if useful;
  `tools/render_map.py` already uses Pillow) paints seamless tiles
  procedurally. Use a fixed seed per style so the output is reproducible and
  reviewable in git.
- Colour maps go in `assets/textures/<Style>/<Name>_color.png`.
- Paint a height field at the same time and derive the normal and roughness
  maps from it. Those depend on the shape (pebbles, planks, ripples), not on
  colour, so put them in `assets/textures/Shared/` and reuse them across
  styles. Only the colour maps are per style.
- Anyone can replace any PNG with a hand-painted one of the same name, and
  the rest of the pipeline doesn't care.

**2. Preview without Studio.**
- `tools/textures/preview.py <Style> <outdir>` writes a contact sheet. Each
  texture is tiled 3x3 so seams and repetition show, and lit with its normal
  map from the style's sun direction, once in calm colours and once in storm
  colours.
- Every catch floor texture also gets a strike warning ring drawn on top in
  that zone's colour, to check the ring still stands out.
- Look at the sheets and fix problems before uploading anything.

**3. Upload.**
- `tools/textures/upload.py` uploads new or changed PNGs (tracked by content
  hash) through Open Cloud.
- It writes the ids into a generated, committed
  `src/server/World/Ground/AssetIds.luau` (file name to `rbxassetid://...`
  plus the hash), so unchanged files are never uploaded twice.
- The API key and creator id come from environment variables
  (`ROBLOX_API_KEY`, and `ROBLOX_CREATOR_ID` for a user or group). Never
  commit or print the key.
- Report any image that moderation didn't approve.
- In the README, explain how to make the key (Creator Dashboard, Open Cloud,
  API keys, Assets read and write). Also explain the manual fallback: bulk
  import in Studio, then a helper script that takes pasted "name id" lines
  and fills in `AssetIds.luau`.
- The plugin only downloads `src/`, so only the ids need to reach Studio,
  not the PNGs.

**4. Install in Studio.**

New module `src/server/World/Ground/init.luau` with `Ground.install(style)`.
`Lib/MapBuilder.build` calls it before building, for Legacy as well as the
other styles.

The plugin requires a clone of MapBuilder, so on Update Game this runs with
plugin permissions and can set the texture maps. It:
- creates or updates variants named `<Style>_<Name>` in folders
  `MaterialService.StormBottler.<Style>`. Keep every style's variants, so
  switching style never needs a re-upload.
- sets the maps, `StudsPerTile`, `MaterialPattern` and the `TerrainDetail`
  faces.
- sets base overrides for the style's terrain materials and clears overrides
  on every other material, so one style never bleeds into the next.
- skips any texture whose id is missing. It warns once with the full list,
  that material keeps its stock look, and the build never breaks.
- works at runtime too. `Systems/Map` builds the map when none is saved, and
  game scripts can't write texture maps. So only set the overrides there,
  rely on the variants already saved in the place, and wrap the plugin-only
  writes so they never error at runtime.
- reaches other modules by absolute paths only, never `script.Parent` (see
  the comment in `MapBuilder`).

The variants are saved with the place when the user presses Ctrl+S after
Update Game; say so in the README. No plugin rebuild should be needed. If one
turns out to be, update the plugin and tell the user to install the new
build.

## The ground spec for each style

Each style declares its ground in `World/Styles/<Style>/Ground.luau`, and
Legacy in `Lib/LegacyGround.luau`. Add an optional `ground` field to the
StylePack in `World/Types.luau`.
- **Terrain**: one spec per terrain material, with the colour, normal and
  roughness texture names, `StudsPerTile`, `MaterialPattern` and optional
  Top, Side and Bottom faces. Use `Organic` for natural ground, to hide the
  tiling, and `Regular` for laid surfaces like planks, cobbles and bricks.
- **Floor parts**: named part variants such as `Boardwalk`, `Catwalk`,
  `Plaza`, `Pad` and `Spawn`. Kit helpers and the style pieces assign them to
  floor parts through `MaterialVariant`.

Cover every terrain material each style actually fills. Water isn't a
material variant, so leave it to the style's water colour. Today the list
is roughly:
- **Legacy (live)**: Sand, Grass, Sandstone, Rock and Cobblestone terrain;
  Concrete and DiamondPlate floor parts.
- **WeatherLab**: Sand, Salt, Sandstone, Limestone, Rock, Slate, Grass,
  LeafyGrass, Cobblestone, Brick, WoodPlanks, Ground, Basalt.
- **StormPunk**: Sand, Limestone, Sandstone, Basalt, Slate, Rock, Brick,
  Pavement, LeafyGrass, Grass, Ground, Concrete, Salt.
- **SkyIsles**: Rock, Slate, Basalt, Pavement, Cobblestone, Grass,
  LeafyGrass, Sand, Sandstone, Ground, Limestone, Mud, Salt.

Build the real list from the code (each palette's terrain colour table and
every `Fill*` / `WriteVoxels` call) rather than trusting this one.

A global override also re-skins every part made of that material, so audit
each style. If a prop that isn't ground uses an overridden material, decide
on purpose. Rocks matching the cliffs is good. A roof turning into cliff
texture is not, so move that prop to a material the style doesn't override.

Terrain colours: check in Studio whether `Terrain:SetMaterialColor` still
tints an overridden material. Either way, bake the palette into the colour
maps so the look doesn't depend on the tint. If the tint multiplies, set it
to white so the colour doesn't double up.

## Art direction

- **Painted, stylized and cheerful**, matching the style guides in
  `docs/styles/`, with Bee Swarm-like readability. No photo textures and no
  noise soup. Use big soft shapes that read from across the map, and keep
  fine detail for up close.
- **Colours come only from the style's palette** in
  `docs/styles/<Style>.md`. Tune values and saturation so the ground still
  reads under the darker storm lighting.
- **Give the ground a Storm Bottler identity, but keep it rare.** A few small
  touches that say lightning lands here:
  - in sand, an occasional glassy fulgurite squiggle (the real glass that
    forms when lightning hits sand)
  - old scorch rings faded into rock
  - a few tiny cyan quartz glints in cliff faces, without spamming emissive
- **Ideas per material** (adapt them to each style):

  | Material | Look |
  | --- | --- |
  | Sand | wind ripples and a few shells |
  | Salt / wet sand | a smooth, darker shore band |
  | Grass | painted clumps with soft light and dark patches, a few clovers or flowers; soil-and-roots sides |
  | Sandstone, limestone | flat cracked tops with banded strata sides |
  | Rock, slate, basalt | chunky faceted plates with a few cracks |
  | Cobble, brick, pavement | rounded stones and mortar in the style's paving colours |
  | Dirt paths | packed earth with worn footprints |
  | Boardwalks | planks with grain and nail heads |
  | Catwalks | diamond plate redrawn in the style's metal |
- **Catch floors come first and must stay readable.**
  - The two-tone field patterns stay.
  - Any material used on a catch floor must be low contrast and low detail:
    no blades, pebbles or high-frequency noise. Warning rings, the strike
    scorch marks and players must stand out against it.
  - The preview sheet shows this. Also add a numeric check: the luminance
    spread must stay under a threshold.
- **Tiling**: no visible seams. Break up repetition with the `Organic`
  pattern, a large `StudsPerTile` and a few variations baked into each tile.
- **Sizes**:
  - 1024 px for big ground colour maps
  - 512 px for normal and roughness maps, and for small surfaces
  - about 30 images or fewer per style, to respect phone memory

## Out of scope

Meshes, new geometry, changes to the layout or the catch rules, and water.

## Done means

- `stylua src` and `selene src` are clean.
- `generate.py` is deterministic (two runs produce identical files). It
  fails if a tile's edges don't wrap seamlessly or a catch floor texture is
  too contrasty.
- The harness checks the ground setup:
  - `tools/harness/World.luau` gets a `MaterialService` stub that records
    variants and overrides.
  - A test checks that every terrain material a style fills has a ground
    spec, that every texture a spec names is in `AssetIds.luau` or reported
    missing, and that no override points at a variant that doesn't exist.
  - `tools/check_world.sh` still passes for every style that passed before.
- Preview sheets exist for every style, and the final message shows them so
  the user can judge the look.
- Uploading:
  - If `ROBLOX_API_KEY` and `ROBLOX_CREATOR_ID` are set, upload the textures
    and commit the ids.
  - If not, leave the missing ids empty and confirm the game still builds
    with the stock look. Then tell the user exactly how to run the upload.
- If the Roblox Studio MCP is available:
  - sync, then run the map build the way Update Game does
  - look at the ground in calm and storm weather
  - catch a strike to confirm the warning rings read clearly
  - play mode shows `[StormBottler] server started` and `client started`
    with no errors
- The README gets a section on the ground textures: making, previewing and
  uploading them, the Use2022Materials tick, and pressing Ctrl+S after Update
  Game. The map rules in `CLAUDE.md` mention ground specs and that floor
  parts get their variant through the Kit helper.
- Commit and push.
