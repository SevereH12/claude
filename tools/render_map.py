#!/usr/bin/env python3
"""Render a map dump (from tools/harness/buildmap.luau) to images.

    python3 tools/render_map.py map.json out_prefix

Writes out_prefix_top.png (top-down, north up) and out_prefix_side.png
(looking north from the south). Parts are drawn in their real colours,
painter-sorted, with zone volumes and sell areas outlined and a 50-stud grid.
"""

import json
import math
import sys

from PIL import Image, ImageDraw, ImageFont

TERRAIN_COLORS = {
    "Water": (38, 92, 140),
    "Grass": (78, 125, 66),
    "LeafyGrass": (70, 120, 60),
    "Sand": (214, 190, 130),
    "Sandstone": (190, 120, 80),
    "Rock": (110, 110, 115),
    "Slate": (90, 92, 100),
    "Basalt": (55, 55, 62),
    "Cobblestone": (130, 130, 128),
    "Pavement": (150, 150, 150),
    "Concrete": (160, 160, 160),
    "Asphalt": (60, 60, 64),
    "Mud": (90, 70, 50),
    "Ground": (110, 90, 60),
    "Ice": (170, 210, 230),
    "Glacier": (190, 220, 240),
    "Snow": (235, 240, 245),
    "Salt": (220, 220, 215),
    "Limestone": (205, 195, 170),
    "CrackedLava": (120, 50, 30),
    "Brick": (150, 80, 60),
    "WoodPlanks": (140, 100, 60),
}


def rotation(cf):
    # cf = [x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22]
    return [[cf[3], cf[4], cf[5]], [cf[6], cf[7], cf[8]], [cf[9], cf[10], cf[11]]]


def corners(cf, size):
    r = rotation(cf)
    cx, cy, cz = cf[0], cf[1], cf[2]
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    out = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                lx, ly, lz = sx * hx, sy * hy, sz * hz
                out.append(
                    (
                        cx + r[0][0] * lx + r[0][1] * ly + r[0][2] * lz,
                        cy + r[1][0] * lx + r[1][1] * ly + r[1][2] * lz,
                        cz + r[2][0] * lx + r[2][1] * ly + r[2][2] * lz,
                    )
                )
    return out


def hull(points):
    pts = sorted(set(points))
    if len(pts) <= 2:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def shade(color, factor):
    return tuple(max(0, min(255, int(c * factor))) for c in color)


def to255(c):
    return tuple(int(round(v * 255)) for v in c)


def main():
    data = json.load(open(sys.argv[1]))
    prefix = sys.argv[2]
    parts = data["parts"]
    terrain = data["terrain"]

    visible = [p for p in parts if p["transparency"] < 0.98]
    zones = [p for p in parts if ".Zones." in p["path"]]
    sells = [p for p in parts if p["name"] in ("SellPad", "SellArea")]

    # world bounds from land terrain and parts (ignore the ocean slabs)
    xs, zs = [], []
    for op in terrain:
        if op["kind"] == "FillCylinder" and op["material"] != "Water":
            xs += [op["cframe"][0] - op["radius"], op["cframe"][0] + op["radius"]]
            zs += [op["cframe"][2] - op["radius"], op["cframe"][2] + op["radius"]]
        elif op["kind"] in ("FillBlock", "FillWedge") and op["material"] != "Water" and max(op["size"]) < 900:
            xs += [op["cframe"][0] - op["size"][0] / 2, op["cframe"][0] + op["size"][0] / 2]
            zs += [op["cframe"][2] - op["size"][2] / 2, op["cframe"][2] + op["size"][2] / 2]
    for p in visible:
        if max(p["size"]) < 900:
            xs.append(p["cframe"][0])
            zs.append(p["cframe"][2])
    pad = 30
    minx, maxx = min(xs) - pad, max(xs) + pad
    minz, maxz = min(zs) - pad, max(zs) + pad
    span = max(maxx - minx, maxz - minz)
    W = 1600
    scale = W / span
    H = int((maxz - minz) * scale)
    W = int((maxx - minx) * scale)

    def P(x, z):
        return ((x - minx) * scale, (z - minz) * scale)  # north (-Z) is up

    font = ImageFont.load_default()

    # ---------------- top-down ----------------
    img = Image.new("RGB", (W, H), TERRAIN_COLORS["Water"])
    draw = ImageDraw.Draw(img, "RGBA")

    # terrain ops in order (later fills overwrite earlier ones, like Roblox)
    for op in terrain:
        color = TERRAIN_COLORS.get(op.get("material", ""), (255, 0, 255))
        if op["kind"] == "FillCylinder":
            cx, cz, r = op["cframe"][0], op["cframe"][2], op["radius"]
            top = op["cframe"][1] + op["height"] / 2
            x0, y0 = P(cx - r, cz - r)
            x1, y1 = P(cx + r, cz + r)
            draw.ellipse([x0, y0, x1, y1], fill=shade(color, 0.9 + top / 120))
        elif op["kind"] == "FillBall":
            cx, cz, r = op["center"][0], op["center"][2], op["radius"]
            x0, y0 = P(cx - r, cz - r)
            x1, y1 = P(cx + r, cz + r)
            draw.ellipse([x0, y0, x1, y1], fill=shade(color, 1.0 + op["center"][1] / 120))
        elif op["kind"] in ("FillBlock", "FillWedge"):
            cs = corners(op["cframe"], op["size"])
            top = max(c[1] for c in cs)
            poly = hull([P(c[0], c[2]) for c in cs])
            factor = 0.9 + top / 120 if op["kind"] == "FillBlock" else 0.8 + top / 150
            draw.polygon(poly, fill=shade(color, factor))

    # grid
    step = 50
    gx = math.floor(minx / step) * step
    while gx <= maxx:
        x, _ = P(gx, 0)
        draw.line([(x, 0), (x, H)], fill=(255, 255, 255, 40))
        draw.text((x + 2, 2), str(int(gx)), fill=(255, 255, 255, 160), font=font)
        gx += step
    gz = math.floor(minz / step) * step
    while gz <= maxz:
        _, y = P(0, gz)
        draw.line([(0, y), (W, y)], fill=(255, 255, 255, 40))
        draw.text((2, y + 2), str(int(gz)), fill=(255, 255, 255, 160), font=font)
        gz += step

    # parts, lowest tops first so taller things draw over
    def top_y(p):
        return max(c[1] for c in corners(p["cframe"], p["size"]))

    for p in sorted(visible, key=top_y):
        if max(p["size"]) >= 900:
            continue
        color = to255(p["color"])
        alpha = int(255 * (1 - p["transparency"]))
        if p["material"] == "ForceField":
            alpha = min(alpha, 110)
        if p["material"] == "Neon":
            color = shade(color, 1.15)
        factor = 0.75 + min(top_y(p), 60) / 160
        fill = shade(color, factor) + (alpha,)
        cs = corners(p["cframe"], p["size"])
        if p["shape"] == "Ball":
            cx, cz, r = p["cframe"][0], p["cframe"][2], p["size"][0] / 2
            x0, y0 = P(cx - r, cz - r)
            x1, y1 = P(cx + r, cz + r)
            draw.ellipse([x0, y0, x1, y1], fill=fill, outline=(0, 0, 0, 60))
        elif p["shape"] == "Cylinder":
            # vertical cylinders show as discs from above
            r = rotation(p["cframe"])
            axis_up = abs(r[1][0]) > 0.9
            if axis_up:
                cx, cz, rad = p["cframe"][0], p["cframe"][2], p["size"][1] / 2
                x0, y0 = P(cx - rad, cz - rad)
                x1, y1 = P(cx + rad, cz + rad)
                draw.ellipse([x0, y0, x1, y1], fill=fill, outline=(0, 0, 0, 60))
            else:
                draw.polygon(hull([P(c[0], c[2]) for c in cs]), fill=fill, outline=(0, 0, 0, 60))
        else:
            draw.polygon(hull([P(c[0], c[2]) for c in cs]), fill=fill, outline=(0, 0, 0, 60))

    # gameplay overlays
    for p in zones:
        cs = corners(p["cframe"], p["size"])
        draw.polygon(hull([P(c[0], c[2]) for c in cs]), outline=(255, 255, 255, 220), width=3)
        x, y = P(p["cframe"][0], p["cframe"][2])
        draw.text((x - 20, y), "ZONE " + p["name"], fill=(255, 255, 255, 255), font=font)
    for p in sells:
        cs = corners(p["cframe"], p["size"])
        draw.polygon(hull([P(c[0], c[2]) for c in cs]), outline=(255, 40, 200, 255), width=3)
        x, y = P(p["cframe"][0], p["cframe"][2])
        draw.text((x - 10, y + 8), "SELL", fill=(255, 40, 200, 255), font=font)
    for p in parts:
        if p["class"] == "SpawnLocation":
            x, y = P(p["cframe"][0], p["cframe"][2])
            draw.ellipse([x - 6, y - 6, x + 6, y + 6], outline=(0, 255, 255, 255), width=3)
            draw.text((x + 8, y - 6), "SPAWN", fill=(0, 255, 255, 255), font=font)

    draw.text((10, H - 20), "top-down, north up, 50-stud grid", fill=(255, 255, 255, 200), font=font)
    img.save(prefix + "_top.png")

    # ---------------- side view (looking north) ----------------
    ys = [c[1] for p in visible if max(p["size"]) < 900 for c in corners(p["cframe"], p["size"])]
    miny, maxy = -20, max(ys + [40]) + 10
    SH = int((maxy - miny) * scale) + 40
    side = Image.new("RGB", (W, SH), (150, 165, 190))
    sd = ImageDraw.Draw(side, "RGBA")

    def S(x, y):
        return ((x - minx) * scale, (maxy - y) * scale + 20)

    # water line and terrain silhouettes
    sd.rectangle([0, S(0, -2)[1], W, SH], fill=TERRAIN_COLORS["Water"])
    for op in terrain:
        if op.get("material") == "Water":
            continue
        color = TERRAIN_COLORS.get(op.get("material", ""), (255, 0, 255))
        if op["kind"] == "FillCylinder":
            cx, r = op["cframe"][0], op["radius"]
            y0, y1 = op["cframe"][1] - op["height"] / 2, op["cframe"][1] + op["height"] / 2
            sd.rectangle([S(cx - r, y1), S(cx + r, y0)], fill=shade(color, 0.8))
        elif op["kind"] == "FillBall":
            cx, cy, r = op["center"][0], op["center"][1], op["radius"]
            sd.ellipse([S(cx - r, cy + r), S(cx + r, cy - r)], fill=shade(color, 0.8))
        elif op["kind"] in ("FillBlock", "FillWedge"):
            cs = corners(op["cframe"], op["size"])
            if op["kind"] == "FillWedge":
                # approximate wedge silhouette by its profile in X/Y
                pts = [S(c[0], c[1]) for c in cs]
                sd.polygon(hull(pts), fill=shade(color, 0.7))
            else:
                sd.polygon(hull([S(c[0], c[1]) for c in cs]), fill=shade(color, 0.8))

    def far_first(p):
        return min(c[2] for c in corners(p["cframe"], p["size"]))

    for p in sorted(visible, key=far_first):
        if max(p["size"]) >= 900:
            continue
        color = to255(p["color"])
        alpha = int(255 * (1 - p["transparency"]))
        if p["material"] == "ForceField":
            alpha = min(alpha, 90)
        cs = corners(p["cframe"], p["size"])
        if p["shape"] == "Ball":
            cx, cy, r = p["cframe"][0], p["cframe"][1], p["size"][0] / 2
            sd.ellipse([S(cx - r, cy + r), S(cx + r, cy - r)], fill=color + (alpha,), outline=(0, 0, 0, 60))
        else:
            sd.polygon(hull([S(c[0], c[1]) for c in cs]), fill=color + (alpha,), outline=(0, 0, 0, 60))
    for p in zones:
        cs = corners(p["cframe"], p["size"])
        sd.polygon(hull([S(c[0], c[1]) for c in cs]), outline=(255, 255, 255, 200), width=2)
    sd.text((10, 4), "side view, looking north (x right, y up)", fill=(0, 0, 0, 220), font=font)
    side.save(prefix + "_side.png")
    print("wrote", prefix + "_top.png", prefix + "_side.png", f"({W}x{H}, scale {scale:.2f}px/stud)")


if __name__ == "__main__":
    main()
