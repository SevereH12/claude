# Feature prompts

Each line is one prompt. Run them in this order, because later ones build
on earlier ones. Each prompt checks that what it needs is in the checkout
and stops if it isn't. To run one, say: "Do `docs/prompts/<file>`".

1. `1-boots.md`: boots you buy that make you faster inside storm zones.
2. `2-progression.md`: two upgrade lines (bottles and boots), zone gates
   by bottle tier, a next-goal tracker, and the extra in-between tiers.
3. `3-premium-zone.md`: a zone only Roblox Premium members can enter.
4. `4-next-world.md`: turns one of the two unused maps (StormPunk, then
   SkyIsles) into a whole new world you reach by portal once you own its
   bottle, with three zones, new bottles and new boots. It reviews the map
   first and the result before pushing. **Run it twice**, once per map (it
   ticks off its plan; StormPunk is done).
5. `5-retention.md`: retention and progression stats on the Creator
   Dashboard, including where players are when they leave. It can run any
   time after prompt 2.
6. `6-ui-devices.md`: **run it twice.** Part A replaces the HUD buttons
   with one MENU button whose Shop, Research, Teleport (between worlds) and
   Passes (a coming-soon placeholder) buttons fly out from the centre. Part B makes every screen
   fit and work on PC, phone (portrait and landscape), iPad and console.
7. `7-temp-text-and-charge-size.md`: makes every on-screen message go away
   after a few seconds (second fix, with a test), and makes bigger zones
   fill more of the bottle per strike while always paying more Volts per
   full bottle.
8. `8-game-passes.md`: **run it three times.** Part A: the pass system,
   the store, and 2x Volts, Remote Sell, Big Bottles and Lucky Charges.
   Part B: Lab Grant, VIP, Bolt Colours and Jet Boots. Part C: Volts packs,
   offers when a pass would help, a free 2x Volts trial, and store stats.
9. `9-rewards.md`: **run it twice.** Part A: timed boosts, a 7-day login
   streak, playtime gifts and a REWARDS panel. Part B: +10% Volts for
   members of the Super Studio group (with an in-game join button), "reward
   ready" nudges and stats. No like rewards (Roblox can't detect likes, and
   its rules forbid rewarding them).
10. `10-gifting.md`: **run it twice.** Part A: gift any game pass to anyone
    by username (a matching "Gift:" product, a safe inbox, live delivery
    across servers). Part B: boosts you can buy for yourself or gift, the
    Boost Bundle, and Server Storms (2x Volts for the whole server). All 13
    products already exist, off sale (`tools/store/store_ids.json`).
11. `11-sound.md`: **run it three times.** Part A: original sound effects
    generated in code from one palette (one key, one reverb, set loudness),
    reviewed, packed into a few files and uploaded. Part B: every button,
    strike, sale and reward plays them, with Music / Effects / Ambience
    volume settings. Part C: licensed music (APM and DistroKid catalogues)
    that crossfades between calm and storm tracks per world, plus ambience.
12. `12-afk-zone.md`: **run it twice.** Part A: the AFK Lounge in the
    hub, paying 10% of the player's grinding rate in their best zone (bag
    value ÷ time to fill, from strikes needed and boot speed, with every
    pass, boost, group bonus and Server Storm counted), and an AFK screen
    that shows the maths. Part B: stays connected overnight (VirtualUser,
    with a server-hop backup), a Teleport entry and stats.

Researchers (all five parts done) live in `researchers/`.

## Rules for every prompt (keep token use low)

- Run on the branch Update Game pulls from (see `CLAUDE.md`), and commit
  and push there when done.
- Read `CLAUDE.md` and the files the prompt lists. For anything else, grep
  for the lines you need instead of opening whole files.
- Don't open or edit files the prompt doesn't list. `WeatherLab` (world 1)
  and `StormPunk` (world 2) are live world styles. Don't edit `SkyIsles`
  except in prompt 4.
  Otherwise, if one of them fails a check because of a new zone, report it
  instead of fixing it.
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
