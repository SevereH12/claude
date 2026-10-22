# Prompt 6: one menu button, world teleport, and a GUI for every device

Follow the rules in `docs/prompts/README.md`. Run this after prompts 1 to
5, so it covers every screen they added.

**Run it twice.** Each run does the first part below that isn't ticked,
then ticks it:

- [x] Part A: one menu button, with Shop, Research, Teleport (worlds) and
  Passes (coming soon) flying out of it
- [x] Part B: every screen fits and works on every device

(Done with two changes the user chose: the MENU button opens a card of
tiles instead of a ring, and the PASSES placeholder became prompt 8's real
store, the BOOSTS tile.)

## Part A: one menu button (run 1)

### Read only

- `src/client/Lib/UI.luau`
- in `src/client/Controllers/HUD.luau`, grep for the buttons
  (`buildShopButton`, the RESEARCH button)
- `ShopUI.luau` and `ResearchUI.luau`: only how they open and close
- `src/server/Systems/Travel.luau` and `src/client/Controllers/Travel.luau`
- `src/shared/Config.luau` (`WORLDS`) and `Remotes.luau`

### Build

1. **One MENU button** replaces the separate SHOP and RESEARCH buttons.
   The TEST button and the readouts stay where they are.
   - It's a round button with a lightning-bottle icon at the side of the
     screen, clear of the thumbstick.
   - **Opening it**: the button spins and pulses, a dim backdrop fades in,
     and four round buttons fly out from the screen centre into a ring:
     SHOP, RESEARCH, TELEPORT and PASSES, each with an icon and a label.
     - They start at scale 0 in the centre and stagger about 0.05s apart,
       with Back easing so they overshoot a little and settle.
   - **Closing it**: clicking the backdrop, the MENU button again, Esc or
     gamepad B plays it in reverse. Picking a button closes the ring and
     opens that panel.
   - **One thing at a time**: only one panel is open at once, and opening
     the menu closes any open panel.
   - **Badges**: a small dot on SHOP when you can afford the next bottle or
     boots, and on RESEARCH when you can afford the next hire.
   - Use TweenService, allocate nothing per frame, and don't change how
     hiring works (it still needs the Research Office).
2. **TELEPORT panel: worlds only.** One row per world in `Config.WORLDS`,
   showing its name, tagline and colour. Teleporting takes you to that
   world's spawn. There are no zone or Research destinations.
   - **Locked worlds** are greyed with "Needs a <bottle name>", the same
     rule the portals use (the world's `requiresBottle`).
   - **The world you're in** shows as "YOU ARE HERE" and can't be
     selected.
   - **Remote**: `TeleportToWorld(worldId)`, rate-limited.
     - `worldId` must be a real world id.
     - The server checks the world is unlocked, the player is alive, and
       they're off `TELEPORT_COOLDOWN` (Config, about 10s).
     - It moves them with the same function `Systems/Travel` uses for
       portals, so the spawn spot and the `World` attribute are handled the
       same way. If that function isn't reusable, make it so; don't copy
       it.
   - Show the cooldown on the panel.
   - Put the unlocked check in a pure function (shared with the portals if
     they don't already have one).
3. **PASSES button**: no Game Passes yet. The button opens a small panel
   saying "Game Pass shop coming soon", with nothing to buy and no
   MarketplaceService code. A later prompt will fill it.
4. **Test**: `tools/harness/test_teleport.luau` covers:
   - a locked world and an unlocked world
   - an unknown world id
   - the cooldown maths

### Done means (part A)

- `stylua src` and `selene src` are clean.
- `test_teleport.luau` and the existing harness tests pass.
- `tools/check_world.sh Game` still passes.
- If the Studio MCP is connected:
  - open the menu and watch the buttons fly out
  - teleport to Voltcliff Works (after using the TEST button for Volts and
    buying its bottle) and back to Barometer Bay
  - check that a locked world refuses
- Tick part A, commit and push.

## Part B: every screen fits and works on every device (run 2)

Make every screen of the game's UI, including the menu ring and the
Teleport and Passes panels from part A, fit, read well and be easy to use on:
- a PC with mouse and keyboard
- a phone, in portrait and landscape
- a tablet (iPad)
- a console with a gamepad, played on a TV

Keep the current look: same colours, fonts and style. This is about layout,
sizing and input, not a redesign.

### Read only

- `src/client/Lib/UI.luau`
- every client file that builds GUI. Find them with
  `grep -ln "ScreenGui\|UI.panel\|UI.button" src/client`. Today that's
  `HUD`, `ShopUI`, `ResearchUI`, `ZoneBanner`, `ZoneGates` and
  `DevCommands`, plus the popup, flash and banner code in `StrikeFX`. Read
  each file once, when you get to it.

### Build

1. **One layout system in `Lib/UI`** (or a new `Lib/Layout.luau`):
   - **Device class**: decide `Phone`, `Tablet`, `Desktop` or `Console`
     from the viewport size (`workspace.CurrentCamera.ViewportSize`, short
     side under about 500 px means a phone) and the input
     (`UserInputService` touch, gamepad and keyboard flags, or
     `PreferredInput` if it exists). Update it when the viewport resizes or
     rotates, or when the input changes, and send a `Changed` signal.
   - **One `UIScale` per ScreenGui**, driven by the class and viewport, so
     everything shrinks on phones and grows on 4K and TV screens.
   - **Safe areas**: every ScreenGui uses
     `ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets`, so the UI stays
     clear of notches and the home bar. Keep the top bar clear of Roblox's
     own buttons (`GuiService.TopbarInset`).
   - **Readable text**: `TextScaled` text gets a `UITextSizeConstraint` with
     a minimum around 14 on phones, so text is never unreadably small.
2. **Touch (phones and tablets)**:
   - Keep the bottom-left (thumbstick) and bottom-right (jump) areas clear.
     Move the bottle bar and buttons so they never sit under a thumb.
   - Every tappable thing is at least 44 x 44 points.
   - Nothing relies on hover.
   - On a phone, the Shop and Research panels open as a near-full-screen
     sheet: a big close button in the corner, and a scrolling list
     (`ScrollingFrame`, `AutomaticCanvasSize`) instead of fixed rows that
     overflow.
   - In portrait, stack things that sit side by side in landscape.
3. **PC**:
   - Keyboard shortcuts: **M** for the menu, **B** for the shop, **R** for
     Research, **T** for Teleport, **P** for Passes and **Esc** to close. Show them as small key hints on the buttons, on PC
     only.
   - Panels keep a sensible maximum size on big monitors (`UI.sizeLimits`).
4. **Console / gamepad**:
   - Every button is `Selectable`, and opening a panel puts the selection on
     its first button (`GuiService.SelectedObject`).
   - **ButtonY** opens the menu ring, the D-pad moves round the ring, and
     **ButtonB** closes. Show button hints instead of key hints.
   - Keep everything inside the TV-safe area, about 5% in from every edge.
5. **Pop-ups and banners** ("+5", "x2 ASSAYED", unlock banners, zone
   banners, toasts):
   - place them by scale and keep them inside the safe area
   - never let two pile on top of each other: queue or stack them
6. **Warnings become temporary**: prompt 7 already added `UI.toast`. Keep
   every warning on it, including any new ones from part A, and check the
   points below still hold:
   - It shows a short message near the top-centre, inside the safe area.
   - It fades out after about 3 seconds.
   - The same text isn't repeated while it's showing (the timer restarts
     instead).
   - At most two show at once.
   - Use it for every warning-style message. Find them with
     `grep -rn -i "full\|locked\|needs\|visit the\|can't\|not enough" src/client`.
     Today these include:
     - "FULL! SELL AT THE POWER PLANT" in the HUD bottle bar: the bar only
       shows the fill (glowing when full) and the warning becomes a toast
       when the bottle first fills, repeating at most every 20 seconds while
       it stays full
     - "Bottle full! Sell at the Power Plant" in `StrikeFX`
     - the zone lock reasons in `ZoneBanner` and `ZoneGates`
     - "Visit the Research Office to hire" in `ResearchUI`: the button just
       shows as disabled, and the hint appears as a toast when it's tapped
   - Status that is still true and needed (Volts, the storm timer, the
     bottle count, a button's LOCKED state) stays on screen.
7. **Test**: put the device-class and scale maths in pure functions, and
   add `tools/harness/test_layout.luau` covering phone portrait, phone
   landscape, iPad, 1080p, 4K and a console at 1080p.

### Review before pushing (part B)

- `stylua src` and `selene src` are clean, and `test_layout.luau` passes.
- If the Studio MCP is connected:
  - use Studio's device emulator to look at the HUD and every panel on iPhone
    (portrait and landscape), iPad, a 1080p desktop and a console
  - check that nothing is cut off, overlaps, hides under the thumbstick or
    jump button, or has unreadable text, and that warnings disappear on their own
  - fix anything you find, then check again once
- In your final message, give the user a short list of what to check in
  Studio (Test tab, then Device), one line per device.
- Tick part B, commit and push.
