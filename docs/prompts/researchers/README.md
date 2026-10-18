# Researchers: build plan

The Researchers feature is too big for one session, so it is split into
parts. Each part fits in one usage limit, ends with the game working, and
is committed and pushed before the next part starts.

The design (what Researchers are and how they behave) is in `design.md`.
Each part reads only the sections of it that it needs.

## How to run the parts

**All at once.** With the Claude Code CLI, on the branch Update Game pulls
from, run:

    tools/run_researchers.sh

It runs each unfinished part in order, each in a fresh session. If it
stops (a usage limit or a failed part), run it again and it carries on from
the first unticked part.

**One at a time.** Start a new Claude Code session and say:

> Do `docs/prompts/researchers/part-1-map.md`

Either way, run every part on the same branch, the one Update Game pulls
from (see `CLAUDE.md`). Each part checks that the previous one is in the
checkout and stops if it isn't.

## Progress

Each part ticks its own box when it's done.

- [x] Part 1: Research Office and camps on the map (`part-1-map.md`)
- [x] Part 2: hiring, posting, levels and the Research panel (`part-2-hiring.md`)
- [x] Part 3: perks I, Forecaster, Rod Tech and Analyst (`part-3-perks-1.md`)
- [x] Part 4: perks II, Chemist and Storm Chaser (`part-4-perks-2.md`)
- [ ] Part 5: the researchers you can see (`part-5-models.md`)

## Rules for every part (keep token use low)

- Read `CLAUDE.md`, the design sections the part names, and the files the
  part lists. For anything else, grep for the lines you need instead of
  opening whole files.
- Don't open or edit files the part doesn't list. `WeatherLab` is the live
  world style: edit it only where a part says to. Never edit the alternate
  styles (`src/server/World/Styles/StormPunk` and `SkyIsles`) or
  `docs/styles`.
- Plan once, then write each file in one pass. No refactors, renames or docs
  beyond what the part asks for.
- Run the checks once at the end. Fix and re-run at most once more. Look at
  any render image at most twice.
- If `lune`, `stylua` or `selene` is missing, add it to `rokit.toml` and run
  `rokit install`, one try only. If that fails, skip that check and say so.
- Only use the Roblox Studio MCP if it's already connected. Then do one
  short play test: sync, play, check the output for
  `[StormBottler] server started` and `client started` with no errors, try
  the part's feature once, and stop.
- Finish by ticking the part's box above, then commit and push. Tell the
  user what to check in Studio after clicking Update Game.
