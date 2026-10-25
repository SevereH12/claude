"""Makes the game page art: the 512x512 game icon and three 1920x1080
thumbnails, in the game UI's look (the same colours, thick dark outlines and
Luckiest Guy text as tools/store/make_icons.py).

   python3 tools/store/make_store_art.py <outdir> [--font LuckiestGuy-Regular.ttf] [--maps DIR]

  icon.png         a glowing bottle full of lightning on the storm-navy
                   background, with the STORM BOTTLER wordmark
  thumb_1_storm.png  Barometer Bay in a storm (drawn with tools/render_view.py)
  thumb_2_worlds.png the three worlds side by side
  thumb_3_loop.png   "catch, sell, upgrade" with the store icons

The map views need the map files from tools/harness/buildmap.luau; if
--maps isn't given they're built into a temporary folder first (needs lune).
Without --font the font is downloaded from Google Fonts' GitHub (falls back
to DejaVu Sans Bold if that fails).

Uploading: Open Cloud can't set the game's own icon or thumbnails (its
thumbnail calls only take translations, and refuse the source language),
so they go up by hand on the Creator Dashboard: see README.md, "Store page
art"."""
import argparse
import importlib.util
import math
import os
import random
import subprocess
import tempfile
import urllib.request

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
FONT_URL = "https://raw.githubusercontent.com/google/fonts/main/apache/luckiestguy/LuckiestGuy-Regular.ttf"
FALLBACK_FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

# UI.COLORS (as in make_icons.py)
PANEL_TOP = (44, 52, 92)
PANEL_BOTTOM = (20, 23, 44)
NAVY_DEEP = (10, 12, 26)
STROKE = (6, 8, 18)
WHITE = (255, 255, 255)
VOLT = (255, 214, 60)
VOLT_DEEP = (255, 150, 30)
STORM = (100, 160, 255)
GREEN = (80, 210, 100)
GLASS = (190, 230, 255)
CORK = (150, 105, 65)

FONT_PATH = FALLBACK_FONT


def font(px):
    return ImageFont.truetype(FONT_PATH, int(px))


def find_font(path):
    """The Luckiest Guy font file: the one given, a cached copy, or a
    download."""
    if path and os.path.exists(path):
        return path
    cache = os.path.join(tempfile.gettempdir(), "LuckiestGuy-Regular.ttf")
    if not os.path.exists(cache):
        try:
            urllib.request.urlretrieve(FONT_URL, cache)
        except Exception as err:  # offline: still make the art
            print(f"couldn't download Luckiest Guy ({err}); using DejaVu Sans Bold")
            return FALLBACK_FONT
    return cache


# Drawing helpers ---------------------------------------------------------------


def gradient(w, h, top, bottom):
    t = np.linspace(0, 1, h)[:, None, None]
    arr = np.array(top) * (1 - t) + np.array(bottom) * t
    return Image.fromarray(np.broadcast_to(arr, (h, w, 3)).astype(np.uint8))


def glow(img, box, color, blur, strength=255):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).ellipse(box, fill=strength)
    mask = mask.filter(ImageFilter.GaussianBlur(blur))
    return Image.composite(Image.new("RGB", img.size, color), img, mask)


def text(d, s, cx, cy, size, fill, stroke=None, anchor="mm"):
    f = font(size)
    sw = stroke if stroke is not None else max(2, int(size * 0.09))
    d.text((cx, cy), s, font=f, fill=fill, stroke_width=sw, stroke_fill=STROKE, anchor=anchor)


def bolt_shape(cx, cy, s):
    base = [(0.10, -0.50), (-0.24, 0.06), (-0.02, 0.06), (-0.12, 0.50), (0.26, -0.10), (0.03, -0.10), (0.17, -0.50)]
    return [(cx + x * s, cy + y * s) for x, y in base]


def poly(d, pts, fill, width):
    d.polygon(pts, fill=fill)
    d.line(pts + [pts[0]], fill=STROKE, width=width, joint="curve")


def jagged(rng, start, end, rough, depth=6):
    """A lightning path from start to end (midpoint displacement)."""
    pts = [start, end]
    for _ in range(depth):
        out = [pts[0]]
        for a, b in zip(pts, pts[1:]):
            mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
            length = math.dist(a, b)
            nx, ny = -(b[1] - a[1]) / (length or 1), (b[0] - a[0]) / (length or 1)
            off = rng.uniform(-rough, rough) * length
            out += [(mx + nx * off, my + ny * off), b]
        pts = out
    return pts


def lightning(img, rng, start, end, width, branches=3, rough=0.18):
    """Draws a glowing lightning strike (with a few forks) onto img."""
    # the see-through pixels carry the glow colour, so the blur has no dark rim
    layer = Image.new("RGBA", img.size, (170, 200, 255, 0))
    d = ImageDraw.Draw(layer)
    paths = [jagged(rng, start, end, rough)]
    for _ in range(branches):
        main = paths[0]
        i = rng.randrange(len(main) // 5, len(main) * 3 // 4)
        a = main[i]
        angle = math.atan2(end[1] - start[1], end[0] - start[0]) + rng.choice((-1, 1)) * rng.uniform(0.4, 0.9)
        length = math.dist(start, end) * rng.uniform(0.2, 0.4)
        paths.append(jagged(rng, a, (a[0] + math.cos(angle) * length, a[1] + math.sin(angle) * length), 0.22, 5))
    for n, path in enumerate(paths):
        w = width if n == 0 else max(2, width // 2)
        d.line(path, fill=(170, 200, 255, 255), width=w * 5, joint="curve")
    halo = layer.filter(ImageFilter.GaussianBlur(width * 4))
    core = Image.new("RGBA", img.size, (0, 0, 0, 0))
    dc = ImageDraw.Draw(core)
    for n, path in enumerate(paths):
        w = width if n == 0 else max(2, width // 2)
        dc.line(path, fill=(255, 250, 220, 255), width=w, joint="curve")
    out = img.convert("RGBA")
    out.alpha_composite(halo)
    out.alpha_composite(halo)
    out.alpha_composite(core)
    return out.convert("RGB")


def bottle(img, cx, cy, s, glow_it=True):
    """The game's bottle (glass, cork, a charge of lightning inside),
    centred at (cx, cy), s pixels tall-ish."""
    if glow_it:
        img = glow(img, [cx - s * 0.55, cy - s * 0.5, cx + s * 0.55, cy + s * 0.6], VOLT_DEEP, s * 0.12, 170)
        img = glow(img, [cx - s * 0.3, cy - s * 0.15, cx + s * 0.3, cy + s * 0.45], VOLT, s * 0.08, 200)
    d = ImageDraw.Draw(img)
    w = max(3, int(s * 0.03))
    d.rounded_rectangle([cx - 0.27 * s, cy - 0.10 * s, cx + 0.27 * s, cy + 0.46 * s], radius=0.11 * s,
                        fill=GLASS, outline=STROKE, width=w)
    d.rounded_rectangle([cx - 0.20 * s, cy + 0.06 * s, cx + 0.20 * s, cy + 0.39 * s], radius=0.07 * s,
                        fill=(255, 236, 150))
    d.rounded_rectangle([cx - 0.11 * s, cy - 0.30 * s, cx + 0.11 * s, cy - 0.08 * s], radius=0.04 * s,
                        fill=GLASS, outline=STROKE, width=w)
    d.rounded_rectangle([cx - 0.14 * s, cy - 0.42 * s, cx + 0.14 * s, cy - 0.27 * s], radius=0.04 * s,
                        fill=CORK, outline=STROKE, width=w)
    # glass shine
    d.rounded_rectangle([cx - 0.22 * s, cy - 0.04 * s, cx - 0.16 * s, cy + 0.20 * s], radius=0.03 * s,
                        fill=(235, 248, 255))
    poly(d, bolt_shape(cx, cy + 0.22 * s, 0.40 * s), VOLT, w)
    return img


def sparks(img, rng, cx, cy, r, count, size):
    d = ImageDraw.Draw(img)
    for _ in range(count):
        a = rng.uniform(0, math.tau)
        dist = r * rng.uniform(0.75, 1.1)
        x, y = cx + math.cos(a) * dist, cy + math.sin(a) * dist
        k = size * rng.uniform(0.6, 1.0)
        poly(d, bolt_shape(x, y, k), VOLT, max(2, int(k * 0.08)))
    return img


# Map views ----------------------------------------------------------------------

def load_render_view():
    spec = importlib.util.spec_from_file_location("render_view", os.path.join(ROOT, "tools", "render_view.py"))
    rv = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(rv)
    return rv


def ensure_maps(maps):
    if maps and os.path.exists(os.path.join(maps, "map.json")):
        return maps
    maps = maps or tempfile.mkdtemp(prefix="stormbottler_maps_")
    print("building the map files with lune ...")
    subprocess.run(["lune", "run", "tools/harness/buildmap.luau", os.path.join(maps, "map.json"), "Game"],
                   cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    return maps


def view(rv, maps, name, eye, at, fov, size, stormy):
    import json
    with open(os.path.join(maps, name)) as f:
        world = json.load(f)
    if stormy:  # a storm sky: dark navy at the top, grey-blue haze low down
        rv.SKY_TOP = np.array([0.07, 0.08, 0.17])
        rv.SKY_LOW = np.array([0.33, 0.37, 0.50])
    else:
        rv.SKY_TOP = np.array([0.22, 0.30, 0.55])
        rv.SKY_LOW = np.array([0.62, 0.68, 0.82])
    img, _ = rv.render(world, eye, at, fov, size, label=None)
    return img.convert("RGB")


def storm_grade(img, amount=0.78):
    """Darkens and cools a render so it reads as stormy weather."""
    arr = np.asarray(img).astype(np.float32) / 255
    arr = arr * amount
    arr[..., 2] = np.minimum(1, arr[..., 2] * 1.12 + 0.03)
    return Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8))


def clouds(img, rng, top_frac=0.32):
    w, h = img.size
    layer = Image.new("L", img.size, 0)
    d = ImageDraw.Draw(layer)
    for _ in range(40):
        x = rng.uniform(-0.1, 1.1) * w
        y = rng.uniform(-0.1, top_frac) * h
        r = rng.uniform(0.06, 0.16) * w
        d.ellipse([x - r, y - r * 0.5, x + r, y + r * 0.5], fill=rng.randint(120, 220))
    layer = layer.filter(ImageFilter.GaussianBlur(w * 0.02))
    return Image.composite(Image.new("RGB", img.size, (24, 27, 46)), img, layer)


def vignette(img, strength=0.55):
    w, h = img.size
    y, x = np.ogrid[0:h, 0:w]
    d = np.sqrt(((x - w / 2) / (w / 2)) ** 2 + ((y - h / 2) / (h / 2)) ** 2)
    k = 1 - strength * np.clip(d - 0.55, 0, 1)
    arr = np.asarray(img).astype(np.float32) * k[..., None]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


# The pieces ----------------------------------------------------------------------


def make_icon(out):
    S = 2048  # draw big, then shrink, for smooth edges
    rng = random.Random(7)
    img = gradient(S, S, PANEL_TOP, NAVY_DEEP)
    img = glow(img, [S * 0.1, S * 0.0, S * 0.9, S * 0.8], STORM, S * 0.1, 90)
    img = lightning(img, rng, (S * 0.06, -S * 0.02), (S * 0.24, S * 0.55), 10, 2)
    img = lightning(img, rng, (S * 0.96, -S * 0.02), (S * 0.78, S * 0.50), 10, 2)
    img = bottle(img, S * 0.5, S * 0.40, S * 0.62)
    img = sparks(img, rng, S * 0.5, S * 0.42, S * 0.36, 5, S * 0.08)
    d = ImageDraw.Draw(img)
    text(d, "STORM", S * 0.5, S * 0.775, S * 0.165, VOLT, stroke=int(S * 0.018))
    text(d, "BOTTLER", S * 0.5, S * 0.915, S * 0.145, WHITE, stroke=int(S * 0.018))
    img.resize((512, 512), Image.LANCZOS).save(os.path.join(out, "icon.png"))


def title_block(img, title, sub, x, y, size):
    d = ImageDraw.Draw(img)
    text(d, title, x, y, size, VOLT, stroke=int(size * 0.1), anchor="lm")
    if sub:
        text(d, sub, x + size * 0.04, y + size * 0.95, size * 0.42, WHITE, stroke=int(size * 0.05), anchor="lm")


def make_thumb_storm(out, rv, maps):
    rng = random.Random(11)
    img = view(rv, maps, "map.json", (150, 110, 230), (-10, 15, -40), 60, (1920, 1080), True)
    img = storm_grade(img)
    img = clouds(img, rng)
    img = lightning(img, rng, (1250, -10), (1170, 410), 7)
    img = lightning(img, rng, (1650, -10), (1760, 330), 6, 2)
    img = lightning(img, rng, (300, -10), (420, 300), 5, 2)
    img = vignette(img)
    # a small bottle mark beside the title
    img = bottle(img, 150, 150, 210)
    title_block(img, "STORM BOTTLER", "CATCH LIGHTNING IN A BOTTLE!", 270, 125, 130)
    img.save(os.path.join(out, "thumb_1_storm.png"))


WORLDS = (
    ("map.json", "BAROMETER BAY", (95, 70, 170), (0, 18, -10), 62),
    ("map_Voltcliff.json", "VOLTCLIFF WORKS", (4880, 110, -190), (5060, 20, 60), 52),
    ("map_Stormspire.json", "STORMSPIRE ISLES", (10180, 120, 200), (10000, 20, -40), 55),
)


def make_thumb_worlds(out, rv, maps):
    rng = random.Random(23)
    W, H = 1920, 1080
    img = Image.new("RGB", (W, H), NAVY_DEEP)
    panel_w = W // 3
    for i, (name, label, eye, at, fov) in enumerate(WORLDS):
        # render wider than the panel so the slanted edges have picture
        shot = view(rv, maps, name, eye, at, fov, (panel_w + 160, H), False)
        mask = Image.new("L", (W, H), 0)
        x0 = i * panel_w
        slant = 80
        # each panel's edges lean like the seams; the outer edges go off-screen
        left = x0 if i > 0 else -200
        right = x0 + panel_w if i < 2 else W + 200
        ImageDraw.Draw(mask).polygon([(left + slant, 0), (right + slant, 0), (right - slant, H), (left - slant, H)],
                                     fill=255)
        canvas = Image.new("RGB", (W, H))
        canvas.paste(shot, (x0 - 80, 0))
        img = Image.composite(canvas, img, mask)
    # lightning seams between the panels
    for i in (1, 2):
        x = i * panel_w
        img = lightning(img, rng, (x + 80, -10), (x - 80, H + 10), 6, 1, 0.04)
    img = vignette(img, 0.4)
    d = ImageDraw.Draw(img)
    # top title band
    band = Image.new("L", (W, H), 0)
    ImageDraw.Draw(band).rectangle([0, 0, W, 190], fill=150)
    band = band.filter(ImageFilter.GaussianBlur(40))
    img = Image.composite(Image.new("RGB", (W, H), NAVY_DEEP), img, band)
    d = ImageDraw.Draw(img)
    text(d, "3 STORMY WORLDS", W / 2, 95, 120, VOLT, stroke=12)
    for i, (_, label, *_rest) in enumerate(WORLDS):
        cx = i * panel_w + panel_w / 2
        d.rounded_rectangle([cx - 270, H - 150, cx + 270, H - 60], radius=24, fill=PANEL_BOTTOM, outline=STROKE,
                            width=8)
        text(d, label, cx, H - 103, 58, WHITE, stroke=6)
    img.save(os.path.join(out, "thumb_2_worlds.png"))


STEPS = (
    ("CATCH", "BoltColours", "RUN INTO THE STORM"),
    ("SELL", "RemoteSell", "CASH IN FOR VOLTS"),
    ("UPGRADE", "BigBottles", "BIGGER BOTTLES!"),
)


def make_thumb_loop(out, rv, maps):
    rng = random.Random(5)
    W, H = 1920, 1080
    back = view(rv, maps, "map.json", (-60, 60, 140), (60, 20, -60), 65, (W, H), True)
    back = storm_grade(back, 0.55).filter(ImageFilter.GaussianBlur(6))
    img = Image.blend(back, gradient(W, H, PANEL_TOP, NAVY_DEEP), 0.45)
    img = lightning(img, rng, (120, -10), (260, 380), 5, 2)
    img = lightning(img, rng, (1800, -10), (1660, 360), 5, 2)
    d = ImageDraw.Draw(img)
    text(d, "CATCH  •  SELL  •  UPGRADE", W / 2, 120, 104, VOLT, stroke=11)
    card, gap = 470, 120
    x0 = (W - (3 * card + 2 * gap)) / 2
    top = 250
    for i, (label, icon, sub) in enumerate(STEPS):
        x = x0 + i * (card + gap)
        cx = x + card / 2
        img = glow(img, [x - 40, top - 40, x + card + 40, top + card + 40], STORM, 50, 110)
        d = ImageDraw.Draw(img)
        d.rounded_rectangle([x - 10, top - 10, x + card + 10, top + card + 10], radius=48, fill=STROKE)
        pic = Image.open(os.path.join(HERE, "icons", f"{icon}.png")).convert("RGB").resize((card, card), Image.LANCZOS)
        mask = Image.new("L", (card, card), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, card - 1, card - 1], radius=40, fill=255)
        img.paste(pic, (int(x), top), mask)
        d = ImageDraw.Draw(img)
        text(d, label, cx, top + card + 95, 96, WHITE, stroke=10)
        text(d, sub, cx, top + card + 185, 48, GLASS, stroke=6)
        if i < 2:  # arrow to the next step
            ax = x + card + gap / 2
            ay = top + card / 2
            poly(d, [(ax - 42, ay - 26), (ax + 6, ay - 26), (ax + 6, ay - 56), (ax + 56, ay), (ax + 6, ay + 56),
                     (ax + 6, ay + 26), (ax - 42, ay + 26)], VOLT, 8)
    img.save(os.path.join(out, "thumb_3_loop.png"))


def main():
    global FONT_PATH
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("out")
    parser.add_argument("--font")
    parser.add_argument("--maps")
    args = parser.parse_args()
    FONT_PATH = find_font(args.font)
    os.makedirs(args.out, exist_ok=True)
    make_icon(args.out)
    rv = load_render_view()
    maps = ensure_maps(args.maps)
    make_thumb_storm(args.out, rv, maps)
    make_thumb_worlds(args.out, rv, maps)
    make_thumb_loop(args.out, rv, maps)
    print(f"store art written to {args.out}")


main()
