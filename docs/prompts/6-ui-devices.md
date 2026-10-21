# Prompt 6: one menu button, teleport, Game Pass shop, and a GUI for every device

Follow the rules in `docs/prompts/README.md`. Run this after prompts 1 to
5, so it covers every screen they added.

**Run it twice.** Each run does the first part below that isn't ticked,
then ticks it:

- [ ] Part A: one menu button, with Shop, Research, Teleport and Passes
  flying out of it
- [ ] Part B: every screen fits and works on every device

## Part A: one menu button (run 1)

### Read only

- `src/client/Lib/UI.luau`
- in `src/client/Controllers/HUD.luau`, grep for the buttons
  (`buildShopButton`, the RESEARCH button)
- `ShopUI.luau` and `ResearchUI.luau`: only how they open and close
- `src/server/Systems/Travel.luau` and `src/client/Controllers/Travel.luau`
- `src/shared/Config.luau`, `Remotes.luau` and `Util/Progression.luau`
- `src/server/Systems/Selling.luau`: only where Volts are earned

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
2. **TELEPORT panel**: one section per world. Each lists the world's hub,
   its Research Center or Office, and its zones in order.
   - **Locked rows** are greyed, with the reason (`Progression.lockReason`,
     the world's `requiresBottle`, or Premium only).
   - **Remote**: `TeleportTo(destId)`, rate-limited.
     - `destId` must be one of the server's own destination ids:
       `"Hub:<WorldId>"`, `"Research:<WorldId>"` or a zone id.
     - The server checks the player is allowed there (the same rules as
       zone gates and portals), is alive, and is off `TELEPORT_COOLDOWN`
       (Config, about 10s).
     - It moves them with the same code `Systems/Travel` uses for portals
       (and sets the `World` attribute).
   - **Landing spots**:
     - a zone: just outside its gate, never inside the zone
     - a hub: the world's spawn
     - Research: the office pad
   - Show the cooldown on the panel.
   - Put the destination list and the allowed check in a pure
     `src/shared/Util/Teleport.luau`.
3. **PASSES panel (Game Pass shop)**:
   - **Config**: `GAMEPASSES`, a list of `{ key, id, name, description }`.
     An `id` of 0 means not created yet, and its card says COMING SOON.
     Start with two simple passes:
     - `DoubleVolts`: selling pays 2x
     - `FastTravel`: no teleport cooldown
   - **Cards**: the name, description and price from
     `MarketplaceService:GetProductInfo(id, Enum.InfoType.GamePass)`
     (cached, wrapped in `pcall`), shown with the Robux icon
     `utf8.char(0xE002)`. BUY calls
     `MarketplaceService:PromptGamePassPurchase`; owned passes show OWNED.
   - **Server** (`Systems/Passes.luau`):
     - check ownership on join with `UserOwnsGamePassAsync` (`pcall` and one
       retry)
     - grant straight away on `PromptGamePassPurchaseFinished`
     - expose `Passes.owns(player, key)`
     - set `Pass_<key>` player attributes for the client to show
     - never trust the client
   - **Effects**: `Selling` applies `DoubleVolts`, and `TeleportTo` skips the
     cooldown for `FastTravel`.
   - **README**: explain how to create a Game Pass on the Creator Dashboard
     and paste its id into Config.
4. **Test**: `tools/harness/test_teleport.luau` covers the destination list,
   allowed and locked destinations, and the cooldown maths.

### Done means (part A)

- `stylua src` and `selene src` are clean.
- `test_teleport.luau` and the existing harness tests pass.
- `tools/check_world.sh Game` still passes.
- If the Studio MCP is connected: open the menu, watch the buttons fly
  out, teleport to Mesa and to the hub, and check that a locked zone
  refuses.
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
