# Researchers: build plan

The Researchers feature is too big for one session, so it is split into
parts. Each part fits in one usage limit, ends with the game working, and
is committed and pushed before the next part starts.

The design (what Researchers are and how they behave) is in `design.md`.
Each part reads only the sections of it that it needs.

## How to run a part

Start a new Claude Code session on this repo and say:

> Do `docs/prompts/researchers/part-1-map.md`

Run the parts in order. **Run every part on the same branch** (the one
Update Game pulls from, see `CLAUDE.md`), or merge each part before starting
the next. Each part checks that the previous one is in the checkout and
stops if it isn't.

## Progress

Each part ticks its own box when it's done.

- [ ] Part 1: Research Office and camps on the map (`part-1-map.md`)
- [ ] Part 2: hiring, posting, levels and the Research panel (`part-2-hiring.md`)
- [ ] Part 3: perks I, Forecaster, Rod Tech and Analyst (`part-3-perks-1.md`)
- [ ] Part 4: perks II, Chemist and Storm Chaser (`part-4-perks-2.md`)
- [ ] Part 5: the researchers you can see (`part-5-models.md`)
- [ ] Part 6 (later): camps and office in the world framework (`part-6-framework.md`).
  Only do this when a new world style is about to replace Legacy.

## Rules for every part (keep token use low)

- Read `CLAUDE.md`, the design sections the part names, and the files the
  part lists. For anything else, grep for the lines you need instead of
  opening whole files.
- Don't open or edit files the part doesn't list. Never touch the
  unfinished world styles (`src/server/World/Styles/StormPunk`, `SkyIsles`,
  `WeatherLab`) or `docs/styles`.
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
