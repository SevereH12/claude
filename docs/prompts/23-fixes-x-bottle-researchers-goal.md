# Prompt 23: the missing X, the flying bottle, researchers changing zones, research goals

Follow the rules in `docs/prompts/README.md`. **One run.** Every part
starts by finding the cause: read the code, explain the cause in the
commit message, and fix that cause, not the symptom. The user's
screenshots are in `docs/prompts/img/`; open them with the Read tool.

- [x] All four fixes, checked and pushed

## 1. The close button shows no X (`img/23-offer-x.png`)

The offer card's close button (top right) is an empty dark box. It's set
to `"✕"` (U+2715), which Luckiest Guy, the button font, doesn't have.

- Use a plain `"X"`, as `UI.window` does, in `Controllers/Offers.luau` and
  `Controllers/BoostsUI.luau`.
- Grep `src/client` for any other button or label text the two game fonts
  may not have (✕ ✖ ✓ ✔ ☰ ▶ and similar; emoji are fine) and fix those
  too.

## 2. A bottle flies around as the player walks (`img/23-flying-bottle.png`)

Something bottle-shaped floats away from the player (out over the water)
and moves around as they walk.

**Find out what it is.** Candidates:
- the bottle held in the hand (`Systems/Bottles.attach`: a `Weld` to
  RightHand)
- the Chemist's tank, the Storm Chaser's balloon or another researcher
  prop (`Controllers/Researchers`, `Lib/ResearcherModels`)
- an effect that follows the player (`Controllers/StrikeFX`, `Tutorial`,
  `AfkUI`)
- something left behind by streaming (`Workspace.StreamingEnabled` is on;
  client-made parts aren't streamed)

**Fix it.** Whatever it is should stay attached where it belongs or not
exist. Check respawn and teleport between worlds too, and check that the
held bottle stays in the hand with every boot, including Jet Boots.

## 3. Researchers don't move to the next zone properly (`img/23-researchers.png`)

The circled spots are research camps by the zone boardwalks. Researchers
posted to a new zone don't end up where they should. Read
`Controllers/Researchers.luau` (how a model is placed at a post's camp
deck from the `Research_<RoleId>` attribute), `Util/ResearchSites` (`camp`)
and `Systems/Research` (posting, setting up, what's published).

Check each step:
- does re-posting move the model? It must be removed from the old camp
  and placed at the new one, even when the post is in another world.
- is the camp found for every zone, in all 3 worlds, including when
  streaming hasn't loaded it yet? (Wait for it, then place.)
- are the deck spots on the deck, facing the zone?
- does the "setting up" countdown show at the new camp?
- does a promotion, an Ascension (researchers sent back to the Office) or
  a rejoin leave a model behind?

Fix every case that's wrong.

## 4. Goals only send you to Research for Glints

`Util/Goals.luau` (prompt 21) also suggests hiring the next researcher, so
the goal card often says "HIRE: …" and sends the player to Research. The
user wants Research goals **only for promotions (Glints)**.

- Remove the hire goal: from the list, its HUD title, its tap target and
  its test cases (`tools/harness/test_goals.luau`, keeping the rest).
- The promote goal stays.

## Checks

- **Before pushing**, re-read the whole diff for wrong argument counts,
  unused names, lines over 100 columns, require cycles and nil access.
- **CI must pass** on the final commit: stylua, selene, every harness test
  and the map checks.
- **The report** gives the cause found for 2 and 3, and the "check in
  Studio" steps for each fix.
- Tick it, commit and push.
