#!/usr/bin/env python3
"""Renders the Walkie app icon into the AppIcon asset catalog.

    python3 scripts/make-app-icon.py      (needs Pillow: pip install Pillow)

Renders one opaque 1024x1024 master and writes every classic iPhone, iPad and App Store
slot from it, plus Contents.json. App Store Connect rejects icons with an alpha channel.
"""
import json
import math
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
AMBER_DIM = (120, 88, 26)
BG_TOP = (24, 24, 26)
BG_BOTTOM = (6, 6, 7)


def px(v):
    return int(round(v * S))


def background():
    img = Image.new("RGB", (S, S))
    draw = ImageDraw.Draw(img)
    for y in range(S):
        t = y / (S - 1)
        draw.line([(0, y), (S, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)))
    return img


def polar(cx, cy, r, deg):
    a = math.radians(deg)
    return cx + r * math.cos(a), cy - r * math.sin(a)


def render():
    img = background()
    cx, cy = px(0.5), px(0.56)

    glow = Image.new("RGB", (S, S), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    r = px(0.36)
    gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(48, 34, 8))
    glow = glow.filter(ImageFilter.GaussianBlur(px(0.08)))
    img = ImageChops.add(img, glow)

    draw = ImageDraw.Draw(img)

    # Tuning scale: ticks along the upper arc, every third one long.
    r_outer = px(0.34)
    start, end, count = 200, -20, 34
    for i in range(count + 1):
        deg = start + (end - start) * i / count
        major = i % 3 == 0
        r_in = r_outer - (px(0.07) if major else px(0.04))
        w = px(0.016) if major else px(0.009)
        color = AMBER if major else AMBER_DIM
        draw.line([polar(cx, cy, r_in, deg), polar(cx, cy, r_outer, deg)], fill=color, width=w)

    # Dial ring.
    rr = px(0.23)
    draw.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=AMBER, width=px(0.028))

    # Needle, tuned slightly right of centre.
    needle_deg = 62
    tip = polar(cx, cy, px(0.255), needle_deg)
    draw.line([(cx, cy), tip], fill=AMBER, width=px(0.026))

    # Centre knob.
    kr = px(0.075)
    draw.ellipse([cx - kr, cy - kr, cx + kr, cy + kr], fill=AMBER)
    ir = px(0.03)
    draw.ellipse([cx - ir, cy - ir, cx + ir, cy + ir], fill=BG_BOTTOM)

    # Talk indicator under the dial.
    lw, lh, ly = px(0.2), px(0.03), px(0.86)
    draw.rounded_rectangle([cx - lw / 2, ly - lh / 2, cx + lw / 2, ly + lh / 2],
                           radius=lh / 2, fill=AMBER_DIM)

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
