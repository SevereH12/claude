# Prompt 14: Settings (controls, sound, graphics, accessibility and HUD)

Follow the rules in `docs/prompts/README.md`.

**Run it twice.** Each run does the first part below that isn't ticked,
then ticks it:

- [x] Part A: the settings system, the SETTINGS menu tile, Controls
  (rebinding) and Sound
- [ ] Part B: Graphics (presets set by device), Accessibility & HUD, and
  the one-time flashing question

## What Roblox allows

- **Graphics**: a game can't change the player's own Roblox graphics level.
  It can only read it (`UserSettings():GetService("UserGameSettings")
  .SavedQualityLevel`). So "Graphics" here means turning the game's own
  effects down: rain, particles, flashes, glow, shadows (set locally) and
  far-away decorations.
- **Saving**: games have no local storage on the device, so settings save to
  the player's profile and follow them to every device.
- **Reserved keys**: some keys belong to Roblox or to movement, and can never
  be bound:
  - movement: W A S D, the arrow keys, Space and Shift
  - chat: `/` and Enter
  - Tab, Esc, and F9 to F12
  - on a controller: A, Start, Select and both thumbsticks

  Esc, and B on a controller, always close panels.

## Part A: settings system, menu tile, Controls and Sound (run 1)

### Read only

- `src/client/Controllers/Shortcuts.luau` and `Menu.luau` (the `ITEMS`
  tiles)
- in `src/client/Lib/UI.luau`, grep `padHint`, `window`, `toast` and
  `openPanel`
- `src/client/Lib/Layout.luau`, for the device class
- in `src/server/Systems/PlayerData.luau`, `DEFAULT_PROFILE`, `MIGRATIONS`
  and `migrate`
- `src/server/Systems/Shop.luau`, as the remote pattern
- if prompt 11 has run (`src/client/Lib/Sfx.luau` exists): `Sfx.luau`, and
  grep for its SETTINGS panel and its gear button

### Build

1. **`src/shared/Util/Settings.luau` (pure)**: the whole settings schema in
   one table. Each setting has a key, a type (bool, a slider with
   min/max/step, a choice from a list, or a keybind), a default and a
   section.
   - **`sanitize(raw)`** returns a clean table: unknown keys are dropped,
     wrong types reset to default, numbers are clamped, and choices are
     checked against their list.
   - Both the client and the server use it.
2. **Saving**:
   - **The profile**: `settings` in the profile (migration), plus
     `settings.version`.
   - **Sending**: the client sends the whole table with
     `SaveSettings(table)`, at most once a second (it waits a second after
     the last change). The remote is rate-limited and size-capped, and the
     server stores `Settings.sanitize(table)`.
   - **On join**: a `Settings` remote sends the saved table, so this isn't
     in every Snapshot.
3. **Client store** (`src/client/Lib/SettingsStore.luau`): `get(key)`,
   `set(key, value)` and a `Changed(key, value)` signal. Every controller
   reads settings through it and reacts live, with no rejoin.
4. **SETTINGS, the 6th menu tile** (⚙), opening a Settings panel in the
   game's UI style:
   - **Tabs**: Controls, Sound, Graphics, Accessibility & HUD.
   - **Each row** has a short label, a one-line hint, and its control (a
     toggle, a slider showing its value, a choice of buttons, or a key
     button).
   - **Resets**: "Reset this tab" and "Reset all", each with a confirm.
   - **A shortcut** to open it: Comma on keyboard; on a controller, Y
     (menu) and then the SETTINGS tile.
   - The panel follows the device layout rules (`Lib/Layout`).
5. **Controls**:
   - **Actions** to bind: Menu, Shop, Research, Teleport, Boosts, Rewards,
     Remote Sell and Settings. Close stays fixed on Esc and B.
   - **Two columns**, Keyboard and Controller. The defaults are today's keys:

     | Action | Keyboard | Controller |
     | --- | --- | --- |
     | Menu | M | Y |
     | Shop | B | — |
     | Research | R | — |
     | Teleport | T | — |
     | Boosts | P | — |
     | Rewards | G | — |
     | Remote Sell | V | L1 |
     | Settings | Comma | — |

   - **Rebinding**: tap a key button and it shows "Press a key…". The next
     key or controller button becomes the binding (Backspace clears it).
   - **Rules**: reserved keys are refused with a toast. A key already used
     by another action swaps with it, and a toast says so.
   - **Saving**: bindings save as `KeyCode` names. The server only accepts
     names on an allowlist.
   - **Shortcuts.luau** reads the bindings from the store instead of
     hard-coded keys. The key hints on buttons (`UI.padHint`) show the
     player's own keys and update straight away.
   - **On touch devices**, the Controls tab just says "Touch controls: tap
     the buttons on screen".
6. **Sound tab**: Master, Music, Effects, Ambience and UI sliders (0 to
   100%) and Mute all.
   - **If prompt 11 has run**: drive its `SoundGroup`s from these settings.
     Move its old sliders into this tab and remove its gear button and
     small panel, so there's one Settings panel.
   - **If it hasn't**: just store the values. Prompt 11 is already told to
     use this tab.
7. **Test**: `tools/harness/test_settings.luau` covers:
   - `sanitize` (unknown keys, wrong types, clamping, bad choices)
   - keybind rules (reserved keys refused, the allowlist, swapping on a
     clash)
   - the defaults

### Done means (part A)

- `stylua src` and `selene src` are clean.
- `test_settings.luau` and the other harness tests pass.
- `tools/check_world.sh Game` still passes. If `tools/harness/test_layout.luau`
  covers panels, it passes with the new one.
- If the Studio MCP is connected, check that:
  - rebinding Shop to K means K opens the shop and B doesn't
  - the hint on the button changes
  - settings come back after rejoining
- Tick part A, commit and push.

## Part B: Graphics, Accessibility & HUD, flashing question (run 2)

**Needs part A**: `src/client/Lib/SettingsStore.luau` must exist. If it
doesn't, stop and tell the user.

### Read only

- `src/shared/Util/Settings.luau` and `src/client/Lib/SettingsStore.luau`
- in `src/client/Controllers/Storm.luau`, the rain and the lighting tweens
- in `src/client/Controllers/StrikeFX.luau`, `screenFlash`, `cameraShake`,
  `bolt`, `impact`, `groundRing` and `popup`
- in `src/client/Controllers/Researchers.luau`, the update loop and name
  tags
- in `src/client/Controllers/Offers.luau` and `Announcements.luau`, where
  they show things
- `src/client/Lib/Layout.luau`, for the device class and the UI scale

### Build

1. **Graphics tab**: a preset (Low, Medium, High or Custom) plus the
   settings below. Changing any single setting turns the preset to Custom.

   | Setting | Low | Medium | High |
   | --- | --- | --- | --- |
   | Rain and particle amount | 25% | 60% | 100% |
   | Lightning glow and flash | off | soft | full |
   | Shadows (`Lighting.GlobalShadows`, local) | off | on | on |
   | Bloom and colour grade intensity | 0 | 50% | 100% |
   | Far-away decorations | hidden beyond 250 studs | hidden beyond 500 | all |
   | Other players' strike effects | off | simple | full |
   | Other players' researchers | hidden | own camp only | all |

   - **Field of view**: a slider from 60 to 90, separate from the preset.
   - **Hiding far decorations**: set `LocalTransparencyModifier` on the
     parts under each world's decoration folders. Never touch ground,
     zones, signs, pads or portals, and never anything that collides.
     Check it in batches, at most every 2 seconds, with the part list cached
     once.
2. **Starting preset, set by device** (first join only, when no graphics
   setting is saved):
   - phone: Low
   - tablet: Medium
   - PC and console: High
   - if the player's Roblox graphics level is set to 3 or lower, one step
     lower
3. **Accessibility & HUD tab**:
   - **Reduce flashing**:
     - no screen flash
     - bolts fade instead of flickering
     - lighting changes over 2 seconds or longer
     - warning rings pulse more slowly
   - **Camera shake**: a slider from 0 to 100% (default 100%).
   - **Colourblind-friendly rings**: warning rings get a dashed outline and
     a ⚡ icon in the middle, and zone colours switch to a high-contrast set.
     The choices are Off, Red-green and Blue-yellow.
   - **Text size**: Normal, Large or Extra large. It raises the
     minimum text size and nudges the UI scale up 10% or 20%, within the
     layout limits.
   - **Show** toggles:
     - catch and sell popups
     - researcher name tags
     - pass offers (when off, `Offers` never shows one)
     - gift and Server Storm chat announcements
     - playtime gift reminders
4. **The flashing question, asked once**:
   - **When**: before the player's first storm (or on join if a storm is
     already on), and only if it hasn't been answered.
   - **The card**: "Lightning flashes a lot in this game. Reduce flashing?"
     with YES and NO.
   - **Saving**: the answer saves (`settings.flashAsked`), and Reduce
     flashing can be changed any time in Settings.
5. **Hooking it up**: every effect above reads its setting from the store
   and reacts to `Changed` live. No setting may make anything gameplay-wise
   unclear: warning rings always show, just calmer.
6. **Tests**: extend `test_settings.luau` with:
   - each preset's values
   - device defaults, including the step down for a low Roblox graphics
     level
   - choosing a single setting turning the preset to Custom

### Done means (part B)

- `stylua src` and `selene src` are clean.
- `test_settings.luau` and the other harness tests pass.
- `tools/check_world.sh Game` still passes.
- If the Studio MCP is connected:
  - switch Low, then High, and see the rain and shadows change
  - turn on Reduce flashing and watch a strike: no screen flash
  - a new profile is asked the flashing question once
- Tick part B, commit and push.
