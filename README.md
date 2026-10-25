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

In the game, `src/client/Lib/Sfx.luau` is the only code that plays sounds
(`Sfx.play(name)` for 2D, `Sfx.playAt(name, position)` for 3D). Buttons,
panels and toasts get their sounds in `Lib/UI`; everything else plays its
sound where it happens. Every sound goes through a SoundGroup (Music,
Ambience, SFX, UI): `Config.SOUND_MIX` sets their volumes, and the Sound tab
of the players' ⚙️ SETTINGS panel scales them.
In Studio, TEST > 🎁 REWARDS > **🔊 Sound board** plays every sound in turn
with its name.

### Music and ambience

- **Music** (`Controllers/Music`) plays the world you're in, calm or storm:
  `Config.MUSIC[<world id>].Calm / .Storm`, shuffled, crossfading over
  `Config.MUSIC_FADE` seconds when the weather or world changes, and dipping
  for big moments (`MUSIC_DUCK`). The tracks are Roblox's licensed partner
  music (APMOfficial, DistrokidOfficial only), instrumental only: the search keeps a track only when its listing says it has no vocals. `python3
  tools/audio/music_search.py` searches the Creator Store for each slot and
  writes `docs/audio/music-shortlist.md`; TEST > 🎁 REWARDS > **🎵 Music
  audition** (Studio) plays every candidate for 20 s so you can pick.
- **Ambience** (`Controllers/Ambience`): wind and waves when calm; rain,
  gusts and distant rumbles in a storm; a hum at every sell station.
  Volumes in `Config.AMBIENCE`.

**Where each volume lives**

| What | Where |
| --- | --- |
| A group's overall level (Music, Ambience, SFX, UI) | `Config.SOUND_MIX` |
| A player's own sliders and mute | ⚙️ SETTINGS on the menu (saved in their profile) |
| One sound's level | `VOLUME` / `VOLUME_OVERRIDE` in `tools/audio/bank.py` (then run it) |
| The loudness every effect is made at | `GROUPS` in `tools/audio/palette.py` |
| Calm and storm ambience, gusts, the hum's reach | `Config.AMBIENCE` |
| The music's tracks, crossfade and ducking | `Config.MUSIC`, `MUSIC_FADE`, `MUSIC_DUCK` |

The mix, worked out: gameplay effects land at about -21 dBFS, thunder -15,
rewards -19, UI -33 (the quietest), music about -24 (licensed tracks are
mastered near -14, times 0.32), rain about -31 and calm waves -36, so the
music sits under the effects and the ambience under the music, and a storm's
thunder is the loudest thing in the game.

## Settings

The ⚙️ SETTINGS tile on the menu (or Comma) opens a panel with four tabs:
Controls, Sound, Graphics and Accessibility & HUD. Every setting is
described once, in `src/shared/Util/Settings.luau` (its kind, default,
limits and tab), and the panel builds its rows from that list. Settings
save to the player's profile, so they follow them to every device; the
server only stores what `Settings.sanitize` lets through.

- **Controls**: every shortcut (Menu, Shop, Research, Teleport, Boosts,
  Rewards, Remote Sell, Settings) can be rebound, for keyboard and
  controller. Keys Roblox or moving needs (W A S D, arrows, Space, Shift,
  `/`, Enter, Tab, Esc, F9 to F12; A, B, Start, Select and the sticks) are
  refused, and taking another action's key swaps them. The key chips on
  buttons show the player's own keys.
- **Sound**: Master, Music, Effects, Ambience and UI volumes, and Mute all.
- **Graphics**: a Quality preset (Low, Medium, High; changing any one
  setting makes it Custom) for rain and particles, lightning glow, shadows,
  bloom and colour, far decorations, other players' lightning and
  researchers; plus Field of view. A new player starts on the preset that
  suits their device (phone Low, tablet Medium, PC and console High; one
  lower when their Roblox graphics level is 3 or less). A game can't change
  the player's own Roblox graphics level.
- **Accessibility & HUD**: Reduce flashing, Camera shake, Colourblind rings
  (dashed rings with a ⚡ and a high-contrast zone colour set), Text size,
  and switches for pop-ups, name tags, pass offers, chat announcements and
  gift reminders. Before their first storm every player is asked once
  whether to reduce flashing. Warning rings always show.
- Code reads settings with `Lib/SettingsStore` (`get`, `set`, `watch`,
  `Changed`), so changes apply at once.

## Storm surprises

Storms aren't all the same. The server decides everything here; players'
screens only draw it. The maths is in `src/shared/Util/Weather.luau`
(tested by `tools/harness/test_weather.luau`), and the numbers are in
`Config.BOLT_TYPES`, `Config.BALL_LIGHTNING`, `Config.SUPERCELL` and
`Config.EVENTS`.

- **Rare bolts**: each strike has a 2% chance to be **Golden** (worth x10),
  0.4% to be **Rainbow** (x25, plus 5 minutes of a random boost for the
  catcher and a chat line for the whole server) and 1% to be **Ball
  lightning** (x5): an orb that drifts across the zone for 8 seconds, and
  the first player with room in their bottle who touches it catches it.
  The ring shows the type (gold, rainbow colours, or the orb) before the
  bolt lands, so players can race for it. Luck and the assay still double
  on top, and a rare bolt fills the same bottle space as a normal one.
- **Supercells**: about once an hour (45 to 75 minutes apart) a storm turns
  into a 3-minute Supercell: twice the strikes, golden bolts 5x as likely,
  a darker purple sky and a banner. The storm timer counts down for 30
  seconds before it starts, so players can get into a zone.
- **Scheduled events**: `Config.EVENTS` lists events with a start, an end
  and a sale multiplier. **Double Volts Weekend** runs every Saturday 00:00
  to Sunday 23:59 UTC and doubles every sale (AFK and Remote Sell too). A
  chip under the goal card shows the event and its time left. To add an
  event, add a line: a weekly one uses times like `"Sat 00:00"`, a one-off
  uses Unix times.
- **Testing in Studio**: the TEST panel's REWARDS list has **Force golden
  bolt** (drops one where you stand, in a zone), **Supercell in 30 s** and
  **Pretend event** (turns Double Volts Weekend on).

### Server goal and Server Surge

Everyone in a server fills one meter together (`Systems/ServerGoal`, the
numbers in `Config.SERVER_GOAL`).

- **Filling it**: every Volt sold in the server counts, at a station or
  with Remote Sell. The AFK Lounge doesn't count.
- **How big it is**: each player's grinding rate (what the AFK screen
  works out for their best zone) added up, times 15 minutes. So a full
  server of late-game players and two new players both take about 15
  minutes. It's worked out again when someone joins or leaves, and it
  never drops below what's already filled plus 10%, so it can't get stuck.
- **Server Surge**: a full meter starts 10 minutes of 2x Volts for
  everyone, with a banner and a chat line. It stacks with a Server Storm
  (both on: 4x). The meter then empties and the next goal is 1.5x bigger;
  every hour the size goes back to normal.
- **On screen**: a slim meter under the goal card ("⚡ Server goal 62%", or
  the Surge's time left). Tap it to see this round's top 3 helpers.
- **Testing in Studio**: the TEST panel's REWARDS list has **Server goal
  +25%** (four taps start a Surge); **Clear boosts** ends a Surge too.

## Quests and stat counters

The game counts what each player does (`Util/Stats`, `Systems/Stats`):
bolts caught (overall, by bolt type, by zone and by type in each zone),
sales, full bottles sold, bottles filled, Volts earned (from sales and the
AFK Lounge), minutes played, researcher promotions and gifts sent. Each
counter is kept three times: for good, for today (a new UTC day starts it
again) and for this week (Monday 00:00 UTC starts it again). They're
saved with the player.

- **Quests**: every day each player gets 3 daily quests and every week 1
  weekly quest, picked from the templates in `Config.QUESTS` (catch bolts,
  catch bolts in one of your best zones, sell full bottles, catch a golden
  bolt, earn Volts, play for a while, promote a researcher). The pick comes
  from your user id and the date, so you get the same quests all day.
- **Size**: amounts grow with your bottle. "Earn Volts" is minutes of your
  grinding rate in your best zone, so it takes about as long early or late.
- **Rewards**: like the daily streak (Volts from your best zone, or timed
  boosts). The weekly quest pays about five daily ones.
- **Reroll**: one free reroll a day swaps any unfinished quest.
- **On screen**: REWARDS has a QUESTS tab: each quest has a progress bar,
  its reward and a CLAIM (or REROLL) button. A toast pops up when a quest
  hits 100%, and the menu's dot lights up while one is ready to claim.
- **Testing in Studio**: the TEST panel's REWARDS list has **Complete
  quest** (your first unfinished quest counts as done) and **Next day**
  (new daily quests).

### Storm Log

The Storm Log is a collection book in the REWARDS panel's **LOG** tab
(`Util/StormLog`, `Systems/StormLog`, `Lib/StormLogTab`). It has four pages:

- **Bolts**: every bolt type (normal, Golden, Rainbow, ball lightning) in
  every zone.
- **Places**: every world and every zone you've been in.
- **Team**: every researcher at every rank (hiring them is the first).
- **Weather**: being in game for a Supercell and for each scheduled event.

It's all worked out from the stat counters (new counters remember the
zones and worlds you've visited and the Supercells and events you've
seen), so the only thing saved is which rewards you've claimed.

- **Rows**: finishing a row (say every bolt type in Mesa) gives a one-time
  reward (Volts or a boost) with its CLAIM button.
- **Pages**: each finished page gives **+2% Volts for good** on every sale
  (and in the AFK Lounge), up to +8% for all four. The numbers are in
  `Config.STORM_LOG`.
- **On screen**: each page has a progress bar; found entries show their
  icon and missing ones a grey "?" (tap one to see how to find it). New
  entries and finished rows pop up a toast, and the menu's dot lights up
  while a row's reward is waiting.
- **Testing in Studio**: the TEST panel's **+Log entry** button marks the
  next missing entry as found (Team entries need a real hire or promotion).

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
