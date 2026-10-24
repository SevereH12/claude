# Storm Bottler Simulator

Catch lightning in bottles on a stormy island, sell the charges at the Power
Plant for Volts, and buy bigger bottles.

## Features

- **Storm cycle**: 90s storms, 20s calm (first storm 8s after the server
  starts). The sky darkens, clouds roll in and it rains during storms.
- **Zones** with glowing force-field borders and entrance arches:
  - **Shoreline** (yellow): everyone in the circle catches. 5 Volts per charge.
  - **Mesa** (orange, up the ramp): only the closest player catches. 20 Volts per charge.
- **Strikes**: a ring and light pillar appear 1.5s before each bolt. Stand in
  the ring to catch a charge. The bottle is always in your hand.
- **Speed**: normal speed inside zones, fast everywhere else.
- **Selling**: step on the glowing SELL pad at the Power Plant.
- **Bottles**: Jar (5) → Flask (15) → Battery Pack (40) → Storm Cell (100).
- **Saving**: Volts, bottle tier and held charges save (retries, session
  locking, autosave every 60s, save on leave and shutdown).
- **HUD**: Volts, storm timer, bottle fill bar, server city meter (placeholder).

Every number (timings, values, prices, radius, walk speeds) is in
`src/shared/Config.luau`.

## Getting it into Roblox Studio

**One-time setup**

1. This GitHub repo must be **public** (the plugin downloads from it).
2. Install the updater plugin: in Studio, **Plugins** tab → **Plugins
   Folder**, then drag `StormBottlerUpdater.rbxmx` into the folder that opens.
   Restart Studio.

**Every update**

1. Open your Storm Bottler place in Studio.
2. **Plugins** tab → **Update Game**. Allow the web-access popup the first time.
3. Press **Ctrl+S** to save, then **Play**.

Build the plugin yourself with `rojo build plugin/plugin.project.json -o StormBottlerUpdater.rbxmx`.

### Testing saving in Studio

Publish the place, then Game Settings > Security > **Enable Studio Access to
API Services**. Without it the game still runs, but uses a temporary profile
that doesn't save (a warning in Output says so).

### Protecting a hand-edited map

The updater rebuilds the map each time while `Workspace.Map` has the
attribute `AutoBuilt = true`. Delete that attribute once you start editing
the map by hand and the updater will leave it alone.

## Reading the stats

`Systems/Analytics` sends overall stats to the Roblox Creator Dashboard
(create.roblox.com → your experience → **Analytics**):

- **Funnels**: the Onboarding funnel. Joined → Entered a zone → First catch
  → First sell → First upgrade → Entered a second zone → Hired a researcher.
  Each player counts once per step, ever.
- **Progression**: the Bottles and Boots tiers bought, and the Zones each
  bottle unlocks.
- **Custom events**: `SessionMinutes` (average minutes per session) and
  `Left` (number of players who left). Split them by Custom Field 1 for
  where players were when they left (a zone, `Camp:<Zone>`, `SellStation`,
  `ResearchCenter`, `Hub`, `Boardwalk`, `Water` or `Respawning`), Field 2
  for their bottle (`Bottle <n>`) and Field 3 for `Storm` or `Calm`.
- **Economy**: Volts earned at the sell station (Source) and spent on
  bottles, boots and researchers (Sink), per item.

Data only shows up after the place is published and played on Roblox, not
from Studio, and can take a day to appear. The built-in **Retention** and
**Engagement** pages already show D1/D7 retention and average session time.

## Selling passes

The Boosts store (MENU → BOOSTS) sells the Game Passes in `Config.PASSES`;
`Systems/Passes` checks who owns what and grants purchases on the server.
To add or change a pass:

1. On the Creator Dashboard: your experience → **Monetization** →
   **Passes** → **Create a Pass**. Upload a 512x512 image and give it a
   name and description, then set it on sale with a price.
   (`tools/store/create_store.py` already made all eight passes this way,
   off sale; their ids are in `tools/store/store_ids.json`.)
2. Copy the pass's asset id into its `id` in `Config.PASSES`. A pass with
   `id = 0` shows COMING SOON. The store shows the price Roblox reports;
   `price` in Config is only shown until that loads.
3. Test in Studio with the TEST panel's **PASSES** toggles ("Pretend owns"):
   they only work in Studio. Pressing BUY in Studio opens a purchase window
   that says it's a test purchase, so no Robux are spent.
4. See sales under **Monetization** → **Passes** → **Analytics**.

The VOLTS tab sells the Volts packs in `Config.VOLT_PACKS` (Developer
Products, granted by `Systems/Receipts`, each purchase once). A pack gives
`charges` × the bolt value of the buyer's best zone, so it grows as they
progress. To add or change a pack:

1. On the Creator Dashboard: your experience → **Monetization** →
   **Developer Products** → **Create a Developer Product**. Give it an
   image, name, description and price. (`create_store.py` made all four
   packs this way too, off sale; their ids are in `store_ids.json`.)
2. Copy its product id into the pack's `productId` in `Config.VOLT_PACKS`
   (`0` shows COMING SOON).
3. Test in Studio: BUY opens a test purchase window (no Robux spent) and
   the Volts arrive once. Studio only saves them if **Enable Studio Access
   to API Services** is on (see Testing saving in Studio).
4. See sales under **Monetization** → **Developer Products** →
   **Analytics**, and the store funnel, offers and trial under
   **Analytics** (Funnels: Store; Custom events: OfferShown, OfferTapped,
   TrialStarted, TrialEnded).

## Rewards

The REWARDS panel (MENU → 🎁 REWARDS; a red dot means something is ready):

- **7-day login streak**: one reward per day (a new day starts at
  midnight UTC). Coming back the next day continues the streak; missing a
  day, or the day after day 7, starts again at day 1
  (`Config.DAILY_REWARDS`).
- **Playtime gifts**: six gifts every visit, at 5, 10, 20, 30, 45 and 60
  minutes of play (`Config.PLAYTIME_GIFTS`).
- Volts rewards are counted in charges × the bolt value of the player's
  best zone, so they're worth the same playtime early or late. Boost
  rewards (2x Volts, Lucky, Big Bottles) give a pass's effect for a while;
  they only count down while playing and stack up to 2 hours. A boost for
  a pass the player owns pays Volts instead.
- **Group bonus**: members of the group that owns the game get +10% Volts
  on every sale (`Config.GROUP_BONUS`), and a `[Member]` chat tag. The
  panel's group card has a JOIN button that opens Roblox's own join
  window; the server checks membership itself. To use a different group,
  change `Config.GROUP_ID` (the number in the group's web address) and
  `Config.GROUP_NAME`.
- Short reminders (toasts with OPEN): the daily reward when you join, each
  gift when it's ready, and the group once a visit after your first sale.

Test in Studio with the TEST panel's **🎁 REWARDS** tools: Next day, +5 min
playtime, Clear boosts and Pretend group member (Studio only). Stats are
under **Analytics**: custom events DailyClaimed, PlaytimeGift and
GroupJoined, and reward Volts in Economy (TimedReward).

## AFK Lounge

The Night Shift Lounge in Barometer Bay's village (or MENU → 🌀 TELEPORT →
AFK LOUNGE) pays Volts while you rest. Stand on its rug for 10 seconds and
you earn **10% of what you'd make grinding your best zone** (15% for
Roblox Premium members), paid every minute:

- The grinding rate counts your bottle (and Big Bottles), your boots (how
  many strikes you can reach), your best zone's bolt value, and everything
  that multiplies a sale: 2x Volts, VIP, Lucky Charges, running boosts,
  the group bonus and a Server Storm. It's worked out again every 15
  seconds, so a boost running out or a new purchase shows straight away.
  The AFK card's "How is this worked out?" shows every step.
- Boosts keep counting down while you're AFK (they're being used).
- Roblox normally disconnects you after 20 idle minutes. In the lounge the
  game keeps you connected; if that ever fails, it saves and moves you to
  a fresh server, back in the lounge.
- To tune it: `Config.AFK.rateFraction` (0.10) and `premiumRateFraction`
  (0.15). Stats: custom events AfkMinutes and AfkRejoin, and AFK Volts in
  Economy (Gameplay, AFK).

Test in Studio: stand in the lounge, then try the TEST panel's pretend
passes and Pretend Premium (the rate changes within 15 seconds) and
**🎁 REWARDS → 💤 Simulate idle 17 min** (teleports don't work in Studio,
so the backup only logs its attempt in the Output).

## Researcher ranks

Researchers have a **rank** (0 to 6) and can only work in zones of their
rank's tier or lower (tier = which bottle opens the zone: Shoreline 0,
Mesa 1, ... Ember Mesa 6). At level 5 you can promote one at the Research
Office: it costs **Glints** (one for every bolt you catch, of that zone's
tier; promotion to rank r takes Glints of tier r or higher), and sends the
researcher back to level 1 a rank higher, with a 10% stronger perk.
In the Research panel the Glints line sits at the top, each card shows the
rank as gold stars (the name tags above the models too), and a level-5
researcher's Hire button becomes **PROMOTE** (tap twice to confirm). Zones
above a researcher's rank show 🔒 in the post picker.

The numbers (`Config.RESEARCH_PRESTIGE`) come from
`python3 tools/balance/prestige.py`, which works out how much data and how
many Glints make the whole team ready about halfway through each new zone,
and checks Config is within 10%. Run it again whenever zones, bottles or
strike settings change. Studio TEST tools: **+500 research data** and
**+100 Glints (this tier)** under 🎁 REWARDS.

## Sound effects

Every effect and ambience loop is original, made in code by
`tools/audio/sfx.py` from one palette (`tools/audio/palette.py`: C major
pentatonic, a glassy shimmer, an electric crackle, one small room, a
loudness target per group). To change a sound, edit its function in
`sfx.py`, then run:

```
python3 tools/audio/sfx.py      # WAVs in tools/audio/out/ (listen to them there)
python3 tools/audio/review.py   # review.png + review.md; fails on a bad peak, level, loop seam or note
python3 tools/audio/pack.py     # 3 effect sheets + 4 loops as .ogg, layout in sheets.json
python3 tools/audio/upload.py   # uploads changed files to the group, writes sound_ids.json and SoundBank.luau
```

Uploads cost one of the 10 a month an unverified account gets, so only
changed files are sent. Running `upload.py` again also re-checks moderation.

## Code layout

- `src/shared` → ReplicatedStorage.Shared: Config, Types, Remotes, Net, formulas, zone geometry
- `plugin/` → the Studio updater plugin (not part of the game)
- `src/server` → ServerScriptService.Server
  - `Systems/`: PlayerData (saving), Map, StormCycle, Strikes, Bottles, Movement, Selling, Shop, Sync
  - `Lib/`: MapBuilder, RateLimit
  - `World/`: the map framework and its three style packs (WeatherLab is live).
    The ground is built from parts (`World/Blocks`), not Roblox Terrain.
- `src/client` → StarterPlayerScripts.Client
  - `Controllers/`: State, Storm, StrikeFX, HUD, ShopUI, ZoneBanner
  - `Lib/`: UI helpers

## Checks

- Format: `stylua src`
- Lint: `selene src`
