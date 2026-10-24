"""The one sound palette every Storm Bottler effect is made from: the key
(C major pentatonic), the envelopes, the glassy shimmer, the electric
crackle, the one small room and the loudness groups. tools/audio/sfx.py
builds each sound from these; review.py checks the results.

numpy only. Everything is deterministic: each sound gets its own random
generator seeded from its name."""

import zlib

import numpy as np

SR = 48000

# --- the key -----------------------------------------------------------------
# C major pentatonic only. Notes are names like "C5" (MIDI 72) or MIDI numbers.
PENTATONIC = {0, 2, 4, 7, 9}  # C D E G A, as pitch classes
_NAMES = {"C": 0, "D": 2, "E": 4, "G": 7, "A": 9}

# --- loudness groups (RMS in dBFS, measured by `measure`) --------------------
GROUPS = {
    "ui": -24.0,
    "gameplay": -18.0,
    "rewards": -16.0,
    "thunder": -12.0,
    "ambience": -20.0,  # the loops (not in the prompt's table: under the effects)
}
PEAK_CEILING = -1.0  # dBFS: no sample above this
GROUP_TOLERANCE = 1.5  # dB either side of the group target


def midi(note):
    """'C5' -> 72. Raises for a note outside the pentatonic set."""
    if isinstance(note, (int, np.integer)):
        value = int(note)
    else:
        value = 12 * (int(note[1:]) + 1) + _NAMES[note[0]]
    if value % 12 not in PENTATONIC:
        raise ValueError(f"{note} is not in C major pentatonic")
    return value


def hz(note):
    return 440.0 * 2 ** ((midi(note) - 69) / 12)


class Sound:
    """Collects one sound's samples and the notes it used."""

    def __init__(self, name, seconds):
        self.name = name
        self.notes = set()
        self.rng = np.random.default_rng(zlib.crc32(name.encode()))
        self.buf = np.zeros(int(round(seconds * SR)))

    def t(self, seconds):
        return np.arange(int(round(seconds * SR))) / SR

    def add(self, signal, at=0.0, gain=1.0, wrap=False):
        """Mixes `signal` in at `at` seconds (wrap: round the end of a loop)."""
        start = int(round(at * SR))
        if wrap:
            idx = (start + np.arange(len(signal))) % len(self.buf)
            np.add.at(self.buf, idx, signal * gain)
            return
        end = min(len(self.buf), start + len(signal))
        if end > start:
            self.buf[start:end] += signal[: end - start] * gain

    def use(self, *notes):
        for n in notes:
            self.notes.add(midi(n))


# --- envelopes ---------------------------------------------------------------
def perc(n, attack=0.004, decay=0.25):
    """A fast attack and an exponential decay (decay = seconds to -60 dB)."""
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-6.9 * np.maximum(t - attack, 0) / decay)


def adsr(n, attack=0.01, decay=0.1, sustain=0.7, release=0.2):
    t = np.arange(n) / SR
    length = n / SR
    env = np.where(
        t < attack,
        t / attack,
        np.where(t < attack + decay, 1 - (1 - sustain) * (t - attack) / decay, sustain),
    )
    tail = np.clip((length - t) / release, 0, 1)
    return env * tail


def fade(x, inn=0.003, out=0.01):
    x = x.copy()
    a, b = int(inn * SR), int(out * SR)
    if a:
        x[:a] *= np.linspace(0, 1, a)
    if b:
        x[-b:] *= np.linspace(1, 0, b)
    return x


# --- tone sources ------------------------------------------------------------
def wave(freq, n, kind="sine", phase=0.0):
    """freq is a number or a per-sample array (for glides)."""
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    ph = 2 * np.pi * np.cumsum(f) / SR + phase
    if kind == "sine":
        return np.sin(ph)
    if kind == "tri":
        return 2 / np.pi * np.arcsin(np.sin(ph))
    if kind == "soft":  # a few odd harmonics: a warm synth for fanfares
        return np.sin(ph) + 0.25 * np.sin(3 * ph) + 0.08 * np.sin(5 * ph)
    raise ValueError(kind)


def tone(snd, note, seconds, kind="sine", attack=0.004, decay=None, env=None, glass=0.12):
    """The core tonal voice: a soft sine or triangle plus the glassy shimmer
    (a quiet partial two octaves up, which stays in the key). Records the note."""
    snd.use(note)
    n = int(seconds * SR)
    f = hz(note)
    e = env if env is not None else perc(n, attack, decay or seconds)
    body = wave(f, n, kind)
    shine = wave(4 * f, n, "sine") * perc(n, 0.002, min(0.12, seconds)) * glass
    return (body + shine) * e


def glide(snd, start, end, seconds, kind="sine", curve=1.0):
    """A pitch sweep from one key note to another (both recorded)."""
    snd.use(start, end)
    n = int(seconds * SR)
    x = np.linspace(0, 1, n) ** curve
    f = hz(start) * (hz(end) / hz(start)) ** x
    return wave(f, n, kind)


def chord(snd, notes, seconds, kind="sine", spread=0.0, decay=None, attack=0.004):
    """Notes together (or rolled `spread` seconds apart)."""
    n = int((seconds + spread * len(notes)) * SR)
    out = np.zeros(n)
    for i, note in enumerate(notes):
        v = tone(snd, note, seconds, kind, attack=attack, decay=decay)
        s = int(i * spread * SR)
        out[s : s + len(v)] += v
    return out / max(1, len(notes)) ** 0.5


# --- noise ---------------------------------------------------------------------
def band(x, lo=20.0, hi=20000.0, tilt=0.0):
    """FFT band filter (circular, so a loop stays seamless). tilt: dB per
    octave above 1 kHz (negative = darker)."""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    g = 1 / (1 + (lo / np.maximum(f, 1e-3)) ** 4) / (1 + (f / hi) ** 4)
    if tilt:
        g = g * (np.maximum(f, 1.0) / 1000.0) ** (tilt / 6.02)
    return np.fft.irfft(spec * g, len(x))


def noise(snd, seconds, lo=20.0, hi=20000.0, tilt=0.0):
    x = snd.rng.standard_normal(int(seconds * SR))
    x = band(x, lo, hi, tilt)
    return x / (np.sqrt(np.mean(x**2)) + 1e-12)


def sweep_noise(snd, seconds, f0, f1, width=1.0):
    """Noise through a band that moves from f0 to f1 Hz (a whoosh): made by
    mixing a few fixed bands with moving gains."""
    n = int(seconds * SR)
    x = snd.rng.standard_normal(n)
    out = np.zeros(n)
    centres = np.geomspace(min(f0, f1) / 1.5, max(f0, f1) * 1.5, 10)
    track = np.geomspace(f0, f1, n)
    for c in centres:
        b = band(x, c / (1 + width / 2), c * (1 + width / 2))
        g = np.exp(-(np.log(track / c) ** 2) / 0.18)
        out += b * g
    return out / (np.sqrt(np.mean(out**2)) + 1e-12)


def crackle(snd, seconds, density=60.0, lo=2500.0, hi=12000.0, burst=0.004):
    """The electric crackle: short filtered-noise bursts at random times
    (`density` per second), each a few ms long."""
    n = int(seconds * SR)
    out = np.zeros(n)
    count = max(1, int(density * seconds))
    for _ in range(count):
        at = int(snd.rng.uniform(0, n))
        length = int(snd.rng.uniform(0.5, 1.5) * burst * SR) + 8
        b = snd.rng.standard_normal(length) * perc(length, 0.0003, length / SR)
        b *= snd.rng.uniform(0.3, 1.0)
        end = min(n, at + length)
        out[at:end] += b[: end - at]
    out = band(out, lo, hi)
    return out / (np.max(np.abs(out)) + 1e-12)


# --- the one room --------------------------------------------------------------
ROOM_SECONDS = 0.45
ROOM_MIX = 0.16


def _room_ir():
    rng = np.random.default_rng(7)
    n = int(ROOM_SECONDS * SR)
    t = np.arange(n) / SR
    ir = rng.standard_normal(n) * np.exp(-6.9 * t / ROOM_SECONDS)
    for delay, gain in ((0.011, 0.5), (0.019, 0.35), (0.029, 0.25), (0.041, 0.18)):
        ir[int(delay * SR)] += gain * 6
    ir = band(np.concatenate([ir, np.zeros(n)]), 180, 7000)[:n]  # padded: no wrap-around
    ir[: int(0.006 * SR)] = 0  # a little pre-delay
    ir *= np.linspace(1, 0, n) ** 0.5  # and no step at the end
    return ir / np.sqrt(np.sum(ir**2))


ROOM_IR = _room_ir()


def room(x, mix=ROOM_MIX, loop=False):
    """The same small, short reverb on every sound (loop: circular, so the
    seam stays clean). Adds the tail to one-shots."""
    if loop:
        wet = np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(ROOM_IR, len(x)), len(x))
        return x * (1 - mix) + wet * mix * 2.2
    n = len(x) + len(ROOM_IR)
    size = 1 << (n - 1).bit_length()
    wet = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ROOM_IR, size), size)[:n]
    dry = np.concatenate([x, np.zeros(len(ROOM_IR))])
    return dry * (1 - mix) + wet * mix * 2.2


def seamless(x, seconds=0.05):
    """Loops: the last `seconds` crossfade into the first (equal power), and
    that overlap is cut off the end."""
    n = int(seconds * SR)
    head, tail = x[:n], x[-n:]
    a = np.sin(np.linspace(0, np.pi / 2, n))
    out = x[:-n].copy()
    out[:n] = head * a + tail * np.cos(np.linspace(0, np.pi / 2, n))
    return out


# --- loudness ---------------------------------------------------------------------
def db(x):
    return 20 * np.log10(max(float(x), 1e-12))


def measure(x):
    """(peak dBFS, RMS dBFS). The RMS is over the sound's active part: the
    10 ms frames within 20 dB of its loudest frame, so a reverb tail or the
    silence after a click doesn't count."""
    frame = int(0.01 * SR)
    usable = len(x) // frame * frame
    if usable == 0:
        return db(np.max(np.abs(x))), db(np.sqrt(np.mean(x**2)))
    frames = x[:usable].reshape(-1, frame)
    energy = np.mean(frames**2, axis=1)
    gate = energy >= energy.max() * 10 ** (-20 / 10)
    rms = np.sqrt(np.mean(energy[gate]))
    return db(np.max(np.abs(x))), db(rms)


def _maxfilter(a, radius):
    m = a.copy()
    step = 1
    while step <= radius:
        m = np.maximum(m, np.maximum(np.roll(m, step), np.roll(m, -step)))
        step *= 2
    return m


def limit(x, ceiling_db=PEAK_CEILING - 0.2, loop=False):
    """A smooth look-ahead peak limiter (no sample over the ceiling)."""
    c = 10 ** (ceiling_db / 20)
    radius = int(0.002 * SR)
    env = _maxfilter(np.abs(x), 2 * radius)
    win = np.hanning(2 * radius + 1)
    win /= win.sum()
    if loop:
        env = np.real(np.fft.ifft(np.fft.fft(env) * np.fft.fft(np.roll(np.pad(win, (0, len(env) - len(win))), -radius))))
    else:
        env = np.convolve(env, win, mode="same")
    gain = np.minimum(1.0, c / np.maximum(env, 1e-12))
    return np.clip(x * gain, -c, c)


def loudness(x, group, loop=False):
    """Scales to the group's RMS target, limiting peaks, and repeats until
    both hold."""
    target = GROUPS[group]
    y = x
    for _ in range(8):
        _, rms = measure(y)
        y = limit(y * 10 ** ((target - rms) / 20), loop=loop)
        _, rms = measure(y)
        if abs(rms - target) < 0.3:
            break
    return y


def trim(x, floor_db=-60.0, keep=0.02):
    """Cuts trailing silence below `floor_db` (keeping `keep` seconds)."""
    above = np.nonzero(np.abs(x) > 10 ** (floor_db / 20))[0]
    if len(above) == 0:
        return x
    end = min(len(x), above[-1] + int(keep * SR))
    return fade(x[:end], 0, 0.01)
