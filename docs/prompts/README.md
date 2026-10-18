# Feature prompts

Each line is one prompt. Run them in this order, because later ones build
on earlier ones. Each prompt checks that what it needs is in the checkout
and stops if it isn't. To run one, say: "Do `docs/prompts/<file>`".

1. `1-boots.md`: boots you buy that make you faster inside storm zones.
2. `2-progression.md`: two upgrade lines (bottles and boots), zone gates
   by bottle tier, a next-goal tracker, and the extra in-between tiers.
3. `3-premium-zone.md`: a zone only Roblox Premium members can enter.
4. `4-next-zone.md`: adds the next new zone from its plan, with a new map
   theme, values, a new bottle and new boots. **Run it once per zone** (it
   ticks off the plan as it goes).
5. `5-retention.md`: retention and progression stats on the Creator
   Dashboard, including where players are when they leave. It can run any
   time after prompt 2.

Researchers (all five parts done) live in `researchers/`.

## Rules for every prompt (keep token use low)

- Run on the branch Update Game pulls from (see `CLAUDE.md`), and commit
  and push there when done.
- Read `CLAUDE.md` and the files the prompt lists. For anything else, grep
  for the lines you need instead of opening whole files.
- Don't open or edit files the prompt doesn't list. `WeatherLab` is the
  live world style. Never edit the alternate styles (`StormPunk`,
  `SkyIsles`). If one of them fails a check because of a new zone, report
  it instead of fixing it.
- Plan once, then write each file in one pass. No refactors, renames or docs
  beyond what the prompt asks for.
- Changing the profile shape means bumping `CURRENT_VERSION` in
  `PlayerData` by one from whatever it is now, adding the migration step,
  and updating `DEFAULT_PROFILE`.
- Put balance numbers in `Config`. Prices and values in the prompts are
  starting suggestions.
- Run the checks once at the end. Fix and re-run at most once more. Look at
  any render image at most twice.
- If `lune`, `stylua` or `selene` is missing, add it to `rokit.toml` and run
  `rokit install`, one try only. If that fails, skip that check and say so.
- Only use the Roblox Studio MCP if it's already connected: one short play
  test, then stop. The TEST button (`Systems/DevCommands`) gives you Volts
  for testing purchases.
- End by telling the user what to check in Studio after clicking Update
  Game.
