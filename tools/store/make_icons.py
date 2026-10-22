"""Draws a 512x512 icon for every item in store_items.json, in the game UI's
look (Lib/UI.luau): the navy panel gradient, a soft glow in the item's
colour, one flat symbol with the UI's thick dark outline, and Luckiest Guy
text (UI.FONT_TITLE). Symbols stay inside the middle circle, because Roblox
shows game pass icons cropped to a circle.
   python3 tools/store/make_icons.py <outdir> [LuckiestGuy-Regular.ttf]
Without the font file, text falls back to DejaVu Sans Bold."""
import math, os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

from items import GROUP_KIND, load

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = 512
N = OUT * 4  # draw big, then shrink, for smooth edges

# UI.COLORS
PANEL_TOP = (44, 52, 92)
PANEL_BOTTOM = (20, 23, 44)
STROKE = (6, 8, 18)
WHITE = (255, 255, 255)
VOLT = (255, 214, 60)
VOLT_DEEP = (255, 150, 30)
STORM = (100, 160, 255)
GREEN = (80, 210, 100)
GLASS = (190, 230, 255)
W = int(N * 0.022)  # outline width

FONT_PATH = sys.argv[2] if len(sys.argv) > 2 else ""


def font(size):
    for path in (FONT_PATH, "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"):
        if path and os.path.exists(path):
            return ImageFont.truetype(path, int(size * N))
    return ImageFont.load_default()


def P(x, y):
    return (x * N, y * N)


def rot(pts, cx, cy, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return [(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c) for x, y in pts]


def poly(d, pts, fill, outline=STROKE, width=W):
    px = [P(x, y) for x, y in pts]
    d.polygon(px, fill=fill)
    d.line(px + [px[0]], fill=outline, width=width, joint="curve")


def ellipse(d, cx, cy, rx, ry, fill, outline=STROKE, width=W):
    d.ellipse([P(cx - rx, cy - ry), P(cx + rx, cy + ry)], fill=fill, outline=outline, width=width)


def rrect(d, x0, y0, x1, y1, r, fill, outline=STROKE, width=W):
    d.rounded_rectangle([P(x0, y0), P(x1, y1)], radius=r * N, fill=fill, outline=outline, width=width)


def text(d, s, cx, cy, size, fill, stroke=W):
    f = font(size)
    box = d.textbbox((0, 0), s, font=f, stroke_width=stroke)
    w, h = box[2] - box[0], box[3] - box[1]
    d.text((cx * N - w / 2 - box[0], cy * N - h / 2 - box[1]), s, font=f, fill=fill,
           stroke_width=stroke, stroke_fill=STROKE)


def bolt_pts(cx, cy, s, deg=0):
    base = [(0.10, -0.50), (-0.24, 0.06), (-0.02, 0.06), (-0.12, 0.50), (0.26, -0.10), (0.03, -0.10), (0.17, -0.50)]
    pts = [(cx + x * s, cy + y * s) for x, y in base]
    return rot(pts, cx, cy, deg) if deg else pts


def bolt(d, cx, cy, s, fill=VOLT, deg=0):
    poly(d, bolt_pts(cx, cy, s, deg), fill)


def bottle(d, cx, cy, s, charge=VOLT):
    # glass body, charge inside, neck and cork (like Systems/Bottles)
    rrect(d, cx - 0.17 * s, cy - 0.12 * s, cx + 0.17 * s, cy + 0.38 * s, 0.08 * s, GLASS)
    rrect(d, cx - 0.12 * s, cy + 0.04 * s, cx + 0.12 * s, cy + 0.32 * s, 0.05 * s, charge, outline=charge, width=1)
    rrect(d, cx - 0.07 * s, cy - 0.30 * s, cx + 0.07 * s, cy - 0.10 * s, 0.03 * s, GLASS)
    rrect(d, cx - 0.09 * s, cy - 0.40 * s, cx + 0.09 * s, cy - 0.28 * s, 0.03 * s, (150, 105, 65))
    bolt(d, cx, cy + 0.18 * s, 0.22 * s)


def background(color):
    img = Image.new("RGB", (N, N))
    d = ImageDraw.Draw(img)
    for y in range(N):
        t = y / (N - 1)
        d.line([(0, y), (N, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(PANEL_TOP, PANEL_BOTTOM)))
    glow = Image.new("L", (N, N), 0)
    ImageDraw.Draw(glow).ellipse([P(0.18, 0.18), P(0.82, 0.82)], fill=150)
    glow = glow.filter(ImageFilter.GaussianBlur(N * 0.08))
    img = Image.composite(Image.new("RGB", (N, N), color), img, glow)
    return img, ImageDraw.Draw(img)


def double_volts(d, c):
    bolt(d, 0.44, 0.47, 0.62)
    text(d, "2X", 0.67, 0.68, 0.24, VOLT)


def remote_sell(d, c):
    bottle(d, 0.40, 0.52, 0.85)
    for i, r in enumerate((0.10, 0.17, 0.24)):
        box = [P(0.62 - r, 0.36 - r), P(0.62 + r, 0.36 + r)]
        d.arc(box, start=-80, end=-10, fill=STROKE, width=int(W * 2.6))
        d.arc(box, start=-80, end=-10, fill=GREEN, width=int(W * 1.2))
    text(d, "SELL", 0.5, 0.80, 0.13, GREEN)


def big_bottles(d, c):
    bottle(d, 0.5, 0.47, 0.88)
    text(d, "+50%", 0.5, 0.80, 0.14, c)


def lucky_charges(d, c):
    leaf = (90, 200, 90)
    for dx, dy in ((0, -0.12), (0.12, 0), (0, 0.12), (-0.12, 0)):
        ellipse(d, 0.5 + dx, 0.47 + dy, 0.115, 0.115, leaf)
    poly(d, [(0.50, 0.56), (0.54, 0.56), (0.62, 0.78), (0.58, 0.80)], (60, 150, 60))
    ellipse(d, 0.5, 0.47, 0.08, 0.08, leaf, outline=leaf)
    bolt(d, 0.5, 0.47, 0.20)


def lab_grant(d, c):
    teal = (80, 205, 190)
    flask = [(0.43, 0.20), (0.57, 0.20), (0.57, 0.38), (0.72, 0.70), (0.68, 0.76), (0.32, 0.76), (0.28, 0.70), (0.43, 0.38)]
    poly(d, flask, GLASS)
    poly(d, [(0.36, 0.56), (0.64, 0.56), (0.72, 0.70), (0.68, 0.76), (0.32, 0.76), (0.28, 0.70)], teal, outline=teal, width=1)
    d.line([P(x, y) for x, y in flask + [flask[0]]], fill=STROKE, width=W, joint="curve")
    rrect(d, 0.40, 0.16, 0.60, 0.22, 0.02, GLASS)
    for x, y, r in ((0.46, 0.48, 0.025), (0.54, 0.40, 0.018), (0.50, 0.30, 0.014)):
        ellipse(d, x, y, r, r, WHITE, width=int(W * 0.6))
    bolt(d, 0.5, 0.66, 0.16)


def vip(d, c):
    crown = [(0.24, 0.66), (0.20, 0.34), (0.36, 0.48), (0.50, 0.26), (0.64, 0.48), (0.80, 0.34), (0.76, 0.66)]
    poly(d, crown, VOLT)
    rrect(d, 0.24, 0.62, 0.76, 0.72, 0.02, VOLT_DEEP)
    for x, y in ((0.20, 0.32), (0.50, 0.24), (0.80, 0.32)):
        ellipse(d, x, y, 0.04, 0.04, VOLT)
    for x, col in ((0.37, (235, 75, 75)), (0.5, STORM), (0.63, GREEN)):
        ellipse(d, x, 0.67, 0.025, 0.025, col, width=int(W * 0.6))
    text(d, "VIP", 0.5, 0.82, 0.14, VOLT)


def bolt_colours(d, c):
    bolt(d, 0.36, 0.50, 0.50, (255, 90, 160), deg=-18)
    bolt(d, 0.64, 0.50, 0.50, (90, 230, 255), deg=18)
    bolt(d, 0.50, 0.46, 0.58, VOLT)


def jet_boots(d, c):
    for y, length in ((0.34, 0.18), (0.44, 0.24), (0.54, 0.16)):
        rrect(d, 0.36 - length, y - 0.022, 0.36, y + 0.022, 0.022, (255, 200, 80), width=int(W * 0.7))
    ellipse(d, 0.32, 0.68, 0.14, 0.065, VOLT_DEEP)
    ellipse(d, 0.36, 0.68, 0.07, 0.035, VOLT, outline=VOLT, width=1)
    boot = [(0.42, 0.26), (0.62, 0.26), (0.62, 0.52), (0.84, 0.60), (0.86, 0.74), (0.42, 0.74)]
    poly(d, boot, (255, 110, 70))
    rrect(d, 0.40, 0.70, 0.88, 0.78, 0.03, (60, 50, 70))
    d.line([P(0.44, 0.40), P(0.62, 0.40)], fill=STROKE, width=int(W * 0.6))


def pocket_charge(d, c):
    rrect(d, 0.30, 0.30, 0.70, 0.74, 0.06, c)
    rrect(d, 0.42, 0.22, 0.58, 0.31, 0.02, (200, 205, 220))
    bolt(d, 0.5, 0.52, 0.32)


def storm_jar(d, c):
    rrect(d, 0.26, 0.32, 0.74, 0.78, 0.10, GLASS)
    rrect(d, 0.31, 0.46, 0.69, 0.73, 0.07, (255, 230, 140), outline=(255, 230, 140), width=1)
    rrect(d, 0.30, 0.22, 0.70, 0.33, 0.03, (150, 105, 65))
    bolt(d, 0.5, 0.56, 0.36)


def thunder_crate(d, c):
    wood, dark = (196, 140, 80), (150, 100, 55)
    rrect(d, 0.22, 0.24, 0.78, 0.78, 0.03, wood)
    for y in (0.42, 0.60):
        d.line([P(0.24, y), P(0.76, y)], fill=dark, width=int(W * 0.7))
    rrect(d, 0.22, 0.24, 0.78, 0.78, 0.03, None)
    poly(d, [(0.26, 0.28), (0.34, 0.28), (0.74, 0.70), (0.74, 0.74), (0.66, 0.74), (0.26, 0.32)], dark, width=int(W * 0.6))
    bolt(d, 0.5, 0.51, 0.34)


def lightning_vault(d, c):
    ellipse(d, 0.5, 0.5, 0.30, 0.30, (130, 140, 165))
    ellipse(d, 0.5, 0.5, 0.22, 0.22, (95, 105, 130))
    for a in range(0, 360, 60):
        x, y = 0.5 + math.cos(math.radians(a)) * 0.26, 0.5 + math.sin(math.radians(a)) * 0.26
        ellipse(d, x, y, 0.025, 0.025, (200, 205, 220), width=int(W * 0.6))
    ellipse(d, 0.5, 0.5, 0.13, 0.13, c)
    bolt(d, 0.5, 0.5, 0.24)


def gift_badge(d):
    # a small present in the corner: this is a gift version of an item
    red = (235, 75, 75)
    rrect(d, 0.75, 0.79, 0.95, 0.96, 0.02, red, width=int(W * 0.8))
    rrect(d, 0.73, 0.74, 0.97, 0.81, 0.02, red, width=int(W * 0.8))
    d.rectangle([P(0.835, 0.75), P(0.865, 0.95)], fill=VOLT)
    ellipse(d, 0.82, 0.71, 0.035, 0.027, VOLT, width=int(W * 0.6))
    ellipse(d, 0.88, 0.71, 0.035, 0.027, VOLT, width=int(W * 0.6))


def timer_badge(d, label):
    # a stopwatch in the top corner: this is a timed boost
    ellipse(d, 0.76, 0.24, 0.13, 0.13, WHITE)
    rrect(d, 0.73, 0.07, 0.79, 0.12, 0.01, WHITE)
    text(d, label, 0.76, 0.25, 0.10, (34, 44, 66), stroke=0)


def boost(draw, label):
    def f(d, c):
        draw(d, c)
        timer_badge(d, label)
    return f


def bundle(d, c):
    bolt(d, 0.30, 0.52, 0.36)
    leaf = (90, 200, 90)
    for dx, dy in ((0, -0.06), (0.06, 0), (0, 0.06), (-0.06, 0)):
        ellipse(d, 0.70 + dx, 0.54 + dy, 0.06, 0.06, leaf)
    bottle(d, 0.50, 0.52, 0.55)
    timer_badge(d, "1H")


def server_storm(d, c):
    cloud = (200, 210, 235)
    for x, y, r in ((0.36, 0.40, 0.12), (0.52, 0.33, 0.16), (0.68, 0.41, 0.12)):
        ellipse(d, x, y, r, r, cloud)
    rrect(d, 0.26, 0.38, 0.78, 0.52, 0.07, cloud)
    for x, deg in ((0.34, -12), (0.52, 0), (0.70, 12)):
        bolt(d, x, 0.66, 0.30, deg=deg)
    text(d, "ALL", 0.5, 0.86, 0.12, VOLT)


DRAW = {
    "DoubleVolts": double_volts,
    "RemoteSell": remote_sell,
    "BigBottles": big_bottles,
    "LuckyCharges": lucky_charges,
    "LabGrant": lab_grant,
    "VIP": vip,
    "BoltColours": bolt_colours,
    "JetBoots": jet_boots,
    "PocketCharge": pocket_charge,
    "StormJar": storm_jar,
    "ThunderCrate": thunder_crate,
    "LightningVault": lightning_vault,
    "DoubleVoltsBoost": boost(double_volts, "30"),
    "LuckyBoost": boost(lucky_charges, "30"),
    "BigBottlesBoost": boost(big_bottles, "30"),
    "BoostBundle": bundle,
    "ServerStorm": server_storm,
}


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    items = load()
    for group in GROUP_KIND:
        for item in items[group]:
            color = tuple(item["color"])
            img, d = background(color)
            DRAW[item.get("pass", item["key"])](d, color)
            if "pass" in item:
                gift_badge(d)
            img.resize((OUT, OUT), Image.LANCZOS).save(os.path.join(out, f"{item['key']}.png"))
    print(f"icons written to {out}")


main()
