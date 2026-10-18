# Prompt 6: make the GUI work on every device

Follow the rules in `docs/prompts/README.md`. Run this after prompts 1 to
5, so it covers every screen they added.

Make every screen of the game's UI fit, read well and be easy to use on:
- a PC with mouse and keyboard
- a phone, in portrait and landscape
- a tablet (iPad)
- a console with a gamepad, played on a TV

Keep the current look: same colours, fonts and style. This is about layout,
sizing and input, not a redesign.

## Read only

- `src/client/Lib/UI.luau`
- every client file that builds GUI. Find them with
  `grep -ln "ScreenGui\|UI.panel\|UI.button" src/client`. Today that's
  `HUD`, `ShopUI`, `ResearchUI`, `ZoneBanner`, `ZoneGates` and
  `DevCommands`, plus the popup, flash and banner code in `StrikeFX`. Read
  each file once, when you get to it.

## Build

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
   - Keyboard shortcuts: **B** for the shop, **R** for Research and **Esc**
     to close a panel. Show them as small key hints on the buttons, on PC
     only.
   - Panels keep a sensible maximum size on big monitors (`UI.sizeLimits`).
4. **Console / gamepad**:
   - Every button is `Selectable`, and opening a panel puts the selection on
     its first button (`GuiService.SelectedObject`).
   - **ButtonY** opens the shop, **ButtonX** opens Research and **ButtonB**
     closes a panel. Show button hints instead of key hints.
   - Keep everything inside the TV-safe area, about 5% in from every edge.
5. **Pop-ups and banners** ("+5", "x2 ASSAYED", unlock banners, zone
   banners, toasts):
   - place them by scale and keep them inside the safe area
   - never let two pile on top of each other: queue or stack them
6. **Warnings become temporary**: warning and hint text must not stay on
   screen forever. Add one toast helper in `Lib/UI` (for example
   `UI.toast(text, kind, seconds)`).
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

If there are too many screens to finish in one go, finish the layout system
and the HUD and shop first, commit and push, and list the screens still to
do at the end of this file, so a second run picks them up.

## Review before pushing

- `stylua src` and `selene src` are clean, and `test_layout.luau` passes.
- If the Studio MCP is connected:
  - use Studio's device emulator to look at the HUD and every panel on iPhone
    (portrait and landscape), iPad, a 1080p desktop and a console
  - check that nothing is cut off, overlaps, hides under the thumbstick or
    jump button, or has unreadable text, and that warnings disappear on their own
  - fix anything you find, then check again once
- In your final message, give the user a short list of what to check in
  Studio (Test tab, then Device), one line per device.
- Commit and push.
