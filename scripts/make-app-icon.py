#!/usr/bin/env python3
"""Renders the Walkie app icon into the AppIcon asset catalog.

    python3 scripts/make-app-icon.py      (needs Pillow: pip install Pillow)

Renders one opaque 1024x1024 master and writes every classic iPhone, iPad and App Store
slot from it, plus Contents.json. App Store Connect rejects icons with an alpha channel.
"""
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "Walkie/Resources/Assets.xcassets/AppIcon.appiconset"

# (idiom, size in points, scale)
SLOTS = [
    ("iphone", "20", 2), ("iphone", "20", 3),
    ("iphone", "29", 2), ("iphone", "29", 3),
    ("iphone", "40", 2), ("iphone", "40", 3),
    ("iphone", "60", 2), ("iphone", "60", 3),
    ("ipad", "20", 1), ("ipad", "20", 2),
    ("ipad", "29", 1), ("ipad", "29", 2),
    ("ipad", "40", 1), ("ipad", "40", 2),
    ("ipad", "76", 1), ("ipad", "76", 2),
    ("ipad", "83.5", 2),
    ("ios-marketing", "1024", 1),
]

SIZE = 1024
SS = 4  # supersampling factor for smooth edges
S = SIZE * SS

AMBER = (250, 190, 62)
DOT = (226, 160, 66)
HALO = (90, 58, 14)
GREY = (72, 72, 74)
BLACK = (0, 0, 0)

# Layout follows the in-app tuner: one tall amber tick at the tuned frequency, a glowing
# dot above it, and two shorter grey ticks either side. Units are fractions of the icon.
CENTER_X = 0.5
TICK_BOTTOM = 0.735
CENTER_TICK_TOP = 0.39
SIDE_TICK_TOP = 0.535
SIDE_SPACING = 0.155
CENTER_TICK_W = 0.03
SIDE_TICK_W = 0.02
DOT_Y = 0.285
DOT_R = 0.03
HALO_R = 0.11


def px(v):
    return v * S


def tick(draw, x, top, width, color):
    w = px(width)
    draw.rounded_rectangle([px(x) - w / 2, px(top), px(x) + w / 2, px(TICK_BOTTOM)],
                           radius=w / 2, fill=color)


def render():
    img = Image.new("RGB", (S, S), BLACK)

    halo = Image.new("RGB", (S, S), BLACK)
    hd = ImageDraw.Draw(halo)
    cx, cy, r = px(CENTER_X), px(DOT_Y), px(HALO_R)
    hd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=HALO)
    halo = halo.filter(ImageFilter.GaussianBlur(px(0.05)))
    img = ImageChops.add(img, halo)

    draw = ImageDraw.Draw(img)
    for i in (-2, -1, 1, 2):
        tick(draw, CENTER_X + i * SIDE_SPACING, SIDE_TICK_TOP, SIDE_TICK_W, GREY)
    tick(draw, CENTER_X, CENTER_TICK_TOP, CENTER_TICK_W, AMBER)

    r = px(DOT_R)
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=DOT)

    return img.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    master = render().convert("RGB")
    for old in OUT_DIR.glob("*.png"):
        old.unlink()

    images = []
    for idiom, points, scale in SLOTS:
        pixels = round(float(points) * scale)
        name = f"AppIcon-{idiom}-{points}@{scale}x.png"
        icon = master if pixels == SIZE else master.resize((pixels, pixels), Image.LANCZOS)
        icon.save(OUT_DIR / name, "PNG", optimize=True)
        images.append({"filename": name, "idiom": idiom, "scale": f"{scale}x",
                       "size": f"{points}x{points}"})
        print(f"{name}: {pixels}x{pixels}")

    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    (OUT_DIR / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


if __name__ == "__main__":
    main()
