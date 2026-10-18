# Researchers part 1: Research Office and camps on the map

Follow the rules in `docs/prompts/researchers/README.md`. Read
`design.md` sections 1 and 5 only.

Goal: the live `Legacy` map gets a Research Office in the hub and a
Research Camp beside each zone, plus a shared module that finds them.
There's no gameplay yet; later parts use these.

## Read only

- `CLAUDE.md`
- `src/server/Lib/LegacyMapBuilder.luau`: the helpers at the top,
  `ZONE_LAYOUT`, `buildZone`, `buildPowerPlant`, `buildDecor` and `build`
- `src/shared/Util/Volumes.luau` and `src/shared/Util/Zones.luau`
- the zones and selling sections of `tools/harness/test_gameplay.luau`
- for `tools/walkcheck.py`, grep for how `SellArea` targets are found
  (around the `sells =` line and the "sell area not reachable" check)

## Build

1. **`src/shared/Util/ResearchSites.luau` (new)**: `camp(zoneId)`,
   `offices()`, `inOffice(position)` and `campAt(position)`, which returns
   the zone id or nil. Use `Volumes.contains`, the same way `Zones` does.
2. **`LegacyMapBuilder.luau`**: add `buildResearch(map)` and call it from
   `build`.
   - **Office**: a small Storm Society building of about 20 parts west of
     the Power Plant plaza, around (-55, 0, -88), with its door facing the
     plaza.
     - In front of the door, a marked doorstep pad with a "RESEARCH"
       surface label.
     - Over the pad, an invisible box tagged `ResearchOffice`, set up like
       the existing `SellArea` (Transparency 1, no collide, query or touch,
       about 12 tall).
   - **Camps**: a `ResearchCamps` model (ModelStreamingMode Persistent)
     holding one invisible box per zone, named after the zone, with a
     `ZoneId` attribute.
     - Each box sits over a visible camp of 30 parts or fewer: a wooden deck
       of about 14 x 28, a tent, an instrument mast with a spinning-cup
       anemometer shape, and a "<ZONE> FIELD CAMP" sign in the zone colour.
     - Suggested spots: Shoreline around (51, 0, -22), with the long side
       along the zone's west edge. Mesa around (-50, 0, 19), beside the foot
       of the ramp. Both must stay outside every zone box and clear of
       paths, rocks and trees.
   - If `Workspace.Map.Ground` exists (the block-map prompt has been done),
     put the camp decks and the office floor in it.
3. **Harness**:
   - `test_gameplay.luau` checks that:
     - every zone in `Config.ZONES` has a camp box outside every zone volume
       and every `SellArea`
     - at least one `ResearchOffice` exists, outside every zone and not
       overlapping a `SellArea`
     - standing on the office pad makes `ResearchSites.inOffice` true
     - standing on each camp deck makes `ResearchSites.campAt` return that
       zone
   - `walkcheck.py` treats each camp box and office box as a place that
     must be reachable from spawn, the same way it treats sell areas.
4. **`CLAUDE.md`**: add two lines to the map rules about the office and
   camp contract.

## Done means

- `stylua src` and `selene src` are clean.
- `tools/check_world.sh Legacy <scratch dir>` passes.
- In `Legacy_top.png`, the office and both camps sit clear of zones, paths
  and props.
- The part 1 box in the README is ticked, and the work is committed and
  pushed.
