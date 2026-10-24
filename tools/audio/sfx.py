#!/usr/bin/env python3
"""Generates every Storm Bottler sound effect and ambience loop as 48 kHz
WAV files from one palette (tools/audio/palette.py), so they all sound like
one game: bright, glassy and electric, C major pentatonic, one small room.

  python3 tools/audio/sfx.py [outdir]      (default tools/audio/out)

Writes <outdir>/<name>.wav and <outdir>/manifest.json (group, loop and the
notes each sound used), which review.py checks and pack.py packs. Same
output every run (fixed seeds). Each sound is one short function below:
change its named settings to change it."""

import json
import os
import subprocess
import sys
import wave as wavfile

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from palette import (  # noqa: E402
    SR,
    Sound,
    adsr,
    band,
    chord,
    crackle,
    fade,
    glide,
    hz,
    loudness,
    noise,
    perc,
    room,
    seamless,
    sweep_noise,
    tone,
    trim,
    wave,
)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
SOUNDS = []  # (name, group, loop, exact, function)


def sound(group, loop=False, exact=False, name=None):
    """Registers a sound. exact: keep its length (no reverb tail), e.g. the
    strike warning that must last WARNING_TIME."""

    def register(fn):
        SOUNDS.append((name or fn.__name__, group, loop, exact, fn))
        return fn

    return register


def config():
    out = subprocess.run(
        ["lune", "run", "tools/balance/config_dump.luau"], cwd=ROOT, check=True, capture_output=True, text=True
    ).stdout
    return json.loads(out[out.index("{") :])


CFG = {}


def secs(n):
    return n / SR


# ---- UI ------------------------------------------------------------------------
@sound("ui")
def click(note="C6", length=0.05):
    s = Sound("click", length + 0.02)
    s.add(tone(s, note, length, "tri", decay=0.045))
    s.add(band(s.rng.standard_normal(int(0.004 * SR)), 2000, 9000) * 0.3)
    return s


@sound("ui")
def hover(note="G6", length=0.035):
    s = Sound("hover", length)
    s.add(tone(s, note, length, "sine", decay=0.03, glass=0.05))
    return s


@sound("ui")
def panel_open(length=0.26, tick="E6"):
    s = Sound("panel_open", length + 0.08)
    s.add(sweep_noise(s, length, 500, 4000) * adsr(int(length * SR), 0.12, 0.05, 0.6, 0.09) * 0.5)
    s.add(tone(s, tick, 0.08, "sine", decay=0.07), at=length - 0.02, gain=0.7)
    return s


@sound("ui")
def panel_close(length=0.22, tick="C6"):
    s = Sound("panel_close", length + 0.05)
    s.add(tone(s, tick, 0.07, "sine", decay=0.06), gain=0.6)
    s.add(sweep_noise(s, length, 3500, 450) * adsr(int(length * SR), 0.03, 0.05, 0.6, 0.14) * 0.5, at=0.02)
    return s


@sound("ui")
def tab(notes=("D6", "G6"), gap=0.045):
    s = Sound("tab", 0.15)
    for i, n in enumerate(notes):
        s.add(tone(s, n, 0.06, "tri", decay=0.055), at=i * gap, gain=0.7)
    return s


@sound("ui")
def menu_open(notes=("C5", "D5", "E5", "G5", "A5"), gap=0.04):
    s = Sound("menu_open", gap * len(notes) + 0.15)
    for i, n in enumerate(notes):
        s.add(tone(s, n, 0.12, "tri", decay=0.11), at=i * gap, gain=0.6)
    return s


@sound("ui")
def menu_close(notes=("A5", "G5", "E5", "D5", "C5"), gap=0.03):
    s = Sound("menu_close", gap * len(notes) + 0.12)
    for i, n in enumerate(notes):
        s.add(tone(s, n, 0.1, "tri", decay=0.09), at=i * gap, gain=0.55 - 0.06 * i)
    return s


@sound("ui")
def toast(note="E6", length=0.08):
    s = Sound("toast", length + 0.02)
    s.add(tone(s, note, length, "sine", decay=0.075, glass=0.2))
    return s


@sound("ui")
def error(note="G3", length=0.16):
    # "No" is a soft low bonk on G3, never a buzzer
    s = Sound("error", length + 0.02)
    s.add(tone(s, note, length, "sine", attack=0.003, decay=0.14, glass=0.0))
    s.add(tone(s, note, length, "tri", decay=0.06, glass=0.0) * 0.25)
    return s


@sound("ui")
def purchase(notes=("C5", "E5", "G5", "A5", "C6"), spread=0.035):
    s = Sound("purchase", 0.75)
    s.add(chord(s, notes, 0.55, "tri", spread=spread, decay=0.5))
    s.add(crackle(s, 0.5, density=30, lo=5000, hi=14000) * perc(int(0.5 * SR), 0.01, 0.45) * 0.25, at=0.05)
    return s


@sound("ui")
def volts_tick(note="C7", length=0.018):
    s = Sound("volts_tick", length)
    s.add(tone(s, note, length, "sine", decay=0.016, glass=0.0))
    return s


# ---- gameplay -------------------------------------------------------------------
@sound("gameplay", exact=True)
def strike_warning(start="C3", end="C4"):
    # a rising electric charge hum lasting exactly WARNING_TIME
    length = CFG["WARNING_TIME"]
    s = Sound("strike_warning", length)
    n = len(s.buf)
    rise = np.linspace(0.25, 1.0, n) ** 1.5
    hum = glide(s, start, end, length, "tri", curve=1.6) + 0.5 * glide(s, "C4", "C5", length, "sine", curve=1.6)
    s.add(hum * rise * 0.5)
    density = crackle(s, length, density=90, lo=3000, hi=11000) * np.linspace(0.1, 1.0, n) ** 2
    s.add(density * 0.35)
    s.buf = fade(s.buf, 0.02, 0.012)
    return s


def _crack(name, seed_shift):
    s = Sound(name, 0.45)
    n = int(0.35 * SR)
    snap = noise(s, 0.35, 300, 16000) * perc(n, 0.0008, 0.12 + 0.03 * seed_shift)
    s.add(snap)
    s.add(crackle(s, 0.3, density=140, lo=2500, hi=14000) * perc(int(0.3 * SR), 0.001, 0.25) * 0.9)
    s.add(noise(s, 0.35, 40, 400) * perc(n, 0.002, 0.3) * 0.6)
    return s


for _i in range(1, 4):
    sound("gameplay", name=f"strike_crack_{_i}")(lambda i=_i: _crack(f"strike_crack_{i}", i))


def _thunder(name, length, booms):
    s = Sound(name, length)
    n = len(s.buf)
    body = noise(s, length, 25, 900, tilt=-6)
    env = np.zeros(n)
    for at, size, decay in booms:
        k = int(at * SR)
        env[k:] += size * perc(n - k, 0.04, decay)
    s.add(body * env)
    s.add(noise(s, length, 25, 120) * perc(n, 0.08, length * 0.8) * 0.7)
    return s


_TAKES = [
    (2.6, [(0.0, 1.0, 1.6), (0.35, 0.7, 1.8), (1.1, 0.4, 1.2)]),
    (2.8, [(0.0, 0.8, 1.2), (0.2, 1.0, 2.0), (0.9, 0.5, 1.5)]),
    (2.4, [(0.0, 1.0, 2.0), (0.6, 0.55, 1.4), (1.3, 0.3, 0.9)]),
]
for _i, (_len, _booms) in enumerate(_TAKES, 1):
    sound("thunder", name=f"thunder_{_i}")(lambda i=_i, l=_len, b=_booms: _thunder(f"thunder_{i}", l, b))


CATCH_NOTES = ("C5", "D5", "E5", "G5", "A5")  # rises as the bottle fills


def _catch(name, note):
    s = Sound(name, 0.45)
    # the zap into the bottle, then the glass clink
    s.add(crackle(s, 0.09, density=300, lo=3000, hi=12000) * perc(int(0.09 * SR), 0.002, 0.09) * 0.5)
    s.add(glide(s, "C5", note, 0.07, "sine") * perc(int(0.07 * SR), 0.002, 0.07) * 0.3)
    clink = tone(s, note, 0.35, "sine", decay=0.3, glass=0.35)
    clink += wave(2 * hz(note), len(clink)) * perc(len(clink), 0.001, 0.12) * 0.3
    s.add(clink, at=0.05)
    return s


for _i, _note in enumerate(CATCH_NOTES, 1):
    sound("gameplay", name=f"catch_{_i}")(lambda i=_i, n=_note: _catch(f"catch_{i}", n))


@sound("gameplay")
def bottle_full(fizz=0.6):
    s = Sound("bottle_full", fizz + 0.15)
    s.add(glide(s, "G4", "C4", 0.05, "sine") * perc(int(0.05 * SR), 0.001, 0.05))
    s.add(noise(s, 0.01, 800, 5000) * perc(int(0.01 * SR), 0.0005, 0.01) * 0.6)
    fz = noise(s, fizz, 4000, 15000) * perc(int(fizz * SR), 0.02, fizz) * 0.35
    fz *= 0.6 + 0.4 * np.abs(np.sin(np.linspace(0, 40, len(fz))))
    s.add(fz, at=0.04)
    return s


def _sell(name, notes, sparkle):
    s = Sound(name, 0.25 + 0.06 * len(notes) + sparkle)
    s.add(crackle(s, 0.08, density=250) * perc(int(0.08 * SR), 0.001, 0.08) * 0.5)
    s.add(chord(s, notes, 0.4 + sparkle * 0.5, "tri", spread=0.05, decay=0.35 + sparkle * 0.4), at=0.05)
    if sparkle:
        s.add(crackle(s, sparkle, density=40, lo=6000, hi=15000) * perc(int(sparkle * SR), 0.02, sparkle) * 0.3, at=0.12)
    return s


SELL = {
    "sell_small": (("E6", "G6"), 0.0),
    "sell_medium": (("C6", "E6", "G6"), 0.25),
    "sell_big": (("C6", "E6", "G6", "C7"), 0.6),
}
for _name, (_notes, _sp) in SELL.items():
    sound("gameplay", name=_name)(lambda n=_name, a=_notes, b=_sp: _sell(n, a, b))


@sound("gameplay")
def lucky(notes=("G5", "C6")):
    # x2: an assay's high grade or a Lucky Charges double
    s = Sound("lucky", 0.5)
    for i, n in enumerate(notes):
        s.add(tone(s, n, 0.25, "tri", decay=0.22, glass=0.3), at=i * 0.07, gain=0.7)
    s.add(crackle(s, 0.3, density=50, lo=6000, hi=15000) * perc(int(0.3 * SR), 0.01, 0.3) * 0.3, at=0.05)
    return s


@sound("gameplay")
def jackpot(notes=("C5", "E5", "G5", "C6", "E6", "G6")):
    # x4: both doubles at once
    s = Sound("jackpot", 1.1)
    for i, n in enumerate(notes):
        s.add(tone(s, n, 0.3, "tri", decay=0.28, glass=0.3), at=i * 0.055, gain=0.55)
    s.add(chord(s, ("C6", "E6", "G6"), 0.6, "soft", decay=0.55), at=0.33, gain=0.6)
    s.add(crackle(s, 0.8, density=70, lo=5000, hi=15000) * perc(int(0.8 * SR), 0.02, 0.8) * 0.35, at=0.1)
    return s


@sound("gameplay")
def tank_glug(bubbles=(("C3", "D3", 0.0), ("E3", "G3", 0.11), ("D3", "E3", 0.2)), size=0.09):
    s = Sound("tank_glug", 0.4)
    for start, end, at in bubbles:
        b = glide(s, start, end, size, "sine", curve=0.6) * perc(int(size * SR), 0.01, size)
        s.add(b, at=at, gain=0.8)
    s.add(noise(s, 0.35, 100, 900) * perc(int(0.35 * SR), 0.02, 0.3) * 0.15)
    return s


@sound("gameplay")
def balloon_bolt(whistle=("A6", "E6"), length=0.45):
    s = Sound("balloon_bolt", length + 0.4)
    s.add(glide(s, *whistle, length, "sine") * adsr(int(length * SR), 0.05, 0.1, 0.7, 0.05) * 0.4)
    s.add(_crack("balloon_bolt_crack", 1).buf * 0.8, at=length)
    return s


@sound("gameplay")
def forecast(note="A6", echoes=3):
    s = Sound("forecast", 0.6)
    for i in range(echoes):
        s.add(tone(s, note, 0.12, "sine", decay=0.11, glass=0.25), at=i * 0.12, gain=0.8 * 0.45**i)
    return s


@sound("gameplay")
def gate_bump(note="G3"):
    s = Sound("gate_bump", 0.25)
    s.add(tone(s, note, 0.2, "sine", attack=0.002, decay=0.16, glass=0.0))
    s.add(noise(s, 0.05, 60, 500) * perc(int(0.05 * SR), 0.001, 0.05) * 0.5)
    return s


@sound("gameplay")
def portal(start="C4", end="C6", length=0.9):
    s = Sound("portal", length + 0.1)
    n = int(length * SR)
    env = adsr(n, 0.15, 0.2, 0.7, 0.3)
    s.add((glide(s, start, end, length, "tri", curve=0.8) + glide(s, "G3", "G5", length, "sine", curve=0.8) * 0.6) * env * 0.4)
    s.add(sweep_noise(s, length, 300, 6000) * env * 0.35)
    s.add(crackle(s, length, density=40) * env * 0.2)
    return s


@sound("gameplay")
def zone_enter(chime=("G5", "C6")):
    s = Sound("zone_enter", 0.7)
    s.add(sweep_noise(s, 0.35, 400, 3000) * adsr(int(0.35 * SR), 0.12, 0.05, 0.6, 0.15) * 0.45)
    for i, n in enumerate(chime):
        s.add(tone(s, n, 0.35, "sine", decay=0.32, glass=0.3), at=0.22 + i * 0.09, gain=0.6)
    return s


# ---- rewards ---------------------------------------------------------------------
@sound("rewards")
def unlock(rise=("C4", "E4", "G4", "C5"), final=("C5", "E5", "G5", "C6")):
    # zone or world unlocked: a 2 s fanfare
    s = Sound("unlock", 2.0)
    for i, n in enumerate(rise):
        s.add(tone(s, n, 0.22, "soft", decay=0.2), at=i * 0.11, gain=0.5)
    held = chord(s, final, 1.4, "soft", decay=1.3, attack=0.02)
    s.add(held, at=0.45, gain=0.8)
    s.add(crackle(s, 1.2, density=40, lo=6000, hi=15000) * perc(int(1.2 * SR), 0.05, 1.1) * 0.25, at=0.45)
    return s


@sound("rewards")
def level_up(notes=("G4", "C5", "E5", "G5")):
    s = Sound("level_up", 1.0)
    for i, n in enumerate(notes):
        s.add(tone(s, n, 0.25 if i < 3 else 0.6, "soft", decay=0.22 if i < 3 else 0.55), at=i * 0.09, gain=0.6)
    s.add(crackle(s, 0.5, density=40, lo=6000, hi=15000) * perc(int(0.5 * SR), 0.02, 0.5) * 0.25, at=0.27)
    return s


@sound("rewards")
def hired(chime=("E5", "G5")):
    s = Sound("hired", 0.8)
    s.add(tone(s, "C3", 0.12, "sine", decay=0.1, glass=0.0) * 0.8)
    s.add(noise(s, 0.06, 80, 1500) * perc(int(0.06 * SR), 0.001, 0.05) * 0.6)
    for i, n in enumerate(chime):
        s.add(tone(s, n, 0.4, "sine", decay=0.38, glass=0.3), at=0.14 + i * 0.09, gain=0.6)
    return s


@sound("rewards")
def boost_start(start="C4", end="C5", top="G5", length=0.6):
    s = Sound("boost_start", length + 0.4)
    n = int(length * SR)
    s.add(glide(s, start, end, length, "tri", curve=1.4) * np.linspace(0.3, 1, n) * 0.5)
    s.add(crackle(s, length, density=80) * np.linspace(0, 1, n) ** 2 * 0.3)
    s.add(tone(s, top, 0.35, "soft", decay=0.33), at=length - 0.03, gain=0.55)
    return s


@sound("rewards")
def boost_end(start="C5", end="C4", length=0.6):
    s = Sound("boost_end", length + 0.05)
    n = int(length * SR)
    s.add(glide(s, start, end, length, "tri", curve=0.7) * np.linspace(1, 0.05, n) ** 1.3 * 0.55)
    s.add(crackle(s, length * 0.5, density=60) * np.linspace(0.6, 0, int(length * 0.5 * SR)) * 0.2)
    return s


@sound("rewards")
def daily(notes=("C5", "E5", "G5", "C6")):
    s = Sound("daily", 1.4)
    s.add(glide(s, "C4", "G4", 0.04, "sine") * perc(int(0.04 * SR), 0.001, 0.04) * 0.7)
    s.add(noise(s, 0.4, 5000, 15000) * perc(int(0.4 * SR), 0.005, 0.35) * 0.25, at=0.02)
    for i, n in enumerate(notes):
        s.add(tone(s, n, 0.25 if i < 3 else 0.75, "soft", decay=0.22 if i < 3 else 0.7), at=0.1 + i * 0.09, gain=0.55)
    return s


@sound("rewards")
def gift_ready(notes=("E5", "G5")):
    s = Sound("gift_ready", 1.1)
    for i, n in enumerate(notes):
        bell = tone(s, n, 0.9, "sine", decay=0.85, glass=0.4)
        bell += wave(2 * hz(n), len(bell)) * perc(len(bell), 0.002, 0.4) * 0.25
        s.add(bell, at=i * 0.16, gain=0.5)
    return s


@sound("rewards")
def gift_received(notes=("G4", "C5", "E5", "G5"), final=("C5", "E5", "G5", "C6")):
    s = Sound("gift_received", 1.8)
    crinkle = crackle(s, 0.3, density=200, lo=3000, hi=14000) * perc(int(0.3 * SR), 0.01, 0.3)
    s.add(crinkle * 0.45)
    for i, n in enumerate(notes):
        s.add(tone(s, n, 0.2, "soft", decay=0.18), at=0.25 + i * 0.08, gain=0.5)
    s.add(chord(s, final, 1.0, "soft", decay=0.95, attack=0.01), at=0.58, gain=0.75)
    s.add(crackle(s, 0.9, density=40, lo=6000, hi=15000) * perc(int(0.9 * SR), 0.02, 0.9) * 0.25, at=0.58)
    return s


@sound("rewards")
def server_storm(start="C3", end="C5", length=2.4):
    s = Sound("server_storm", 3.0)
    s.add(_thunder("server_storm_thunder", 3.0, [(0.0, 1.0, 2.2), (0.3, 0.8, 2.0)]).buf * 0.9)
    n = int(length * SR)
    synth = glide(s, start, end, length, "soft", curve=1.5) + 0.5 * glide(s, "G3", "G5", length, "soft", curve=1.5)
    s.add(synth * np.linspace(0.05, 1, n) ** 1.5 * adsr(n, 0.01, 0.01, 1, 0.25) * 0.5, at=0.2)
    s.add(crackle(s, length, density=70) * np.linspace(0, 1, n) ** 2 * 0.25, at=0.2)
    return s


# ---- loops (circular, so they repeat with no seam) ---------------------------------
def lfo(s, cycles, phase=0.0):
    """A 0..1 wobble that repeats exactly `cycles` times over the loop."""
    t = np.arange(len(s.buf)) / len(s.buf)
    return 0.5 + 0.5 * np.sin(2 * np.pi * cycles * t + phase)


def loop_tone(s, note):
    """A key note rounded to a whole number of cycles over the loop."""
    s.use(note)
    n = len(s.buf)
    cycles = round(hz(note) * n / SR)
    return np.sin(2 * np.pi * cycles * np.arange(n) / n)


@sound("ambience", loop=True)
def calm_loop(length=24.0):
    # calm wind and waves
    s = Sound("calm_loop", length)
    wind = noise(s, length, 150, 1800, tilt=-4) * (0.35 + 0.4 * lfo(s, 2, 1.0) * lfo(s, 3, 0.2))
    waves = noise(s, length, 200, 5000, tilt=-3)
    swell = lfo(s, 3, -1.2) ** 3  # three waves a loop, 8 s apart
    s.add(wind * 0.6 + waves * swell * 0.7)
    return s


@sound("ambience", loop=True)
def rain_loop(length=16.0, drops=900):
    s = Sound("rain_loop", length)
    s.add(noise(s, length, 600, 12000, tilt=-1.5) * (0.85 + 0.15 * lfo(s, 4)))
    tick = int(0.003 * SR)
    for _ in range(drops):
        d = s.rng.standard_normal(tick) * perc(tick, 0.0002, 0.003)
        s.add(d * s.rng.uniform(0.3, 1.2), at=s.rng.uniform(0, length), wrap=True)
    s.buf = band(s.buf, 120, 14000)
    return s


@sound("ambience", loop=True)
def gust_loop(length=20.0):
    s = Sound("gust_loop", length)
    base = noise(s, length, 80, 2500, tilt=-5)
    gusts = 0.2 + 0.8 * (lfo(s, 3, 0.4) ** 4 + 0.6 * lfo(s, 5, 2.1) ** 6)
    whistle = noise(s, length, 700, 1600) * lfo(s, 3, 0.4) ** 6 * 0.3
    s.add(base * gusts + whistle)
    return s


@sound("ambience", loop=True)
def hum_loop(length=8.0):
    # the power plant's electric hum: C2 and its harmonics (C3, G3, C4 stay in the key)
    s = Sound("hum_loop", length)
    s.add(loop_tone(s, "C2") * 0.6 + loop_tone(s, "C3") * 0.45 + loop_tone(s, "G3") * 0.25 + loop_tone(s, "C4") * 0.12)
    s.buf *= 0.85 + 0.15 * lfo(s, 16)
    buzz = crackle(s, length, density=25, lo=2000, hi=8000)
    s.buf += buzz * 0.12
    return s


# ---- build -----------------------------------------------------------------------------
def write_wav(path, x):
    pcm = np.clip(np.round(x * 32767), -32768, 32767).astype("<i2")
    with wavfile.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def render(name, group, loop, exact, fn):
    s = fn()
    s.name = name
    x = s.buf
    if loop:
        x = room(x, loop=True)
        x = seamless(np.concatenate([x, x[: int(0.05 * SR)]]))
        x = loudness(x, group, loop=True)
    elif exact:
        x = room(x)[: len(s.buf)]
        x = fade(loudness(x, group), 0, 0.012)
    else:
        x = trim(loudness(room(x), group))
    return x, sorted(s.notes)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "out")
    os.makedirs(out, exist_ok=True)
    CFG.update(config())
    manifest = []
    for name, group, loop, exact, fn in SOUNDS:
        x, notes = render(name, group, loop, exact, fn)
        write_wav(os.path.join(out, f"{name}.wav"), x)
        manifest.append(dict(name=name, group=group, loop=loop, exact=exact, notes=notes, seconds=len(x) / SR))
        print(f"{name:<16} {group:<9} {len(x) / SR:6.2f}s")
    with open(os.path.join(out, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)
    print(f"{len(manifest)} sounds -> {out}")


if __name__ == "__main__":
    main()
