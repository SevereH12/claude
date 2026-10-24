#!/usr/bin/env python3
"""Packs the generated sounds into a few uploads (Roblox allows only 10
audio uploads a month on an account that isn't ID-verified):

- the one-shot effects into three sheets (UI, Gameplay, Rewards), with
  0.5 s of silence between sounds
- each loop as its own file

  python3 tools/audio/pack.py [outdir]      (default tools/audio/out)

Encodes <outdir>/<File>.ogg with ffmpeg and writes tools/audio/sheets.json:
each file's name, and each sound's file, start and length in seconds (the
game plays one sound off a sheet with a PlaybackRegion)."""

import json
import os
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from palette import SR  # noqa: E402
from review import read_wav  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
GAP = 0.5  # seconds of silence between sounds on a sheet
LEAD = 0.1  # before the first sound (decoder start-up)
SHEETS = {"ui": "SfxUI", "gameplay": "SfxGameplay", "thunder": "SfxGameplay", "rewards": "SfxRewards"}


def loop_file(name):
    # calm_loop -> AmbCalm
    return "Amb" + name.removesuffix("_loop").title().replace("_", "")


def encode(samples, path):
    raw = np.clip(np.round(samples * 32767), -32768, 32767).astype("<i2").tobytes()
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-",
         "-c:a", "libvorbis", "-q:a", "6", path],
        input=raw, check=True,
    )


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "out")
    manifest = json.load(open(os.path.join(out, "manifest.json")))
    sheets, sounds, files = {}, {}, {}
    for item in manifest:
        name = item["name"]
        x = read_wav(os.path.join(out, f"{name}.wav"))
        if item["loop"]:
            file = loop_file(name)
            files[file] = {"loop": True}
            sounds[name] = {"file": file, "start": 0, "length": round(len(x) / SR, 4), "group": item["group"], "loop": True}
            encode(x, os.path.join(out, f"{file}.ogg"))
            continue
        file = SHEETS[item["group"]]
        parts = sheets.setdefault(file, [np.zeros(int(LEAD * SR))])
        start = sum(len(p) for p in parts) / SR
        parts += [x, np.zeros(int(GAP * SR))]
        sounds[name] = {"file": file, "start": round(start, 4), "length": round(len(x) / SR, 4), "group": item["group"], "loop": False}
    for file, parts in sheets.items():
        files[file] = {"loop": False}
        encode(np.concatenate(parts), os.path.join(out, f"{file}.ogg"))
    for file in files:
        files[file]["path"] = f"{file}.ogg"
        files[file]["seconds"] = round(max(s["start"] + s["length"] for s in sounds.values() if s["file"] == file), 2)
    with open(os.path.join(HERE, "sheets.json"), "w") as f:
        json.dump({"files": files, "sounds": sounds}, f, indent=1)
        f.write("\n")
    print(f"{len(files)} files ({', '.join(files)}) -> {out}; layout in tools/audio/sheets.json")


if __name__ == "__main__":
    main()
