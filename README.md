# Storm Bottler Simulator

Catch lightning in bottles on a stormy island, sell the charges at the Power
Plant for Volts, and buy bigger bottles.

## Features

- **Storms**: 90 s storms and 20 s of calm. During a storm, lightning
  strikes the storm zones: a ring appears 1.5 s before each bolt, and
  standing in it catches the charge. Rare bolts (Golden, Rainbow, ball
  lightning), Supercells and Server Storms make some storms special.
- **Three worlds**, joined by portals: **Barometer Bay** (Shoreline,
  Mesa, and Aurora Reef for Roblox Premium members), **Voltcliff Works**
  (Generator Yard, Tidewire Beach, Thunderhead Mesa) and **Stormspire
  Isles** (Rune Spire, Cloudshore, Ember Mesa). In "Shared" zones everyone
  in the ring catches; in the Mesas only the closest player does.
- **Selling**: stand at a Power Plant sell station (or use the Remote
  Sell pass) and your charges become Volts.
- **Progress**: 9 bottles (Jar to Storm Core) and 9 pairs of boots, a
  Research Office with 5 researchers to hire, post and promote, and
  **Ascension** (start again for +50% Volts per level).
- **Rewards**: a 7-day login streak, playtime gifts every day, daily and
  weekly quests, the Storm Log collection book, an AFK Lounge, a server
  goal that starts a 2x Server Surge, friends and invite rewards, and
  leaderboards.
- **Store** (everything off sale until the owner turns it on): 8 Game
  Passes, Volts packs, boosts and gifting.
- **Settings**, sound and music, a new-player tutorial and one-time
  gameplay tips after it, phone
  notifications, an admin panel, error reports and server-side movement
  checks.
- **Saving**: every player's profile saves with retries and session
  locking, every 60 s, when they leave and when the server shuts down.

Every number (timings, values, prices, radius, walk speeds) is in
`src/shared/Config.luau`. The sections below explain each part.

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
3. Test in Studio by pressing BUY: Studio opens a purchase window that says
   it's a test purchase, so no Robux are spent.
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
- **Playtime gifts**: six gifts a day, at 5, 10, 20, 30, 45 and 60
  minutes of play that UTC day (`Config.PLAYTIME_GIFTS`). Playtime is
  saved, so leaving and rejoining carries on where you were (it doesn't
  give the gifts again); a new day starts them again.
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

Stats are under **Analytics**: custom events DailyClaimed, PlaytimeGift and
GroupJoined, and reward Volts in Economy (TimedReward).

## Boots and storm drag

Boots make you run faster inside storm zones, and each zone's storm slows
you back down, so every new zone starts out as a fresh race to the bolts.

- **Boots**: each pair adds 4 more speed than the last (Puddle Jumpers +4
  up to Cloud Walkers +32), only inside storm zones. Between zones
  everyone runs at 30 (45 with Jet Boots), whatever boots they wear.
- **Storm drag**: every zone's storm takes some speed away. Nobody types
  it in: `Util/Speed` works it out from the bottle and boot prices, so a
  new zone gets one by itself. It's the bonus of the boots a typical
  player owns when that zone opens, where "typical" means someone who
  always buys the cheaper of the next bottle and the next boots (the
  order the HUD's goals show). So a typical player walks into every zone
  at 18 (a little over Roblox's default 16; `Config.WALK_SPEED_IN_ZONE`),
  and every pair they buy while there makes them faster again.
- Today's drags: Shoreline, Mesa and Aurora Reef 0, Generator Yard 12,
  Tidewire Beach 20, Thunderhead Mesa and Rune Spire 24, Cloudshore 28,
  Ember Mesa 32. The Premium zone drags like your best zone.
- Your speed in a zone never drops below 10 or goes above 28
  (`Config.ZONE_SPEED`), so leaving a zone always speeds you up.
- On screen: walking into a zone with drag shows a note ("Storm drag -12
  speed: you run 18 here"), and the shop's BOOTS rows say how fast each
  pair runs in your best zone.
- The AFK Lounge and the movement checks use the same speeds.
- To tune it: change `speedBonus` in `Config.BOOTS` (the drags follow by
  themselves), or `Config.ZONE_SPEED`. `tools/harness/test_speed.luau`
  checks the rules and prints every zone's drag and speeds.

## AFK Lounge

The Night Shift Lounge in Barometer Bay's village (or MENU → 🌀 TELEPORT →
AFK LOUNGE) pays Volts while you rest. Stand on its rug for 10 seconds and
you earn **10% of what you'd make grinding your best zone** (15% for
Roblox Premium members), paid every minute:

- The grinding rate counts your bottle (and Big Bottles), your boots
  against your best zone's storm drag (how many strikes you can reach),
  your best zone's bolt value, and everything
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

Test in Studio: stand in the lounge (teleports don't work in Studio, so the
server-hop backup only logs its attempt in the Output).

## Researcher ranks

Researchers have a **rank** (0 to 6) and can only work in zones of their
rank's tier or lower (tier = which bottle opens the zone: Shoreline 0,
Mesa 1, ... Ember Mesa 6). At level 5 you can promote one at the Research
Office: it costs **Glints** (one for every bolt you catch, of that zone's
tier; promotion to rank r takes Glints of tier r or higher), and sends the
researcher back to level 1 a rank higher, with a 10% stronger perk.
The Research panel has two tabs, **TEAM** and **LOG** (the Storm Log).
TEAM starts with a strip of Glints chips, one per zone tier in that zone's
colour (a dimmed "?" until you have some; tap one to see where those Glints
come from and which promotions they pay for). Under it each researcher has
a compact card: the rank as gold stars (the name tags above the models
too), level, perk, data bar, and two buttons: **📍 POST** opens one shared
post picker (Office, then the zones under each world's name; zones above
the researcher's rank show 🔒 and the rank they need), and HIRE becomes
**PROMOTE** once hired (it shows Glint progress like "✨ 37/65 Mesa" while
you're short; tap twice to confirm).

The numbers (`Config.RESEARCH_PRESTIGE`) come from
`python3 tools/balance/prestige.py`, which works out how much data and how
many Glints make the whole team ready about halfway through each new zone,
and checks Config is within 10%. Run it again whenever zones, bottles or
strike settings change.

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

### Music and ambience

- **Music** (`Controllers/Music`) plays the world you're in, calm or storm:
  `Config.MUSIC[<world id>].Calm / .Storm`, shuffled, crossfading over
  `Config.MUSIC_FADE` seconds when the weather or world changes, and dipping
  for big moments (`MUSIC_DUCK`). The tracks are Roblox's licensed partner
  music (APMOfficial, DistrokidOfficial only), instrumental only: the search keeps a track only when its listing says it has no vocals. `python3
  tools/audio/music_search.py` searches the Creator Store for each slot and
  writes `docs/audio/music-shortlist.md` (listen to each on its Creator
  Store page to pick).
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
  and switches for pop-ups, name tags, pass offers, chat announcements,
  gift reminders and gameplay tips. Before their first storm every player is asked once
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

### Server goal and Server Surge

Everyone in a server fills one meter together (`Systems/ServerGoal`, the
numbers in `Config.SERVER_GOAL`).

- **Filling it**: every Volt sold in the server counts, at a station or
  with Remote Sell. The AFK Lounge doesn't count.
- **How big it is**: each player's grinding rate (what the AFK screen
  works out for their best zone) added up, times 15 minutes. So a full
  server of late-game players and two new players both take about 15
  minutes. Players who have been in the AFK Lounge for 5 minutes or more
  (`afkExcludeMinutes`) are left out, since they can't help fill it; they
  count again when they leave the lounge. It's worked out again when
  someone joins, leaves, or starts or stops being left out, and it never
  drops below what's already filled plus 10%, so it can't get stuck.
- **Server Surge**: a full meter starts 10 minutes of 2x Volts for
  everyone, with a banner and a chat line. It stacks with a Server Storm
  (both on: 4x). The meter then empties and the next goal is 1.5x bigger;
  every hour the size goes back to normal.
- **On screen**: a slim meter under the goal card ("⚡ Server goal 62%", or
  the Surge's time left). Tap it to see this round's top 3 helpers.

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

### Storm Log

The Storm Log is a collection book in the RESEARCH panel's **LOG** tab
(`Util/StormLog`, `Systems/StormLog`, `Lib/StormLogTab`). The tab shows
"(n)" when n rows can be claimed, and the menu's RESEARCH dot lights. It has four pages:

- **Bolts**: every bolt type (normal, Golden, Rainbow, ball lightning) in
  every zone.
- **Places**: every world and every zone you've been in.
- **Team**: every researcher at every rank (hiring them is the first).
- **Weather**: being in game for a Supercell and for each scheduled event.

The Roblox Premium zone (Aurora Reef) is a **bonus**: its Bolts row and
its Places entry are shown, but the pages (and the Barometer Bay row) can
be finished without it, so everyone can reach the full +8%.

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

## Ascension

Ascension is the game's rebirth (`Util/Ascension`, `Systems/Ascension`,
`Controllers/AscensionUI`). Once you own the top bottle (the Storm Core),
an **ASCEND** row shows at the bottom of the Shop's BOTTLES list.

- **What it costs**: you need `baseCost x (level + 1)` Volts: 10M for the
  first, 20M for the second, and so on (`Config.ASCENSION`).
- **What resets**: your Volts, bottle, boots, the charges in your bottle
  and the Chemist's tank. You're moved back to Barometer Bay's spawn.
- **What stays**: passes, gifts, boosts, researchers (ranks and levels),
  Glints, quests, the Storm Log, settings, reward streaks and stats.
- **The reward**: **+50% Volts for good per level, added up** (level 3 =
  +150%, so every sale pays 2.5x). It multiplies with passes, events, the
  Server Surge and the Log, and the AFK Lounge and quests follow by
  themselves. The level is saved as `ascension` in the profile.
- **Safety**: pressing ASCEND asks the server, which checks the rules and
  sends a one-use token that runs out after 30 seconds. The confirm screen
  lists exactly what resets and what stays; only pressing ASCEND there (with
  that token) does it.
- **On screen**: purple stars over your head ("★★ ASCENDED", everyone sees
  them) and in the player list, and a big celebration when you ascend.

## Tutorial, friends and invites

**New-player tutorial** (`Util/Tutorial`, `Systems/Tutorial`,
`Controllers/Tutorial`). A first-time player sees a small card at the top
of the screen with one line at a time:

1. Walk to Shoreline (a glowing path and a light beam show the way).
2. Catch 3 bolts. If it's calm, the card explains the storm timer and
   points at it.
3. When the bottle is full, a path leads to the sell pad.
4. Open the MENU, the SHOP, and buy the Vial (a glowing outline and a
   pointing hand show each button in turn).
5. "You're a Storm Bottler!" and a reward of 50 charges (paid in Volts,
   like every reward: 250 Volts on Shoreline).

- **Skipping**: SKIP asks "Skip the tutorial?" first (YES / NO).
- **Saving**: the step is saved (`tutorialStep` in the profile), so it
  carries on after a rejoin. Anyone who owns a Vial or better (or has
  ascended) never sees it.

**Gameplay tips** (`Config.HINTS`, `Util/Hints`, `Systems/Hints`,
`Controllers/Hints`). After the tutorial, the rest of the game is shown a
little at a time: when something becomes useful, a small two-line toast
starting with 💡 appears for 8 seconds, and the button it's about glows
softly for 20 seconds (the MENU button, then the right tile once the menu
is open, or the SELL button or the server goal meter). Tapping the toast
opens that panel. Each tip shows **once ever**.

- **What they cover**: boots and storm drag, a new zone opening, a new
  world's portal, Teleport, hiring a researcher, posting one, Glints,
  promotions, the Storm Log, the daily streak, playtime gifts, quests and
  rerolls, the TOP leaderboards, invites, the group bonus, Boosts, the AFK
  Lounge, rare bolts, Supercells, events, the server goal and Surge, Remote
  Sell (if you own it), Ascension (when you can), Settings and the friends
  boost.
- **When**: never during the tutorial, never with a panel or the menu
  open, never while you're catching in a storm (or for 10 seconds after a
  catch), never in the AFK Lounge, not in the first minute after joining
  or after the tutorial, and at least 90 seconds apart. If several are
  ready, the first in the list goes first.
- **Editing them**: everything is in one list in `Config.HINTS` (near the
  top of `Config.luau`): each tip's id, its trigger (`when`, and `minutes`
  into the visit), its text, what tapping it opens and what glows. The
  triggers themselves are short functions in `Util/Hints.CONDITIONS`.
  Never rename an id (a renamed tip shows again to everyone).
- **Saving**: the ids shown are saved in the profile (`hintsSeen`). The
  client says when it showed one; the server only accepts known ids, a few
  a minute. Players from before tips existed don't get tips for things
  they've clearly done (hired a researcher, bought boots, claimed a daily
  reward, been in two zones, ...).
- **Turning them off**: ⚙️ SETTINGS → Accessibility & HUD → **Gameplay
  tips**.
- **Tests**: `tools/harness/test_hints.luau` checks the triggers, the
  order, the timing and the once-only rule.

**Friends boost** (`Systems/Friends`): +5% Volts for each Roblox friend
in your server, up to 3 (+15%). The server checks friendships when
someone joins and forgets them when they leave. A green chip on the HUD
says "👥 +10% friends". It counts everywhere a sale does (Remote Sell, the
AFK Lounge).

**Invites** (`Systems/Invites`, the **INVITE** button in REWARDS): opens
Roblox's own invite window. When a friend who has **never played before**
joins from your invite, they get a welcome gift of 100 charges, and once
they've played 10 minutes (or made their first sale) you get a 2x Volts
Boost in your gift inbox (so you get it even if you're offline). Limits: 5
rewarded invites a day per inviter, and only for Roblox accounts at least
14 days old (so alt accounts don't pay). Numbers are in `Config.TUTORIAL`, `Config.FRIENDS`
and `Config.INVITES`. Studio can't send real invites: look for
`[Invites]` lines in the output on a live server.

## Leaderboards and notifications

**Leaderboards** (`Util/Leaderboards`, `Systems/Leaderboards`). Four
boards: **All-time Volts**, **Bolts caught**, **Ascension** and **Longest
streak** (the most days in a row you claimed the daily reward; it keeps
counting past day 7). Each is saved in its own OrderedDataStore
(`StormBottler_LB_volts` and so on).

- **Saving scores**: every 5 minutes (only scores that changed) and when
  you leave.
- **Reading them**: every server reads the top 50 every 2 minutes, so a new
  score can take a few minutes to show.
- **Seeing them**: REWARDS > **TOP**. A button per board, then "You: #7"
  (or "not in the top 50" with your own score), then the top 50 with
  avatars. Your own row glows gold.
- **The board at the spawn**: a "TOP VOLTS" sign beside world 1's spawn
  shows the top 10 all-time Volts.
- **Testing in Studio**: the boards need Game Settings > Security >
  Enable Studio Access to API Services.

**Phone notifications** (`Util/Notifications`, `Systems/Notifications`).
After a player claims a daily reward for the first time, a message asks
"Remind me when my daily reward is ready?". YES opens Roblox's own
notifications prompt. It's only ever asked once, and the YES is saved
(`notifyYes`). When someone who tapped YES leaves (or the server closes), two reminders wait in a MemoryStore queue: **daily reward
ready** (at midnight UTC, if they claimed today) and **streak ends soon**
(3 hours before their streak would break). Any running server sends due
reminders each minute, and each is sent only once. Coming back cancels
them. Roblox delivers at most one a day per game, only to players 13 and
over who said yes.

**Setup you need to do once** (until then nothing is sent, and the output
says `[Notifications] not sending ...`):

1. **Notification strings**: on the Creator Dashboard
   (create.roblox.com/dashboard/creations), open the game, then
   **Engagement > Notifications > Create a Notification String**. Make two,
   for example "Your daily reward is ready! ⚡" and "Your login streak ends
   soon. Come back to keep it!" (99 characters at most). For each one, use
   the **...** button > **Copy Asset ID** and paste the ids into
   `src/shared/Config.luau`: `NOTIFICATIONS.dailyReadyMessageId` and
   `NOTIFICATIONS.streakEndingMessageId`.
2. **API key**: Creator Dashboard > **Open Cloud > API Keys > Create API
   Key**. Add the **user-notification** API system with the
   **user.user-notification:write** permission for this experience. Copy
   the key.
3. **Secret**: on the game's page on the Creator Dashboard, **Secrets >
   Create Secret**. Name: `StormBottlerNotifyKey`, secret: the key, domain:
   `apis.roblox.com`.
4. **HTTP**: in Studio, **File > Experience Settings > Security > Allow
   HTTP Requests** on.

The game must have at least 100 visits before Roblox sends any. Studio
can't send real notifications.

## Admin panel, error reports and streaming

**Admin panel** (`Systems/Admin`, `Controllers/AdminUI`, `Util/Ops`).
Admins are the owner of the Super Studio group, anyone in it at rank 200
or higher (`Config.ADMIN_RANK`), and everyone in a Studio play test.
Admins see an **🛡 ADMIN** button under the MENU button. In the panel:

- type a **username** (or a user id) at the top, and a **reason** under it
- **KICK** (players in this server), **BAN** for the length on the button
  beside it (1 hour, 1 day, 7 days, 30 days or forever; tap it to change)
  and **UNBAN**. Bans use Roblox's own ban system, so they work in every
  server and don't work in Studio.
- **GIVE VOLTS** (the amount box) and **GIVE BOOST** (tap the boost and the
  length to change them), for players in this server
- **RESET PROFILE**: tap it, then tap again within 4 seconds to confirm.
  Their save starts again from nothing (if they're in the server they're
  sent out first; it refuses while they're playing in another server).
- **LOOK UP**: that player's saved data, read only, in the box at the bottom
- **TEST ERROR** makes a test error on the server and on your device, and
  **ERRORS** shows this server's 20 most recent errors.

The server checks every request (only the button is on the client), and
every action is saved in the `AdminLog` DataStore: one entry per action
(who, what, when, the target), one key per day (`day_2026-10-25`).

**Error reports** (`Systems/Errors`, `Controllers/ErrorReport`). Every
script error, on the server and on players' devices, is grouped by a short
fingerprint (the script's name and the first line of the message, with
numbers and player names taken out). The first time a fingerprint shows up
in a server it's sent to the Creator Dashboard as the custom event
**Error** (field 1 = the fingerprint, field 2 = `server` or `client`).
Devices send at most 5 errors a minute, and a server takes at most 300 a
minute.

**Streaming** (`Lib/MapBuilder`). The map turns on
**Workspace.StreamingEnabled**, so phones only load the world near the
player (at least 128 studs round you, up to 512 when there's memory;
`Config.STREAMING`). Update Game sets it when it rebuilds the map. If the
map is marked as hand-edited (so it isn't rebuilt), turn it on yourself:
click **Workspace** in the Explorer, then tick **StreamingEnabled** in
Properties. What the game needs everywhere stays loaded (Persistent
models): zone volumes, camps, gates, sell areas, the research office,
portals and the AFK Lounge. Before a trip to another world the server
loads the arrival spot first.

## Data deletion requests

Players can ask Roblox to erase their data ("right to erasure"). Roblox
then tells you which user id to erase, and gives you a deadline:

- **Getting told**: on the Creator Dashboard, open **Webhooks** (under
  your profile menu) and add one with the **Right To Erasure Request**
  trigger, pointing at a URL that reaches you (a Discord webhook works).
  Without a webhook, Roblox sends the request as a notice in your Roblox
  messages, so keep an eye on those.
- **Erasing**: run the script (or ask Claude to run it) before the
  deadline. First the dry run, which only reads and lists what it would
  change:

  ```
  python3 tools/ops/erase_user.py <userId> --dry-run
  python3 tools/ops/erase_user.py <userId>
  ```

  It deletes that user's save (`StormBottler_PlayerData`, key
  `player_<id>`), gift inbox and gift receipts (`StormBottler_Gifts`),
  invite count (`StormBottler_Invites`), leaderboard scores (the four
  `StormBottler_LB_<board>` stores) and phone reminders (the
  `StormBottler_Notifications` MemoryStore). Where their name or id sits
  in someone else's data (gifts they sent, someone's invite list, the
  `AdminLog`), it blanks just that part and keeps the rest. It prints
  every key it deletes or cleans.
- **Keeping it complete**: if the game's code ever opens a store the
  script doesn't know, the script refuses to run until it's added.
  `python3 tools/ops/erase_user.py --check` checks just that, and
  `python3 tools/ops/test_erase_user.py` tests the erase against a fake
  Roblox (nothing goes online).
- It uses the same Open Cloud API key as `tools/store/` (`$ROBLOX_API_KEY`,
  or the one the network adds). The key needs DataStores, Ordered
  DataStores and MemoryStore access for the game. Roblox keeps bans
  itself; this game stores nothing else about players.

## Store page art

`python3 tools/store/make_store_art.py tools/store/art` draws the game
page art into `tools/store/art/`:

- `icon.png` (512×512): the game icon, a glowing bottle of lightning with
  the STORM BOTTLER name
- `thumb_1_storm.png`, `thumb_2_worlds.png`, `thumb_3_loop.png`
  (1920×1080): Barometer Bay in a storm, the three worlds, and "catch,
  sell, upgrade"

Roblox's Open Cloud can't change a game's own icon or thumbnails (its
thumbnail calls only take translated images), so upload them by hand on
create.roblox.com (Creator Dashboard):

1. **Icon**: click the game under **Creations**. In the left menu go to
   **Configurations** > **Places**, click the start place (the one with a
   star), then **Icon** in its left menu. Set the type to **Image**, click
   **Change**, choose `icon.png`, then **Save Changes**.
2. **Thumbnails**: back on the game's page, click **Thumbnails** in the
   left menu and open the **Experience Detail Page** tab. Upload
   `thumb_1_storm.png`, `thumb_2_worlds.png` and `thumb_3_loop.png`, put
   the storm one first, remove Roblox's default picture, and save. (The
   **Home Page** tab can use the same images.)
3. Roblox checks new images first, so they can take a few minutes to show.

## Private servers

Private servers are **on**, at **100 Robux a month** (set with Open Cloud:
`PATCH /cloud/v2/universes/10772352394`, `privateServerPriceRobux`).
Players buy one from the **Servers** tab on the game page. Roblox only
offers private servers in a **public** game, so they show up once the game
is public. To check, change the price or turn them off: create.roblox.com
> **Creations** > the game > **Audience** > **Access Settings** >
**Allow private servers** (and **Requires Robux** with the price), then
**Save Changes**.

In a private server its owner gets a small green **[Owner]** chat tag
(`Systems/PrivateServer`, `Controllers/VipChat`). Everything else works the
same as in a public server.

## Movement checks (anti-cheat)

The client moves its own character, so a cheat script could teleport onto
lightning rings or run faster. `Systems/AntiCheat` (rules in
`Util/AntiCheat`, numbers in `Config.ANTI_CHEAT`) looks at every player's
position 5 times a second. If someone moved further across the ground than
their walk speed allows (×1.5, plus 6 studs, over about a second), they
can't catch bolts, touch ball lightning or sell at a station for 5
seconds. Jet Boots, boots, jumping and falling are allowed for, and so is
every move the server makes (portals, the Teleport panel, the AFK Lounge,
Ascension's trip home, the zone lock, respawning). Nobody is kicked: lag
can look like a teleport. Someone caught 3 or more times shows in the
admin panel's list as `[cheat]`, and the output prints `[AntiCheat]`
lines.

## Code layout

- `src/shared` → ReplicatedStorage.Shared: `Config` (every number),
  `Types`, `Remotes` (every remote's name), `Net`, and `Util/`: the pure
  rules (no Roblox services) both sides use and the harness tests:
  formulas, zones, progression, passes, rewards, quests, the Storm Log,
  Ascension, research, weather and the server goal, settings, social,
  leaderboards, notifications, admin rules (`Ops`), walk speed and storm
  drag (`Speed`) and movement checks (`AntiCheat`).
- `src/server` → ServerScriptService.Server (a Script). It loads every
  system in `Systems/`, calls each one's `init()` and then `start()`.
  - `Systems/`: one module per feature. The core: `PlayerData` (saving),
    `Sync` (sends each player their state), `StormCycle`, `Strikes`,
    `Selling`, `Shop`, `Bottles`, `Boots`, `Movement`, `Travel`,
    `AntiCheat`, `Map`. Then `Research`, `Rewards`, `Quests`,
    `StormLog`, `Ascension`, `Afk`, `ServerGoal`, `Boosts`, `Passes`,
    `PassPerks`, `Store`, `Receipts`, `RemoteSell`, `Gifts`, `Friends`,
    `Invites`, `Group`, `Leaderboards`, `Notifications`, `Settings`,
    `Stats`, `Tutorial`, `Hints`, `Analytics`, `Admin`, `Errors`,
    and `PrivateServer`.
  - `Lib/`: `MapBuilder` (builds the map) and `RateLimit`.
  - `World/`: the map framework and its three style packs (WeatherLab,
    StormPunk, SkyIsles). The ground is built from parts (`World/Blocks`),
    not Roblox Terrain.
- `src/client` → StarterPlayerScripts.Client (a LocalScript)
  - `Controllers/`: `State` (the latest snapshot), the HUD and menu, one
    controller per panel (shop, research, rewards, boosts, gifts,
    settings, teleport, AFK, Ascension, admin), the storm and strike
    effects, music and sound, and the tutorial.
  - `Lib/`: UI helpers (`UI`, `Layout`, `LayoutMath`), sounds (`Sfx`),
    settings, toasts and the Log and leaderboard tabs.
- `plugin/` → the Studio updater plugin (not part of the game).
- `tools/` → the test harness (`tools/harness`, run with Lune), map
  checks and renders, and store, audio and ops scripts.

## Checks

- Format: `stylua src`
- Lint: `selene src`
- Game rules: `lune run tools/harness/test_<name>.luau` for each test in
  `tools/harness/` (`test_gameplay.luau Game`, and `test_layout.luau`
  takes an output path)
- The map: `tools/check_world.sh Game <outdir>`
- Data deletion script: `python3 tools/ops/test_erase_user.py` (offline)

GitHub runs the format, lint, harness and map checks on every push to
`main` and to the working branch (`.github/workflows/ci.yml`).
