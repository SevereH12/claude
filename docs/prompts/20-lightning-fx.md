# Prompt 20: smooth lightning that doesn't cut out

Follow the rules in `docs/prompts/README.md`. **One run.**

- [x] Smooth bolts, a flicker that doesn't look like a glitch, less work per
  strike, and rain that keeps up

The user said: "the lighting looks choppy in some zones and gets cut off and
comes back". That's the lightning bolts first. Also check the strike's
light flash and the rain, which follow the same path. Nothing changes on the
server.

## Read only

- `src/client/Controllers/StrikeFX.luau`: the top comment, the constants,
  `effectPart`, `jaggedPath`, `drawPath`, `flickerAndFade`, `bolt`,
  `impact`, `onWarning` (for the ball-lightning orb only) and `onLanded`
- in `src/client/Controllers/Storm.luau`: `makeRain`
- in `src/client/Controllers/Graphics.luau` and `src/shared/Util/Settings.luau`:
  grep `glow`, `othersStrikes` and `particleAmount`
- in `src/shared/Types.luau`: `StrikeLanded`
- in `src/shared/Config.luau`: grep `THUNDER_` (to see where effect
  numbers live)

## What's wrong (found by reading the code)

1. **Blocky, broken bolts.** Each bolt is 9 straight box parts, a Neon core
   plus a wider see-through glow box per segment. The boxes don't join
   where the path bends (the glow boxes have no overlap at all), so joints
   show gaps and square ends.
2. **The flicker looks like a glitch.** `flickerAndFade` hides every part
   at 0.05 s and shows them again at 0.09 s. That's two or three frames,
   and on a slower frame rate it reads as the bolt cutting out and coming
   back.
3. **Too much work per strike, so busy zones stutter.** Every client draws
   every strike in every world (the server sends them to all players):
   - about 34 parts per bolt, plus arcs to each catcher
   - sparks
   - a `PointLight` with range 60 that casts shadows when Glow is Full

   Supercells double the strikes. Strikes 5000 studs away in another world
   still cost frame time, and the shadowed lights are the heaviest part.
4. **The rain lags behind.** The rain slab follows the camera, but its
   particles stay where they were made, so at boot speed (boots only speed
   you up inside zones) the area ahead of you is dry until the rain catches
   up.

## Build

1. **Bolts drawn with Beams.**
   - **How**: one anchored, invisible, non-colliding host part in
     `fxFolder`, with an Attachment per path point.
   - **Each bolt**: a core Beam and a wider glow Beam per segment:
     - `FaceCamera = true`, no texture, `LightEmission = 1`,
       `LightInfluence = 0`
     - widths from `thickness`
     - consecutive segments share attachments, so the joins are seamless
   - **Keep**: the jagged path, the branches, the rare-bolt thickness and
     colour, and the catcher arcs. The bolt still starts `BOLT_HEIGHT`
     above the strike.
   - **Destroying**: the host part when the fade ends.
2. **The flicker**, like a real restrike:
   - the bolt drops to about 40% (the Beams' Transparency) for one beat,
     then comes back to full and fades, and it never hides completely
   - optionally, redraw a slightly different path on the restrike
   - Reduce flashing keeps just the slow fade
3. **Less work per strike**: a pure `src/shared/Util/StrikeFx.luau` decides
   how much to draw.
   - **Inputs**: the distance from the camera, whether the strike is in the
     player's world (the `World` player attribute against the zone's
     `world`), whether it's theirs (`isMine`), and the Others' lightning
     setting.
   - **Answer**: "full", "simple" or "none".
   - **Rules**:
     - your own strikes are always full
     - another world's strikes are none (no sound either)
     - past `Config.STRIKE_FX.drawDistance` (start at 600 studs) they're
       none, and past `simpleDistance` (start at 250) at most simple
     - the setting can only lower it
   - **Light budget**: at most `Config.STRIKE_FX.maxLights` (start at 3)
     strike lights alive. A new one replaces the oldest.
   - **Shadows**: only your own strike's light casts shadows, and only when
     Glow is Full.
   - **The rest stays as it is**: thunder timing, popups, screen flash and
     camera shake.
4. **Rain that keeps up**: set the rain emitter's `LockedToPart = true` so
   the streaks move with the slab, and check the Rain setting still works.
5. **Tests**: `tools/harness/test_strikefx.luau` covers the `StrikeFx`
   rules (own, other world, each distance band, and each setting) and the
   light budget (if it's in the module). Put the jagged path maths in
   `Util/StrikeFx` too, so the test can check the path's start, end and
   point count.

## Done means

- stylua and selene are clean; the new test and the existing harness tests
  pass. If the tools can't be installed, say so in the report.
- The top comment in `StrikeFX.luau` matches the new drawing.
- Report the "check in Studio" steps:
  1. stand in a busy zone during a Supercell and watch the bolts, which
     should be smooth with no gaps or cut-outs
  2. run with fast boots and watch the rain
  3. try Others' lightning set to Simple and Off
- Tick it, commit and push.
