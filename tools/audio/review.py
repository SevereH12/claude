#!/usr/bin/env python3
"""Checks the generated sounds before they're uploaded, and draws them.

  python3 tools/audio/review.py [outdir]      (default tools/audio/out)

Writes <outdir>/review.png (a waveform and spectrogram per sound) and
<outdir>/review.md (length, peak, RMS and group per sound). Exits non-zero
if any sound has:
- a peak above -1 dBFS
- an RMS more than 1.5 dB off its group's target (palette.GROUPS)
- a loop with a click at the seam
- a note outside C major pentatonic
- (not a loop) a tail longer than 3 s"""

import json
import os
import sys
import wave as wavfile

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from palette import GROUP_TOLERANCE, GROUPS, PEAK_CEILING, PENTATONIC, SR, db, measure  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
MAX_TAIL = 3.0  # seconds after the sound's body has died down 20 dB


def read_wav(path):
    with wavfile.open(path) as w:
        assert w.getframerate() == SR and w.getsampwidth() == 2 and w.getnchannels() == 1, path
        return np.frombuffer(w.readframes(w.getnframes()), "<i2").astype(float) / 32767


def tail_seconds(x):
    """Time from where the sound falls 20 dB under its peak for good to its
    last sample above -60 dBFS."""
    a = np.abs(x)
    body = np.nonzero(a > a.max() * 0.1)[0][-1]
    audible = np.nonzero(a > 10 ** (-60 / 20))[0][-1]
    return max(0, audible - body) / SR


def seam_jump(x):
    """How much bigger the jump from the last sample to the first is than
    the loop's own sample-to-sample movement (1.0 = typical)."""
    d = np.abs(np.diff(x))
    return abs(x[0] - x[-1]) / (np.percentile(d, 99.9) + 1e-9)


def spectrogram(x, width, height):
    size, hop = 1024, max(1, len(x) // width)
    frames = []
    win = np.hanning(size)
    pad = np.concatenate([x, np.zeros(size)])
    for i in range(width):
        seg = pad[i * hop : i * hop + size]
        if len(seg) < size:
            seg = np.concatenate([seg, np.zeros(size - len(seg))])
        frames.append(np.abs(np.fft.rfft(seg * win)))
    spec = np.array(frames).T  # freq x time
    f = np.fft.rfftfreq(size, 1 / SR)
    rows = np.geomspace(40, 20000, height)[::-1]
    idx = np.clip(np.searchsorted(f, rows), 0, len(f) - 1)
    level = 20 * np.log10(spec[idx] + 1e-9)
    level = np.clip((level + 30) / 70, 0, 1)
    r = (255 * np.clip(level * 2 - 0.2, 0, 1)).astype(np.uint8)
    g = (255 * np.clip(level * 1.6 - 0.6, 0, 1)).astype(np.uint8)
    b = (255 * np.clip(0.35 + level * 0.8 - np.clip(level * 2 - 1.4, 0, 1), 0, 1)).astype(np.uint8)
    return Image.fromarray(np.dstack([r, g, b]), "RGB")


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "out")
    manifest = json.load(open(os.path.join(out, "manifest.json")))
    rows, problems = [], []
    tile_w, wave_h, spec_h, label_h = 360, 54, 70, 18
    cols = 4
    lines = (len(manifest) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (tile_w + 10) + 10, lines * (label_h + wave_h + spec_h + 16) + 10), (20, 22, 30))
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("DejaVuSans.ttf", 12)
    except OSError:
        font = ImageFont.load_default()

    for i, item in enumerate(manifest):
        name, group, loop = item["name"], item["group"], item["loop"]
        x = read_wav(os.path.join(out, f"{name}.wav"))
        peak, rms = measure(x)
        target = GROUPS[group]
        bad = []
        if peak > PEAK_CEILING + 1e-6:
            bad.append(f"peak {peak:.1f} dBFS > {PEAK_CEILING}")
        if abs(rms - target) > GROUP_TOLERANCE:
            bad.append(f"RMS {rms:.1f} dB is {rms - target:+.1f} dB off {group} ({target})")
        off = [n for n in item["notes"] if n % 12 not in PENTATONIC]
        if off:
            bad.append(f"notes outside the key: {off}")
        tail = tail_seconds(x)
        if loop:
            jump = seam_jump(x)
            if jump > 1.5:
                bad.append(f"click at the loop seam ({jump:.1f}x the loop's normal sample jump)")
        elif tail > MAX_TAIL:
            bad.append(f"tail {tail:.1f}s > {MAX_TAIL}s")
        problems += [f"{name}: {b}" for b in bad]
        rows.append((name, group, loop, len(x) / SR, peak, rms, target, tail, "; ".join(bad) or "ok"))

        # the tile: label, waveform, spectrogram
        cx = 10 + (i % cols) * (tile_w + 10)
        cy = 10 + (i // cols) * (label_h + wave_h + spec_h + 16)
        colour = (255, 120, 120) if bad else (230, 230, 240)
        draw.text((cx, cy), f"{name}  {group}{' loop' if loop else ''}  {len(x) / SR:.2f}s  {rms:.1f} dB", fill=colour, font=font)
        top = cy + label_h
        draw.rectangle([cx, top, cx + tile_w, top + wave_h], fill=(32, 36, 50))
        mid = top + wave_h / 2
        hop = max(1, len(x) // tile_w)
        for px in range(min(tile_w, len(x) // hop)):
            seg = x[px * hop : (px + 1) * hop]
            draw.line([cx + px, mid - seg.max() * wave_h / 2, cx + px, mid - seg.min() * wave_h / 2], fill=(255, 214, 70))
        ceiling = 10 ** (PEAK_CEILING / 20) * wave_h / 2
        draw.line([cx, mid - ceiling, cx + tile_w, mid - ceiling], fill=(90, 90, 110))
        sheet.paste(spectrogram(x, tile_w, spec_h), (cx, top + wave_h + 2))

    sheet.save(os.path.join(out, "review.png"))
    with open(os.path.join(out, "review.md"), "w") as f:
        f.write("| Sound | Group | Loop | Length | Peak | RMS | Target | Tail | Check |\n")
        f.write("| --- | --- | --- | --- | --- | --- | --- | --- | --- |\n")
        for name, group, loop, length, peak, rms, target, tail, check in rows:
            f.write(
                f"| {name} | {group} | {'yes' if loop else ''} | {length:.2f}s | {peak:.1f} | {rms:.1f} | "
                f"{target:.0f} | {tail:.2f}s | {check} |\n"
            )
    print(f"wrote {out}/review.png and review.md ({len(rows)} sounds)")
    if problems:
        print("FAIL:")
        for p in problems:
            print("  " + p)
        sys.exit(1)
    print("ok: every sound passes")


if __name__ == "__main__":
    main()
