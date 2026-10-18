# Prompt 4: add the next zone, using the unused maps (run once per zone)

Follow the rules in `docs/prompts/README.md`.

**Needs prompt 2**: `requiresBottle` must be on `ZoneDef`. If it isn't, stop
and tell the user.

The repo has two finished world styles that aren't used: **StormPunk**
("Voltcliff Works": copper coils and factory islands) and **SkyIsles**
(floating rune islands). Each run turns **one** of them into a new zone
inside the live WeatherLab world. The zone island, field, border and gate
look like that style; it plays exactly like the other zones; and it comes
with new values, a new bottle and new boots.

Do the first row in the plan that isn't ticked, and tick it when you're
done.

## The plan

| Done | id | Name | Borrowed look | Mode | Volts per charge | Strike interval | Size (w x d) | Floor | Needs bottle | New bottle (capacity / price) | New boots (bonus / price) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [x] | Works | Voltcliff Works | StormPunk zone island | Shared | 60 | 0.9 | 104 x 116 | 12 | Storm Cell | Tempest Tank 250 / 40,000 | Coil Striders +7 / 35,000 |
| [ ] | Isles | Stormspire Isles | SkyIsles floating island | Single | 180 | 1.2 | 96 x 104 | 32 | Tempest Tank | Rune Cell 600 / 200,000 | Sky Treads +8 / 180,000 |

Numbers are suggestions. If `Layout.plan` says a connector is too steep,
change only this zone's `floor`. Boots bonuses must keep in-zone speed below
`WALK_SPEED_OUTSIDE`.

## Step 1: review the map you're borrowing (before writing code)

- Run `tools/check_world.sh <Style> <scratch dir>` for the style in this
  row and look at its top and side renders once.
- Read that style's "Zones" section in `docs/styles/<Style>.md`, plus its
  `init.luau`, `Zone.luau` and `Themes/init` (or the theme list in
  `init.luau`). Open other files only when a function you'll call needs
  them.
- Pick the most distinctive of its zone themes that isn't a beach or a
  canyon, since WeatherLab already has those. StormPunk's Default
  ("Generator Yard") and SkyIsles' Default are the likely picks.
- Write down, in a few lines in your reply:
  - which theme you're borrowing
  - what state its zone functions need from `ctx`: anything its
    `atmosphere`, `buildBase` or `buildHub` sets up (for example `Geo` or
    `Land` registries and palette lookups)
  - how you'll provide that state inside a WeatherLab build

## Step 2: build it

1. **Config**:
   - add the zone with the next `order`, a colour no other zone uses, a
     tagline in the style of the others, `requiresBottle` set to the tier
     index of the needed bottle, and `theme` set to the borrowed look (for
     example `"StormPunk:Default"`)
   - append the new bottle to `BOTTLES` and the new boots to `BOOTS`
2. **Borrowing in WeatherLab** (`Styles/WeatherLab/init.luau`): when a
   zone's theme names another style (`"<Style>:<Theme>"`), that zone's
   `buildZoneGround`, `buildBorder`, `buildGate` and theme dressing go to
   that style pack's own functions instead of WeatherLab's.
   - Set up whatever state they need, without running the other style's
     atmosphere, hub or teaser.
   - WeatherLab still builds the connector boardwalk, so make sure it meets
     the borrowed gate cleanly.
   - The framework still makes the zone volume, Research Camp and gate
     barrier.
3. **Make it sit in WeatherLab's world**: the borrowed island keeps its own
   look, but blend the edges:
   - its base meets WeatherLab's sea, or for SkyIsles it floats above the
     bay with a visible tether or rock spire
   - colours that turn muddy under WeatherLab's lighting get a small
     per-zone tweak through the borrowed palette, not by editing the
     alternate's files
4. **Leave the alternates working**: prefer calling their code without
   changing it. If a small change is unavoidable, keep it backwards
   compatible, and both alternates must still pass `check_world.sh` as full
   styles.
5. Tick this zone's row in the plan above.

## Step 3: review before pushing

Don't push until all of this passes. Fix anything that fails and review
again (at most twice).

- `stylua src` and `selene src` are clean.
- `tools/check_world.sh WeatherLab <scratch dir>` passes: build, gameplay
  tests, walkcheck (spawn to the new zone, its camp and its gate) and
  flickercheck.
- `tools/check_world.sh` still passes for StormPunk and SkyIsles.
- Look at the WeatherLab top and side renders and check that:
  - the new zone is in the next spiral slot, and the Research Center moved
    one slot out
  - the boardwalk meets the borrowed gate with no gap or step
  - the catch floor is flat, clear and low contrast, and nothing borrowed
    stands on it
  - nothing overlaps the neighbouring zones, the camp or the Research
    Center
  - the island clearly reads as the borrowed style, yet doesn't look broken
    or floating by accident next to WeatherLab
- If the Studio MCP is connected, take one look in play mode, during a
  storm if you can.
- In your final message, list what you checked, with the render images
  attached. Then commit and push.
