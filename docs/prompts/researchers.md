# Prompt: add Researchers to Storm Bottler

Copy everything below the line into a new Claude Code session on this repo.

---

Add a **Researchers** system to Storm Bottler Simulator. Read `CLAUDE.md`
first and follow it (strict Luau, server owns state, Config for numbers,
remotes in `Remotes.luau`, `Sync.markDirty`, `PlayerData.get`, the world
framework rules). Use the roblox-dev skills: `new-system` for the
server/client/shared skeleton, `roblox-security` for the two new client
requests, `roblox-datastores` for the profile migration, `roblox-ui` for the
panel, and `roblox-performance` for the client renderer.

## The idea

Researchers are the game's take on pets, but they must **not** look or act
like normal Roblox pets. No eggs, no hatching, no rarities, no duplicates,
no fusing, nothing floating behind the player. Instead they are members of
the Storm Society, a small field team of storm scientists. You hire each one
once with Volts, then **post them at a zone's Research Camp**. There they set
up their instrument and work the storm. Their perk helps you while you play
in that zone, and they get better by collecting field data from the strikes
they watch.

The interesting choice is **where you post each one**. A Rod Tech at Mesa,
where only the closest player catches each bolt, does something different
from a Rod Tech at Shoreline. Posting someone in a zone you don't play also
trains them there.

## The five researchers

One of each role, hired in this order (each needs the previous one hired).
All numbers go in `Config.RESEARCHERS` (an ordered list) and are only
suggestions; balance against the bottle prices (250 / 1,500 / 8,000). Names
are placeholders you can change.

| # | Role (name) | Price | Perk while you are in their zone | Lv1 to Lv5 |
| --- | --- | --- | --- | --- |
| 1 | Forecaster (Dr. Isobar) | 400 | **Early Warning**: you see the next strike's ring privately before everyone else does | lead 0.4s to 1.2s |
| 2 | Rod Tech (Ohmar) | 1,500 | **Grounding Rod**: your catch radius is bigger | +1 to +3 studs |
| 3 | Analyst (Prof. Kilowatt) | 5,000 | **Charge Assay**: each charge you catch has a chance to be high grade and worth double | 10% to 30% |
| 4 | Chemist (Dr. Fizz) | 12,000 | **Overflow Tank**: when your bottle is full, catches go into her tank instead of being lost | 3 to 15 charges |
| 5 | Storm Chaser (Gale) | 30,000 | **Weather Balloon**: during storms they pull down a personal bolt near you that only you can catch | every 30s to 12s |

Rules for the perks (all decided on the server):
- A perk applies only while the owner's root is inside that zone
  (`Zones.at`) and the researcher has finished setting up.
- **Forecaster**: when Strikes picks a strike position, it sends a private
  `Forecast` remote (`FireClient`, never `FireAllClients`) to each eligible
  owner `lead` seconds before the public `StrikeWarning`. The public warning
  and the bolt timing stay exactly as they are. Picking the position a little
  earlier is fine.
- **Rod Tech**: `distanceInside` uses the player's own radius. In `Single`
  zones the winner is still the closest player by real distance, so the
  bonus lets you reach a bolt but never lets you beat someone standing closer.
- **Analyst**: rolled per catch with the server's `Random`. Double the
  charge value. Report it in `StrikeLanded` (for example an `assayed` list of
  UserIds) so the client can show a "x2 ASSAYED" popup.
- **Chemist**: a full player with room in the tank counts as a normal
  catcher (also in `Single` zones), and the charge and its value go to the
  tank. Standing at that zone's Research Camp with room in your bottle moves
  the tank into the bottle. This is a server position check on a loop, like
  `Selling`, with no remote. The tank saves.
- **Storm Chaser**: on a timer during storms, while the owner is in the
  zone, spawn a strike near the owner (12 to 20 studs away, inside the catch
  area, using the same ground raycast as normal strikes) through the normal
  warning, wait and resolve path, with an `ownerId` on `StrikeWarning` and
  `StrikeLanded`. Only the owner can catch it. Other clients draw it muted
  and grey. Allow at most one balloon bolt in flight per player. It does not
  change the zone's normal strike pacing.

**Field data and levels**: every strike that lands in a researcher's zone
while they are posted there and their owner is in the server gives them +1
data, or +3 if the owner caught it. Level thresholds are in Config
(suggested: 0, 40, 150, 400, 1000). Levelling is automatic and shows a toast.

**Posting**: a researcher is either at the Office (the hub) or posted to one
zone. Changing posts can be done from anywhere, but they need
`RESEARCH_SETUP_TIME` (about 8 seconds) to set up before the perk works,
so hopping between zones mid-storm isn't free. A saved post that points at a
zone no longer in `Config.ZONES` falls back to the Office. Hiring only works
while standing in the Research Office (server position check).

## Fitting into the map (the important part)

Researchers must work in every world style with no style needing to know
about them. Add two things to the map contract; the client draws the
researchers at those places.

**1. A Research Camp per zone (built by the framework).**
- `World/Layout.luau`: every slot also gets a `camp` CFrame. This is a flat
  pad (`RESEARCH_CAMP_SIZE`, about 28 x 14) at floor height, just outside the
  footprint on the hub-facing edge, beside the gate and clear of the
  connector. `Layout.plan` includes camps in its overlap and clearance
  checks, so adding a zone still lands cleanly and moves nothing.
- `World/Builder.luau` creates `Workspace.Map.ResearchCamps.<ZoneId>`: an
  invisible, non-colliding, non-query box over the pad with a `ZoneId`
  attribute, in a Persistent-streaming model like `Zones`. This is a gameplay
  contract, so styles never create it.
- Add an optional StylePack hook `buildCamp(ctx, zone)` to `World/Types.luau`.
  If a style has no `buildCamp`, use a new `Kit.researchCamp(ctx, zone)`: a
  neutral wooden deck on piles down to whatever is below (so it works over
  land, water or sky), a small tent, an instrument mast, and a sign reading
  "<ZONE> FIELD CAMP" in the zone colour. Keep it under about 30 parts. Give
  WeatherLab, StormPunk and SkyIsles their own `buildCamp` in their style's
  language (see `docs/styles/*.md`); Blockout can use the default.
- Catch floors stay untouched: camps are outside the footprint.

**2. A Research Office in the hub (built by each style).**
- New `Kit.researchOffice(parent, pad)`, modelled on `Kit.sellArea`: an
  invisible box tagged `ResearchOffice` over a clearly marked doorstep pad.
- `buildHub` in every style must make one, and `Builder` errors if none
  exists, just like `SellArea`. Ideas: WeatherLab turns one of its two
  existing research domes into the Storm Society office; StormPunk adds an
  R&D lab on a quiet bearing; SkyIsles adds an observatory alcove; Blockout
  adds a plain labelled box. Nothing may stand on a current or future lane.
- **Legacy is the live style** (`Config.WORLD_STYLE = "Legacy"`), so
  `Lib/LegacyMapBuilder.luau` gets a hand-placed office next to the Power
  Plant and a camp beside each zone's entrance (outside the zone box; Mesa's
  is beside the ramp).
- Update `CLAUDE.md` (map rules) and the style docs with the two new
  contracts.

## How researchers look

They are drawn by a new client controller from server-set data, so there are
no server instances, no replication cost and no map part budget.
- Small, chunky storm scientists about two thirds of a player's height, made
  from simple parts (no meshes or assets, like the rest of the game):
  rounded body, head, goggles, cream field coat with a Storm Society badge,
  and a role-coloured raincoat hood. Each one has 14 parts or fewer.
- **The instrument is the silhouette.** It is how you tell them apart from
  far away:
  - Forecaster: a brass barometer on a tripod, plus a clipboard
  - Rod Tech: a tall copper rod with a coil and a cable into the ground
  - Analyst: a folding desk with a glowing screen and a ticker-tape printer
  - Chemist: a glass tank backpack that visibly fills with cyan as her tank fills
  - Storm Chaser: a striped weather balloon on a tether that rises in storms
- They stand and work. They don't walk around after the player. In calm
  weather: idle motions (writing, adjusting the instrument, looking up at
  the sky). In storms: they brace, hoods up, and the instruments crackle
  cyan. They react when their perk fires (the Forecaster points, the Analyst
  prints tape on an assay, the balloon jerks before a balloon bolt).
- Unposted researchers hang around the Research Office.
- Neutral colours with one role accent, readable in every style. Use neon
  only for "bottled lightning" cyan.

## Data and remotes

- `Types.Profile` v2: add `researchers` (role id to `{ level, data, post }`)
  plus the Chemist's `tankCount` and `tankValue`. Bump `CURRENT_VERSION` in
  `PlayerData`, add the v1 to v2 migration, and update `DEFAULT_PROFILE`.
  Extend `Snapshot` with what the UI needs (including set-up-until times).
- Pure math (perk value at a level, level from data, next threshold) goes in
  a new `src/shared/Util/Research.luau` so both sides and the tests share it.
- New server system `src/server/Systems/Research.luau` owns hiring, posting,
  data, levels, the tank decant loop and the balloon timer. It exposes small
  queries (`radiusFor`, `forecastLead`, `rollAssay`, `tankRoom`...) that
  `Strikes` calls. It does not reach into Strikes' internals.
- Remotes (add them to `Remotes.luau`):
  - `HireResearcher(roleId)`: rate-limited; checks that the argument is a
    string that is a real role, that the player doesn't own it yet, that the
    previous role is hired, the Volts against the server's Config price, and
    that the player is standing in a `ResearchOffice` box.
  - `PostResearcher(roleId, post)`: rate-limited; `post` must be `"Office"`
    or a real zone id; the player must own the role.
  - `Forecast` (server to one client).
- So every client can draw everyone's team, the server sets attributes on
  each Player (for example `Research_Forecaster = "Mesa:3"` for zone and
  level). Clients only read them.

## Client

- `Controllers/Researchers.luau` renders the camps and the office:
  - The local player's researchers get the front spots and a name tag
    ("Dr. Isobar · Forecaster Lv3").
  - Other players' researchers fill the remaining spots, up to
    `RESEARCH_CAMP_SPOTS` (about 8). Any extra show as a "+N more on site"
    board.
  - Use one update loop, only animate camps within about 250 studs, and
    allocate nothing per frame. Clean up when players leave.
- `Controllers/ResearchUI.luau`: a "RESEARCH" button under the shop button
  opens a panel with one card per role. Each card has a ViewportFrame
  portrait, name, role, perk now and at the next level, a data bar, a post
  picker (Office plus each zone in Config order) and a Hire button. Hire is
  disabled with "Visit the Research Office to hire" unless you're standing
  there. Match `ShopUI` and `Lib/UI`.
- `StrikeFX`:
  - private forecast ring (faint and dashed, only you see it)
  - your extended reach ring when a Rod Tech is active
  - muted balloon bolts that belong to other players
  - "x2 ASSAYED" and "+1 → TANK" popups

## Out of scope

Eggs, rarities, trading, Robux purchases, researchers following the player,
the city meter, and any change to the public strike rate or sell flow.

## Done means

- `stylua src` and `selene src` are clean.
- `tools/harness/test_gameplay.luau` gains these checks:
  - every zone has a camp part, outside every zone volume and every
    SellArea, with walkable ground under it at floor height
  - at least one `ResearchOffice` exists, outside every zone
  - the camp pad is free of map parts above deck height
- `tools/walkcheck.py` treats camps and the office as places you must be
  able to walk to from spawn.
- `tools/check_world.sh` passes for Legacy and Blockout with no new failures
  for StormPunk, SkyIsles or WeatherLab. Look at the renders: camps sit
  beside gates and nothing overlaps. The map stays under 2,500 parts.
- A test for `Util/Research.luau` covers level thresholds and perk values.
- If the Roblox Studio MCP is available, sync and play. The output must show
  `[StormBottler] server started` and `client started` with no errors. Hire
  the Forecaster at the office, post them to Shoreline, see them at the camp
  and see the early ring. Then stop.
- Update the README (features, code layout) and commit and push.
