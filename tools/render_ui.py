#!/usr/bin/env python3
"""Draws where the HUD goes on each device, from test_layout's numbers.

    lune run tools/harness/test_layout.luau preview.json
    python3 tools/render_ui.py preview.json out.png

One tile per device, drawn to the same height so the shapes compare:
the screen, Roblox's top-bar buttons (grey corners), the TV-safe edge (console), the
thumbstick and jump areas (touch, red), and every HUD piece in design
pixels times the device's UI scale, as it would sit on that screen.
"""

import json
import sys

from PIL import Image, ImageDraw

COLORS = {
    "volts": (255, 214, 60),
    "storm": (110, 220, 140),
    "goal": (100, 160, 255),
    "bar": (70, 90, 230),
    "menu": (44, 52, 92),
    "card": (120, 130, 170),
    "toasts": (235, 235, 245),
    "banner": (200, 120, 255),
    "test": (255, 150, 30),
}
LABELS = {
    "volts": "VOLTS",
    "storm": "STORM",
    "goal": "GOAL",
    "bar": "BOTTLE",
    "menu": "MENU",
    "card": "menu card (open)",
    "toasts": "toasts",
    "banner": "zone banner",
    "test": "TEST",
}
TILE_H = 420


def main():
    devices = json.load(open(sys.argv[1]))
    out = sys.argv[2] if len(sys.argv) > 2 else "ui_preview.png"
    tiles = []
    for d in devices:
        vw, vh = d["viewport"]
        k = TILE_H / vh  # pixels of this drawing per real pixel
        img = Image.new("RGB", (int(vw * k) + 2, TILE_H + 28), (24, 28, 44))
        dr = ImageDraw.Draw(img)
        dr.rectangle([0, 0, vw * k, vh * k], fill=(64, 110, 150), outline=(255, 255, 255))
        edge = d["edge"]
        s = d["scale"]
        # the safe area's top left in real pixels
        ox, oy = vw * edge, vh * edge
        if edge:
            dr.rectangle([ox * k, oy * k, (vw - ox) * k, (vh - oy) * k], outline=(255, 255, 255))
        left, right, height = d["topbar"]
        if height > 0:
            ax = d["area"][0]
            for x0, x1 in ((0, left), (right, ax)):
                dr.rectangle(
                    [(ox + x0 * s) * k, oy * k, (ox + x1 * s) * k, (oy + height * s) * k],
                    fill=(90, 90, 100),
                )
        for z in d["thumbs"]:
            x, y, w, h = z
            dr.rectangle(
                [(ox + x * s) * k, (oy + y * s) * k, (ox + (x + w) * s) * k, (oy + (y + h) * s) * k],
                outline=(235, 75, 75),
            )
        order = ["card", "banner", "toasts", "test", "volts", "storm", "goal", "bar", "menu"]
        for key in order:
            x, y, w, h = d["hud"][key]
            box = [(ox + x * s) * k, (oy + y * s) * k, (ox + (x + w) * s) * k, (oy + (y + h) * s) * k]
            if key in ("card", "banner", "toasts", "test"):
                dr.rectangle(box, outline=COLORS[key])
            else:
                dr.rounded_rectangle(box, radius=4, fill=COLORS[key], outline=(6, 8, 18))
            dr.text((box[0] + 3, box[1] + 2), LABELS[key], fill=(0, 0, 0) if key not in ("card", "banner", "toasts", "test", "menu", "bar") else (255, 255, 255))
        dr.text((4, TILE_H + 8), f"{d['name']}  ({d['class']}, UI scale {s:.2f})", fill=(255, 255, 255))
        tiles.append(img)

    # pack tiles into rows about 1800 px wide
    rows, row, width = [], [], 0
    for t in tiles:
        if row and width + t.width > 1800:
            rows.append(row)
            row, width = [], 0
        row.append(t)
        width += t.width + 12
    rows.append(row)
    W = max(sum(t.width + 12 for t in r) for r in rows)
    H = sum(TILE_H + 40 for _ in rows)
    sheet = Image.new("RGB", (W, H), (12, 14, 28))
    y = 0
    for r in rows:
        x = 0
        for t in r:
            sheet.paste(t, (x, y))
            x += t.width + 12
        y += TILE_H + 40
    sheet.save(out)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
