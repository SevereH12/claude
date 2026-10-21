# Prompt 7: make text go away, and bigger zones fill the bottle faster

Follow the rules in `docs/prompts/README.md`. There are two independent
jobs; do both, then commit once.

## Job 1: on-screen text must go away after a bit (second attempt)

This has been asked for before and text still stays on screen. So don't
patch one message: find **every** piece of text that can appear and prove
each one disappears.

### Read only

- `src/client/Lib/UI.luau`
- `src/client/Controllers/ZoneBanner.luau`, `ZoneGates.luau`, `HUD.luau`,
  `Travel.luau` and `ResearchUI.luau`
- the `popup` function and its callers in `StrikeFX.luau`
- grep `src/client` for any other `.Text =` on a label that is shown and
  hidden

### Steps

1. **Make a list first.** In your reply, write a short table of every
   message-style text (anything that isn't a constant readout), with:
   - where it's shown
   - what hides it
   - whether anything can stop it hiding

   Look especially for:
   - **re-show loops**: a loop calling `show` every 0.2s while you stand near
     a gate or in a zone keeps a banner up forever
   - **stale delays**: a `task.delay` hide from an earlier show that's
     cancelled, or hides the wrong message
   - **tweens that end up visible**
   - **labels whose text is set but whose frame never hides**
2. **One message system.** Add `UI.toast(text, kind?, seconds?)` in
   `Lib/UI` (or finish it if prompt 6 already added one):
   - **Where**: top-centre, inside the safe area.
   - **How long**: fades out after `seconds`, 3 by default.
   - **Duplicates**: the same text while it's showing restarts its timer
     instead of stacking.
   - **How many**: at most two at once, so the oldest goes first.
   - **Stale hides**: every hide checks a generation number, so an old hide
     can't touch a newer message.
3. **Route every warning, hint and notice through it**:
   - bottle full
   - zone locked or needs a bottle, and Premium only
   - "Visit the Research Office"
   - unlocks
   - level-ups
   - travel and portal notes
   - the "speed boost" leave note

   Zone title cards can keep their own big banner, but it must also hide
   after its time, with the same generation guard.
4. **Show each one once per event**, not every loop tick:
   - The gate explanation shows when you arrive within `GATE_NEAR` and not
     again until you've gone past `GATE_FAR` (check that this really
     works).
   - Bottle full shows when it fills, then at most every 20 seconds while
     it stays full.
5. **Readouts that should stay**: Volts, the storm timer, the bottle bar
   count, the goal card, the TANK count and a button's LOCKED state. The
   bottle bar must not keep "FULL! SELL AT THE POWER PLANT" as permanent
   text; it glows when full instead.
6. **Test**: put the toast queue logic in a pure function with an
   injectable clock, and add `tools/harness/test_toast.luau` covering:
   - a toast expires
   - the same text restarts its timer instead of duplicating
   - the cap of two
   - an old hide can't hide a newer toast

## Job 2: bigger zones take up more of the bottle per strike

Each zone gets `chargeSize`: how many bottle units one caught strike uses.
Bigger zones (later in progression) use more space per strike. **A full
bottle must always be worth more Volts in a bigger zone**, so Volts per
bottle unit (`chargeValue / chargeSize`) must strictly go up from zone to
zone.

### Read only

- `src/shared/Config.luau`, `Types.luau`, `Util/Formulas.luau` and
  `Util/Progression.luau`
- the catch loop in `src/server/Systems/Strikes.luau` (grep
  `chargeCount +=`) and the premium value code next to it
- the Chemist tank and decant code in `src/server/Systems/Research.luau`
  (grep `chargeCount`, `tankCount`)
- the bottle bar in `src/client/Controllers/HUD.luau` and the strike popup
  in `StrikeFX.luau`

### Build

1. **Config**: add `chargeSize` to `ZoneDef` and every zone. Suggested
   values (Volts per strike unchanged):

   | Zone | Size per strike | Volts per strike | Volts per unit |
   | --- | --- | --- | --- |
   | Shoreline | 1 | 5 | 5 |
   | Mesa | 2 | 20 | 10 |
   | Generator Yard | 3 | 60 | 20 |
   | Tidewire Beach | 5 | 150 | 30 |
   | Thunderhead Mesa | 8 | 500 | 62.5 |

   - The premium zone uses the size of the player's best zone, and pays its
     1.5x value on top, so it's always the best per unit.
   - Any zone added later must follow the same rule, so say so in a Config
     comment.
2. **Catching**:
   - A catch adds `chargeSize` units and the zone's value.
   - If the bottle has less room than `chargeSize`, fill the remaining room
     and pay that fraction of the value, rounded down, at least 1.
   - A bottle is full when `chargeCount >= capacity`, as now.
   - Apply the same rule to the Chemist's tank, Storm Chaser balloon bolts
     and decanting (units and value move together).
3. **Client**:
   - The bottle bar shows units ("JAR 3 / 5"), so it fills faster in big
     zones.
   - The catch popup still shows Volts.
   - The zone banner tagline, the shop or the zone sign shows the size, for
     example "Each bolt fills 3".
4. **Test**: add to `tools/harness/test_formulas.luau` (or a new
   `test_charge.luau`). Order the zones by progression (world, then
   `requiresBottle`, then `order`; premium excluded) and check:
   - Volts per unit strictly increases from each zone to the next
   - a full bottle of the zone's required tier is worth strictly more Volts
     than the same bottle filled in the previous zone
   - every zone's required bottle holds at least 5 of its strikes
   - a partial fill pays the right fraction and is at least 1

## Done means

- `stylua src` and `selene src` are clean.
- `test_toast.luau`, `test_formulas.luau` and the other harness tests pass.
- `tools/check_world.sh WeatherLab <scratch dir>` still passes.
- If the Studio MCP is connected, play once:
  - walk to a locked gate and stand there 10 seconds: the message shows once
    and goes away
  - fill your bottle: the warning goes away
  - catch in Mesa: the bar jumps by 2
- Commit and push.
