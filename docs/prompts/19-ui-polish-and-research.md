# Prompt 19: UI polish, and the Research panel with the Log in it

Follow the rules in `docs/prompts/README.md`. **Run it twice**; each run
does the first unticked part, then ticks it.

- [x] Part A: off-centre text, black bits at rounded corners, and progress
  bars that don't show (shared helpers, used everywhere)
- [x] Part B: the Research panel: TEAM and LOG tabs (the Storm Log moves
  here from Rewards), a Glints display, and compact researcher cards

The user's choices: only fix text that is meant to be centred (left-aligned
text stays left); the black shows at rounded corners; the Log's page bars
don't show up.

## Part A: shared UI fixes (run 1)

### Read only

- `src/client/Lib/UI.luau` (all of it: everything here is built from it)
- grep `src/client` for `Instance.new("ScrollingFrame")` and
  `Instance.new("CanvasGroup")`, and read only those blocks and the card
  sizes inside them (`UDim2.new(1, -12`)
- in `src/client/Lib/StormLogTab.luau`: `StormLogTab.build`
- in `src/client/Controllers/RewardsUI.luau`: `buildQuestCard` and the
  quest bar

### What's wrong (found by reading the code)

1. **Title text sits high.** Luckiest Guy has a tight ascender, so Roblox
   draws its capitals about 15% of the line height above the centre of the
   box (Roblox bug report: devforum topic 822188). Every heading, button and
   big number uses it.
2. **Black at rounded corners.** A `UIStroke` is drawn outside its frame.
   When a parent clips (a ScrollingFrame or a CanvasGroup), the straight
   edges of the stroke are cut off but the rounded corners aren't, so dark
   corner bits show. This happens in:
   - every scrolling list: padding is 2–4 px on the top and left only, while
     card strokes are 3–6 px (a claimable quest's is 5), and there's none at
     the bottom
   - toasts: `UI.panel` fills its CanvasGroup exactly
   - `UI.window`'s header: its bottom corners are rounded too, leaving dark
     notches under the coloured strip
3. **Content sits to one side.** Cards are `1, -12` wide with left padding
   only, so lists sit left of centre, and the default scrollbar (black)
   draws over the right edge.
4. **The Log's page bars don't show.** Their track is `panelBottom` (the
   panel's own colour), and the fill starts at 0.

### Build (in `UI.luau`, then use it everywhere)

1. **`UI.TITLE_NUDGE`** (start at 0.12): `UI.label` with `Title = true`
   and `UI.button` move their text down by `TITLE_NUDGE × TextBounds.Y`.
   - **How**: `PaddingTop` plus the nudge and `PaddingBottom` minus it, so
     the text size doesn't change. `UI.button` adds it to its existing
     0.16-scale padding as an offset.
   - **Updating**: update it when `TextBounds` changes, only when the
     rounded value changes (no feedback loop).
2. **`UI.STROKE_ROOM = 6`** and **`UI.list(parent, props): ScrollingFrame`**:
   - **Padding**: `STROKE_ROOM` on all four sides.
   - **Scrollbar**: `VerticalScrollBarInset = ScrollBar`, and the bar
     coloured `subtext` at 0.4 transparency.
   - **Layout**: a centred `UIListLayout` with `props.gap`. Cards inside use
     full width (`1, 0`).
   - **Use it** for every scrolling list in `src/client`: the Rewards pages,
     Shop, Boosts (both), Teleport, Settings, Gift, Research, Admin and
     DevCommands. Grids inside lists keep their own layouts.
3. **`UI.card(props): (Frame, UIStroke)`**: the one card look (`panelDark`,
   12 px corners, a 3 px stroke, 10 px padding). Use it for the quest cards
   and the Log's row cards now; Part B uses it for researchers.
4. **`UI.bar(parent, props)`**: returns the bar frame plus
   `setFraction(n)` and an optional centred label.
   - **Track**: `COLORS.stroke`, with a 2 px `panelTop` outline.
   - **Fill**: a pill with the same corners. No CanvasGroup. A fill narrower
     than the bar's height gets a minimum width equal to the height, and
     it's hidden at 0.
   - **Use it** for the Log's page bars, the quest bars and the Research
     data bar. Leave the HUD bars alone.
5. **Toasts**: inset the panel inside its CanvasGroup
   by `STROKE_ROOM`, and grow the group by the same amount so the visible
   size stays the same.
6. **`UI.window` header**: square its bottom corners with a filler frame in
   the header's colour and gradient, behind the title.

### Done means (part A)

- stylua and selene are clean; the harness tests pass, including
  `test_layout.luau` and `test_toast.luau`.
- No `Instance.new("ScrollingFrame")` is left outside `UI.list`.
- In Studio (if the MCP is connected): open each panel once and look at
  the corners, the list edges, the Log bars and the button text. If the
  title text still sits high or low, tune `TITLE_NUDGE`.
- Tick part A, commit and push.

## Part B: the Research panel (run 2)

**Needs part A**: `UI.card`, `UI.bar` and `UI.list` must exist. If they
don't, stop and tell the user.

### Read only

- `src/client/Controllers/ResearchUI.luau` (all of it: rewrite its UI and
  keep the logic: remotes, promote confirm, the tip, level-up toasts, the
  office auto-open)
- `src/client/Lib/StormLogTab.luau`: the comment at the top, `build` and
  `render`
- in `src/client/Controllers/RewardsUI.luau`: `describe`, `selectTab`, the
  tab bar in `init`, the `StormLogTab` lines and `ReadyChanged`
- in `src/client/Controllers/Menu.luau`: grep `ReadyChanged` and `buyDots`
- in `src/shared/Util/Research.luau`: `glintsOf`, `glintsFor`, `tierZone`,
  `zoneTier`, `canPost`, `canPromote` and `maxRank`
- `src/client/Lib/ZoneColours.luau` (`of`)

### Build

1. **The panel**:
   - **Title**: "🔬 RESEARCH" (the same colour).
   - **Tabs**: a tab row like Rewards: "👥 TEAM" and "📖 LOG". The LOG tab
     shows "(n)" when n rows can be claimed.
   - **Size**: the same design size as Rewards.
2. **Move the Log**:
   - Build `StormLogTab` into Research's LOG page. Rewards keeps REWARDS,
     QUESTS and TOP (three tabs across).
   - Move `describe` into `src/client/Lib/RewardText.luau`, used by both
     panels.
   - `ResearchUI.openLog()` replaces `RewardsUI.openLog`, so the Log's
     toasts open Research.
   - Add a `ResearchUI.ReadyChanged` signal (a Log row is claimable). The
     menu's RESEARCH dot lights for it as well as for "can afford the next
     researcher". Rewards' dot stops counting the Log.
3. **The Glints display**, a strip at the top of TEAM:
   - **Chips**: one per zone tier (0 to `maxRank`), in that tier's zone
     colour (`ZoneColours.of(Research.tierZone(tier))`).
   - **Each chip**: a gem drawn in UI (a 45°-rotated square with a gradient
     and an outline; no uploaded image), the count (abbreviated), and the
     zone name under it.
   - **Tiers with none yet**: dimmed, with "?".
   - **Tapping a chip**: a toast says where those Glints come from and which
     promotions they pay for. Word it from the rules in `Util/Research`
     (`glintsFor`); don't restate them.
   - **When a count rises** while the panel is open, that chip pops
     (`UI.pop`).
   - This replaces the one-line Glints text.
4. **Compact researcher cards** (`UI.card`, in a `UI.list`):
   - **Top**: the portrait on the left; beside it the name · role with rank
     stars, "Lv x / 5" on the right, the perk now, and next (subtext).
   - **Then**: the data bar (`UI.bar`), then the status line.
   - **Bottom row**: two buttons side by side, "📍 <POST>" and
     HIRE / PROMOTE.
   - **PROMOTE** shows Glint progress while it's short ("✨ 37/65 Mesa",
     disabled), then "PROMOTE ✨65". Keep the two-tap confirm.
5. **The post picker**: one overlay inside the panel, shared by every card,
   replacing the button grids.
   - **Contents**: Office, then the zones grouped under their world's name
     (`Config.WORLDS[i].displayName`). Locked zones show 🔒 and "Rank N"; the current post
     is highlighted in volt.
   - **Picking**: tap one to post (the same remote).
   - **Closing**: it closes on a pick, a tap outside it, or Esc / gamepad B,
     without closing the panel.
6. **No server changes.**

### Done means (part B)

- stylua and selene are clean; the harness tests pass (`test_research`,
  `test_quests` and `test_layout`).
- Nothing outside `ResearchUI` still calls `RewardsUI.openLog`.
- In Studio (if the MCP is connected): open Research and check both tabs,
  a Glints chip tap, and the picker. Use the TEST button "+Log entry" to
  see the LOG count and the menu dot.
- Tick part B, commit and push.
