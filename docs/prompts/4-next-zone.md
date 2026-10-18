# Prompt 4: add the next zone (run once per zone)

Follow the rules in `docs/prompts/README.md`.

**Needs prompt 2**: `requiresBottle` must be on `ZoneDef`. If it isn't, stop
and tell the user.

Each run adds **one** zone: the first row in the plan below that isn't
ticked. The zone plays exactly like the existing ones. Only the map theme,
the numbers and the shop items are new. When you're done, tick its row in
this file.

## The plan

Gates point at the bottle the previous zone added, so the zones unlock in
order. Floors are suggestions: if `Layout.plan` says a connector is too
steep, change only this zone's `floor`.

| Done | id | Name | Theme | Mode | Volts per charge | Strike interval | Size (w x d) | Floor | Needs bottle | New bottle (capacity / price) | New boots (bonus / price) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [ ] | Marsh | Thunder Marsh | Marsh | Shared | 60 | 0.9 | 104 x 120 | 10 | Storm Cell | Tempest Tank 250 / 40,000 | Bog Hoppers +7 / 35,000 |
| [ ] | Glacier | Glacier Rim | Glacier | Single | 180 | 1.2 | 96 x 104 | 30 | Tempest Tank | Cryo Cell 600 / 200,000 | Ice Cleats +8 / 180,000 |
| [ ] | Caldera | Caldera | Volcano | Shared | 500 | 0.9 | 108 x 116 | 40 | Cryo Cell | Magma Battery 1,500 / 1,000,000 | Ember Striders +9 / 900,000 |
| [ ] | Summit | Storm Summit | Summit | Single | 1,500 | 1.1 | 96 x 100 | 56 | Magma Battery | Thunder Core 4,000 / 5,000,000 | Sky Treads +10 / 4,500,000 |

Boots bonuses must keep in-zone speed below `WALK_SPEED_OUTSIDE`. If a
bonus would break that, raise `WALK_SPEED_OUTSIDE` in the same change and
say so.

## Read only

- `src/shared/Config.luau`
- `src/server/World/Styles/WeatherLab/Themes/init.luau` and
  `Themes/Default.luau`
- in `src/server/World/Styles/WeatherLab/WLTypes.luau`, the `Theme` type
- in `src/server/World/Styles/WeatherLab/Palette.luau`, the `colors` table
- the theme's section of `docs/styles/WeatherLab.md` (grep `## Zones`
  onward), for the art rules

## Build

1. **Config**:
   - add the zone entry with the next `order`, a colour no other zone uses,
     a tagline in the style of the others, and `requiresBottle` set to the
     tier index of the bottle it needs
   - append the new bottle to `BOTTLES` and the new boots to `BOOTS`
   - the Research Center moves one slot out by itself, and the new zone's
     Research Camp comes from the framework
2. **The theme**: `Themes/<Theme>.luau`, registered in `Themes/init.luau`.
   - Start from `Default`'s structure and keep to WeatherLab's style guide
     and palette, plus two accent colours for this biome. Ideas:
     - **Marsh**: reed beds, lily pads, a stilt hut and fog
     - **Glacier**: ice shelves, snow caps, a frozen weather mast
     - **Volcano**: dark basalt, glowing cracks outside the field, a steam
       vent
     - **Summit**: a rocky peak, prayer-flag-like signal pennants, a big
       lightning rod
   - The catch floor stays flat, clear and low contrast, as a bold two-tone
     field pattern like the other zones.
   - Build everything from `Blocks` and Kit parts. No terrain.
3. Tick this zone's row in the plan above.

## Done means

- `stylua src` and `selene src` are clean.
- `tools/check_world.sh WeatherLab <scratch dir>` passes, including the
  walkcheck to the new zone and its camp.
- Look at the top and side renders once: the new zone is in the next slot,
  reachable, and nothing overlaps.
- Report (don't fix) whether `check_world.sh` still passes for `StormPunk`
  and `SkyIsles`.
- Commit and push.
