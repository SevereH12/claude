# Prompt 11: sound effects, ambience and music that fit together

Follow the rules in `docs/prompts/README.md`.

**Run it three times.** Each run does the first part below that isn't
ticked, then ticks it:

- [ ] Part A: make every sound effect (original, generated in code),
  review it, upload it
- [ ] Part B: play them everywhere in the game, with volume settings
- [ ] Part C: licensed music that follows the weather, ambience, and the
  final mix

Today the game has only three placeholder sounds (`Config.SOUNDS`: a
collide noise for strikes, and one "ping" for catching and selling).
Everything else is silent.

## One sound palette, so it all fits together

Every effect is made by one generator from the same ingredients. That's
what makes it sound like one game.

- **Theme, "bottled lightning"**: bright, glassy and electric, playful
  rather than scary.
  - The core of each tonal sound is a soft sine or triangle, plus a short
    glassy shimmer (a quiet high partial).
  - Anything to do with lightning adds a dash of electric crackle (short
    filtered-noise bursts).
- **One key**: every tonal sound uses only notes of C major pentatonic (C D
  E G A).
  - Good things rise; rewards are rising arpeggios.
  - "No" is a soft, low, short "bonk" on G3, never a harsh buzzer.
- **One room**: the same small, short reverb on every effect, so nothing
  sounds pasted in.
- **Loudness by group**, measured as RMS over the sound with peaks never
  above -1 dBFS:

  | Group | RMS |
  | --- | --- |
  | UI | about -24 dBFS |
  | gameplay | about -18 dBFS |
  | rewards | about -16 dBFS |
  | thunder | about -12 dBFS |

  Within a group, sounds stay within ±1.5 dB of each other.
- **Variety without chaos**:
  - repeated sounds (clicks, catches) get ±4% random pitch when played
  - thunder and impacts have 3 takes each, picked at random
- **Licences**:
  - effects are original, made by our generator, so there's no copyright
    risk
  - music only comes from Roblox's licensed partner catalogues
    (creators **APMOfficial** and **DistrokidOfficial**, which any game may
    use)
  - never use random players' uploads; many are ripped from other games

## Part A: make, review and upload the effects (run 1)

This part is tools only, with no game code.

### Read only

- `src/shared/Config.luau` (`SOUNDS`, `WARNING_TIME`, `STORM_DURATION`)
- grep `src/client` for `playSound`, `UI.pop`, `toast`, `openPanel` and
  `Activated`, to list every event that needs a sound
- `tools/store/create_store.py`, for the Open Cloud call pattern (the API
  key is added by the network proxy for `apis.roblox.com`)

### Build

1. **`tools/audio/sfx.py`**: generates every effect below as 48 kHz WAV
   files from one shared palette module (the key, the reverb, the crackle,
   the shimmer and the envelopes).
   - It's deterministic: a fixed seed, so the same output every time.
   - It uses numpy only (`pip install numpy` if it's missing), plus ffmpeg
     for encoding.
   - Each sound is a short Python function with named settings, so changing
     one sound is a one-line edit.
2. **The sound list** (adjust it to the events you actually found):
   - **UI**:
     - click
     - hover (PC only, very quiet)
     - panel open (a soft upward whoosh and a glass tick) and close (the
       reverse)
     - tab switch
     - menu open (a quick 5-note fan-out matching the tiles popping in) and
       close
     - toast blip
     - error / locked bonk
     - purchase success (a sparkle chord)
   - **Gameplay**:
     - strike warning: a rising electric charge hum lasting exactly
       `WARNING_TIME`, played in 3D
     - bolt impact: a crack and thunder, 3 takes
     - catch: a glass clink and a zap into the bottle, 5 pitch steps so it
       rises as the bottle fills
     - bottle full: a cork pop and fizz
     - sell: an electric "ka-ching" in 3 sizes by amount (small, medium,
       big)
     - x2 assay / lucky
     - x4 jackpot
     - tank glug
     - balloon bolt: a whistle and crack
     - forecast ping
     - gate bump: a low bonk
     - portal travel: a warp sweep
     - zone enter: a whoosh and chime
   - **Rewards**:
     - zone or world unlocked: a 2s fanfare
     - level up (a short fanfare)
     - researcher hired (a stamp and chime)
     - boost start (power up) and boost end (power down)
     - daily reward (a chest-pop fanfare)
     - gift ready (a soft bell)
     - gift received (an unwrap sparkle and fanfare)
     - Server Storm start (big thunder and a rising synth)
     - Volts count-up tick (tiny, for the HUD counter)
   - **Loops** (seamless; the last 50 ms crossfades into the first):
     - calm wind and waves
     - storm rain
     - storm wind gusts
     - power-plant electric hum
3. **Review before uploading**: `tools/audio/review.py <outdir>` writes:
   - `review.png`: a waveform and spectrogram for every sound
   - `review.md`: a table of each sound's length, peak, RMS and group

   It **fails** (non-zero exit) if any of these is wrong:
   - a peak above -1 dBFS
   - an RMS more than 1.5 dB off its group target
   - a loop with a click at the seam (sample jump over a threshold)
   - a tonal sound outside the pentatonic set (the generator records the
     notes it used)
   - a non-loop sound with a tail longer than 3 s

   Look at `review.png` once and fix anything odd.
4. **Pack to save uploads**: Roblox allows only 10 audio uploads a month on
   an account that isn't ID-verified.
   - Join the one-shot effects into a few sheets (`UI`, `Gameplay`,
     `Rewards`), with 0.5 s of silence between sounds, encoded as `.ogg`
     with ffmpeg.
   - Keep each loop as its own file.
   - That's about 7 uploads, so the total stays at 8 or fewer.
   - Write `tools/audio/sheets.json`, giving each sound's sheet, start and
     length in seconds.
5. **Upload**: `tools/audio/upload.py` uploads through the Open Cloud
   Assets API.
   - **Request**: `POST /assets/v1/assets`, multipart, `assetType`
     `"Audio"`, with the creator set to group **7889739** (the group that
     owns the game, so the game is allowed to play them). Poll the
     operation until it gives an asset id.
   - **Skipping**: only upload files whose content hash changed.
   - **Results**: write the ids to `tools/audio/sound_ids.json`.
   - **Errors**:
     - a 401 or 403: stop and tell the user to add **Assets: read and
       write** for the Super Studio group to their API key
     - a rate or quota error: stop and report how many uploads remain
6. **Generate `src/shared/SoundBank.luau`** from `sheets.json` and
   `sound_ids.json`: for each sound, its asset id, `start`, `length`,
   `loop`, its group (UI, SFX, Ambience) and its default volume.

### Done means (part A)

- `review.py` passes, and `review.png` was looked at.
- Every file uploaded and moderation approved (check the operation
  results). `SoundBank.luau` has real ids.
- `stylua src` and `selene src` are clean.
- In the final message, show `review.png`. The generated sounds are WAV
  files in `tools/audio/out/`, so the user can listen to them on their
  computer.
- Tick part A, commit and push. Commit the generator and the ids, not the
  WAV files.

## Part B: play them everywhere, with volume settings (run 2)

**Needs part A**: `src/shared/SoundBank.luau` with real ids must exist. If
it doesn't, stop and tell the user.

### Read only

- `src/shared/SoundBank.luau` and `Config.luau` (`SOUNDS`)
- `src/client/Lib/UI.luau`
- `src/client/Controllers/StrikeFX.luau`
- `src/client/Controllers/Menu.luau`
- grep the other client controllers for the events listed in part A
  (panels, toasts, rewards, purchases, travel), and read only those lines
- in `src/server/Systems/PlayerData.luau`, `DEFAULT_PROFILE`, `MIGRATIONS`
  and `migrate`

### Build

1. **`src/client/Lib/Sfx.luau`**: the only code that plays sounds.
   - **Calls**: `Sfx.play(name, opts?)` for 2D UI sounds, and
     `Sfx.playAt(name, position, opts?)` for 3D world sounds.
   - **Playing one sound off a sheet**: set `PlaybackRegionsEnabled` and
     `PlaybackRegion = NumberRange.new(start, start + length)`.
   - **Reuse**: a small pool of Sound instances per sheet, so nothing is
     created per play.
   - **Pitch**: random ±4% pitch on repeated sounds.
   - **Volume groups**: `SoundService` gets `SoundGroup`s for `Music`,
     `Ambience`, `SFX` and `UI`, and every sound goes into one.
   - **Throttling**: the same sound plays at most once per 50 ms (the
     Volts tick at most every 80 ms).
2. **Wire every event**:
   - **Buttons**: one hook in `Lib/UI` gives every button its click (and
     hover on PC), so no button is missed.
   - **Panels, the menu, toasts, tabs**: through the `Lib/UI` open and
     close helpers.
   - **Strikes**:
     - the warning hum plays in 3D at the ring
     - the impact plays in 3D, with the thunder delayed by distance (about
       1 s per 340 studs, up to 1.5 s)
     - the catch rises in pitch with the bottle fill
   - **Sell**: picks small, medium or big by amount.
   - **Everything else from the part A list**, at its event.
   - Remove `Config.SOUNDS` and the old `playSound`.
3. **Settings**:
   - **If prompt 14 has run** (`src/client/Lib/SettingsStore.luau` exists):
     don't build a panel. Drive the `SoundGroup`s from its Sound tab
     settings (Master, Music, Effects, Ambience, UI, Mute all) through
     `SettingsStore.Changed`.
   - **Otherwise**, a gear button on the menu card opens a small SETTINGS
     panel.
     - **Sliders**: Music, Effects (SFX and UI) and Ambience, plus a Mute
       all toggle.
     - **Saving**: in the profile (`settings.musicVolume`, `sfxVolume`,
       `ambienceVolume`, and `muted`, in a migration) through a
       `SaveSettings` remote, rate-limited and with values clamped from 0
       to 1.
     - **Applying**: on join.
     - Prompt 14 later moves these into its Settings panel.
4. **Studio check**: a TEST-panel "Sound board" button (Studio only) plays
   every sound in order with its name shown, so the user can hear them all
   in one go.

### Done means (part B)

- `stylua src` and `selene src` are clean.
- `tools/check_world.sh Game` still passes.
- If the Studio MCP is connected: run the Sound board, catch a strike and
  sell, and check the Output has no sound errors (for example, a failed
  asset load).
- Tick part B, commit and push.

## Part C: music that follows the weather, ambience, final mix (run 3)

**Needs part B**: `src/client/Lib/Sfx.luau` must exist. If it doesn't,
stop and tell the user.

### Read only

- `src/client/Lib/Sfx.luau` and `src/shared/SoundBank.luau`
- in `src/client/Controllers/Storm.luau`, grep `Storm.current`,
  `Storm.Changed` and `phase`
- in `src/shared/Config.luau`, `WORLDS`
- grep for the client's current-world attribute (`World`)

### Build

1. **Find the music** with the Creator Store search API:
   `POST https://apis.roblox.com/toolbox-service/v2/assets:search` with
   `{"searchCategoryType":"Audio","query":..., "maxPageSize":50}`.
   - **Filters**: keep only results whose creator is **APMOfficial** or
     **DistrokidOfficial**, `audioType` `"Music"`, and at least 90 s long.
   - **Four playlists**, each with 6 candidates. Search from several
     queries per slot:
     - **Barometer Bay, calm**: sunny, playful, light adventure, seaside
     - **Barometer Bay, storm**: driving electronic, energetic, synth action
     - **Voltcliff Works, calm**: quirky, mechanical, steampunk, groovy
     - **Voltcliff Works, storm**: industrial electronic, intense
   - **Shortlist**: write it to `docs/audio/music-shortlist.md` (id, title,
     artist, length and source query). Put the top 3 per slot in
     `Config.MUSIC`.
   - **The user picks**: you can't listen to them, so the user chooses. Add
     a TEST-panel "Music audition" button (Studio only) that plays each
     shortlist track for 20 s with its name shown.
2. **Music that follows the weather** (`Controllers/Music.luau`):
   - **What plays**: the current world's calm or storm playlist, matching
     the storm phase. A phase change crossfades over 3 s.
   - **Order**: shuffled, with no repeats until the playlist is used up.
   - **Changing world**: crossfades to the new world's music.
   - **Ducking**: music dips 6 dB for about 1.5 s under big moments
     (fanfares, a jackpot, a Server Storm, gift received), then comes back.
     Do this with a tween on the Music group's volume.
   - **Settings**: everything goes through the Music group, so the sliders
     work.
3. **Ambience**:
   - **Calm**: the wind-and-waves loop, quiet.
   - **Storm**: the rain loop, plus random wind gusts and distant rumbles
     every 6 to 15 s.
   - **Phase changes**: 3 s crossfades between calm and storm.
   - **Power plant**: the electric hum loop sits on each world's power-plant
     coil or sell station in 3D, heard within about 60 studs.
4. **Final mix pass**: listen through the Sound board order in Studio (if
   the MCP is connected), or else check the numbers. Make sure:
   - no group drowns out another (music sits under the effects; UI is the
     quietest)
   - storms feel big
   - Default volumes are in `Config.SOUND_MIX`, so they're easy to tune.

### Done means (part C)

- `stylua src` and `selene src` are clean.
- `tools/check_world.sh Game` still passes.
- If the Studio MCP is connected: play through one calm-to-storm-to-calm
  cycle and check the music and ambience crossfade, with no errors in
  Output.
- In the final message:
  - **The shortlist**: link `docs/audio/music-shortlist.md`, and tell the
    user to try "Music audition" in Studio and say which tracks to keep.
  - **The settings**: list where each sound and music setting lives.
- Tick part C, commit and push.
