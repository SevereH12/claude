# Researchers: design

Shared by every part. Read only the sections your part names.

## 1. The idea

Researchers are the game's take on pets, but they must **not** look or act
like normal Roblox pets. No eggs, no hatching, no rarities, no duplicates,
no fusing, and nothing floating behind the player.

They are the Storm Society, a field team of five storm scientists. You hire
each one once with Volts at the Research Office in the hub, then **post them
at a zone's Research Camp**. There they set up their instrument and work the
storm. Their perk helps you while you play in that zone, and they level up
from the strikes they watch.

The interesting choice is **where you post each one**. Posting a researcher
in a zone you don't play also trains them there.

## 2. The five roles

One of each, hired in order (each needs the previous one). All numbers live
in `Config.RESEARCHERS` and are starting suggestions; names are placeholders.

| # | id | Name | Price | Perk while you're in their zone | Lv1 to Lv5 |
| --- | --- | --- | --- | --- | --- |
| 1 | `Forecaster` | Dr. Isobar | 400 | **Early Warning**: you privately see the next strike's ring before everyone else | lead 0.4s to 1.2s |
| 2 | `RodTech` | Ohmar | 1,500 | **Grounding Rod**: bigger catch radius | +1 to +3 studs |
| 3 | `Analyst` | Prof. Kilowatt | 5,000 | **Charge Assay**: each charge you catch may be high grade, worth double | 10% to 30% |
| 4 | `Chemist` | Dr. Fizz | 12,000 | **Overflow Tank**: when your bottle is full, catches go into her tank | 3 to 15 charges |
| 5 | `StormChaser` | Gale | 30,000 | **Weather Balloon**: during storms, pulls down a bolt near you that only you can catch | every 30s to 12s |

## 3. Perk rules (all decided by the server)

A perk only works while the owner's root is inside that zone (`Zones.at`)
and the researcher has finished setting up.

- **Forecaster**: when Strikes picks a strike position, each eligible owner
  gets a private `Forecast` (`FireClient`, never `FireAllClients`) `lead`
  seconds before the public `StrikeWarning`. Public warning and bolt timing
  are unchanged.
- **Rod Tech**: catch distance uses the player's own radius. In `Single`
  zones the closest player by real distance still wins, so the bonus lets
  you reach a bolt but never beat someone standing closer.
- **Analyst**: rolled per catch with the server's `Random`. Doubles that
  charge's value. `StrikeLanded` lists the assayed UserIds so the client
  can show a popup.
- **Chemist**: a full player with tank room counts as a normal catcher (in
  `Single` zones too), and the charge goes to the tank. Standing at that
  zone's Research Camp with room in your bottle moves the tank into the
  bottle. This is a server position check on a loop, like `Selling`, with
  no remote. The tank saves.
- **Storm Chaser**: on a timer during storms, while the owner is in the
  zone, a strike lands 12 to 20 studs from them, inside the catch area. It
  goes through the normal warning, wait and resolve path with an `ownerId`.
  Only the owner can catch it; other clients draw it muted grey. At most one
  balloon bolt is in flight per player, and it doesn't change the zone's
  normal strike pacing.

## 4. Levels, posting and hiring

- **Field data**: each strike that lands in a researcher's zone while
  they're posted there and their owner is in the server gives +1 data, or
  +3 if the owner caught it. Level thresholds are in Config (suggested: 0,
  40, 150, 400, 1000). Levelling up is automatic and shows a toast.
- **Posting**: a researcher is either at the `"Office"` or posted to one
  zone. You can repost from anywhere, but they need `RESEARCH_SETUP_TIME`
  (about 8 seconds) to set up before the perk works. A saved post that names
  a zone no longer in `Config.ZONES` falls back to the Office.
- **Hiring** only works while standing in the Research Office (server
  position check).

## 5. Map contract

- **Research Office**: a building in the hub with an invisible box tagged
  `ResearchOffice` over a clearly marked doorstep pad. It works like
  `SellArea`.
- **Research Camp**: one per zone, just outside the zone (never on the
  catch floor), beside its entrance. It has an invisible box at
  `Workspace.Map.ResearchCamps.<ZoneId>` (Persistent-streaming model, `ZoneId`
  attribute) over a flat deck of about 14 x 28, plus a small tent, an
  instrument mast and a "<ZONE> FIELD CAMP" sign in the zone colour.
- `src/shared/Util/ResearchSites.luau` is the only code that finds these:
  `camp(zoneId)`, `offices()`, `inOffice(position)` and `campAt(position)`.

## 6. Data

- **Profile v2** adds:
  - `researchers`, mapping role id to `{ level, data, post }`
  - `tankCount` and `tankValue` for the Chemist
- **Snapshot** carries what the UI needs, including the set-up-until times.
- **Player attributes**: so every client can draw everyone's team, the
  server sets `Research_<RoleId> = "<post>:<level>"` on each Player. Clients
  only read them.
- **Remotes**:
  - `HireResearcher(roleId)` and `PostResearcher(roleId, post)`, client to
    server. Both are rate-limited and validated like `Shop.luau`.
  - `Forecast`, server to one client.

## 7. How they look

- Small, chunky storm scientists about two thirds of a player's height,
  made from simple parts (no meshes or assets), with 14 parts or fewer each.
  They have a rounded body, a head and goggles, a cream field coat with a
  Storm Society badge, and a hood in their role colour.
- **The instrument is the silhouette:**
  - Forecaster: a brass barometer on a tripod, plus a clipboard
  - Rod Tech: a tall copper rod with a coil and a cable into the ground
  - Analyst: a folding desk with a glowing screen and a ticker-tape printer
  - Chemist: a glass tank backpack that fills with cyan as her tank fills
  - Storm Chaser: a striped weather balloon on a tether that rises in storms
- They stand and work; they never follow the player.
  - Calm weather: idle motions (writing, adjusting the instrument, looking
    up).
  - Storms: they brace with hoods up, and the instruments crackle cyan.
  - When their perk fires they react: the Forecaster points, the Analyst
    prints tape, the balloon jerks.
- Unposted researchers hang around the Research Office.
- Neutral colours with one role accent. Neon only for "bottled lightning"
  cyan.
