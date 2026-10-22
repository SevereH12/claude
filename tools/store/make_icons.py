"""Draws a simple 512x512 icon for every item in store_items.json.
   python3 tools/store/make_icons.py <outdir>
Placeholder art: replace on the Creator Dashboard whenever you like."""
import json, math, os, sys
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
SIZE = 512
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def font(size):
    try:
        return ImageFont.truetype(FONT, size)
    except OSError:
        return ImageFont.load_default()


def icon(item, path):
    r, g, b = item["color"]
    img = Image.new("RGB", (SIZE, SIZE), (22, 26, 44))
    d = ImageDraw.Draw(img)
    # glowing disc in the item colour
    for i in range(60, 0, -1):
        t = i / 60
        col = (int(22 + (r - 22) * (1 - t) * 0.9), int(26 + (g - 26) * (1 - t) * 0.9), int(44 + (b - 44) * (1 - t) * 0.9))
        rad = 60 + t * 180
        d.ellipse([SIZE / 2 - rad, SIZE / 2 - rad, SIZE / 2 + rad, SIZE / 2 + rad], fill=col)
    # lightning bolt behind the text
    bolt = [(290, 70), (180, 270), (250, 270), (210, 440), (340, 220), (268, 220), (320, 70)]
    d.polygon(bolt, fill=(255, 255, 255))
    d.polygon(bolt, outline=(30, 30, 50), width=6)
    text = item["symbol"]
    size = 170 if len(text) <= 2 else 130 if len(text) <= 3 else 105
    f = font(size)
    box = d.textbbox((0, 0), text, font=f, stroke_width=10)
    w, h = box[2] - box[0], box[3] - box[1]
    d.text(((SIZE - w) / 2 - box[0], (SIZE - h) / 2 - box[1] + 40), text, font=f, fill=(r, g, b), stroke_width=10, stroke_fill=(20, 20, 35))
    d.rounded_rectangle([8, 8, SIZE - 8, SIZE - 8], radius=60, outline=(r, g, b), width=12)
    img.save(path)


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    items = json.load(open(os.path.join(HERE, "store_items.json")))
    for group in ("passes", "products"):
        for item in items[group]:
            icon(item, os.path.join(out, f"{item['key']}.png"))
    print(f"icons written to {out}")


main()
