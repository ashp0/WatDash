#!/usr/bin/env python3
"""Draws the WatDash app icon (a timetable card on Waterloo gold) at every
size macOS asks for. Run with any Python that has Pillow:

    ~/.venvs/uw-classes/bin/python Tools/make_icon.py
"""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "WatDash/Assets.xcassets/AppIcon.appiconset"
S = 1024


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def master() -> Image.Image:
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # Squircle-ish tile inset like Apple's grid (824 on 1024).
    inset = 100
    tile = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    grad = Image.new("RGBA", (S, S))
    top, bottom = (253, 190, 64), (226, 128, 10)
    for y in range(S):
        ImageDraw.Draw(grad).line([(0, y), (S, y)], fill=lerp(top, bottom, y / S) + (255,))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([inset, inset, S - inset, S - inset], radius=185, fill=255)
    tile.paste(grad, (0, 0), mask)

    # Soft shadow under the tile.
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([inset, inset + 14, S - inset, S - inset + 14], radius=185, fill=(0, 0, 0, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    img.alpha_composite(shadow)
    img.alpha_composite(tile)

    d = ImageDraw.Draw(img)
    # Card.
    cx0, cy0, cx1, cy1 = 250, 262, 774, 772
    card_shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(card_shadow).rounded_rectangle([cx0, cy0 + 16, cx1, cy1 + 16], radius=60, fill=(120, 60, 0, 110))
    img.alpha_composite(card_shadow.filter(ImageFilter.GaussianBlur(16)))
    d.rounded_rectangle([cx0, cy0, cx1, cy1], radius=60, fill=(255, 255, 255, 255))
    # Header band.
    d.rounded_rectangle([cx0, cy0, cx1, cy0 + 120], radius=60, fill=(38, 38, 42, 255))
    d.rectangle([cx0, cy0 + 60, cx1, cy0 + 120], fill=(38, 38, 42, 255))
    # Binder rings.
    for x in (370, 654):
        d.rounded_rectangle([x - 18, cy0 - 40, x + 18, cy0 + 40], radius=18, fill=(250, 250, 250, 255))
    # Timetable blocks in course colours.
    blocks = [
        ((66, 120, 245), 408, 402, 580),
        ((219, 61, 143), 486, 470, 712),
        ((41, 168, 133), 604, 312, 530),
        ((140, 92, 237), 682, 500, 712),
    ]
    for color, y, x0, x1 in blocks:
        d.rounded_rectangle([x0, y, x1, y + 58], radius=18, fill=color + (255,))
    # Now line.
    d.rounded_rectangle([cx0 + 24, 571, cx1 - 24, 581], radius=5, fill=(229, 72, 64, 255))
    d.ellipse([cx0 + 10, 562, cx0 + 38, 590], fill=(229, 72, 64, 255))
    return img


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    art = master()
    images = []
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = points * scale
            name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
            art.resize((px, px), Image.LANCZOS).save(OUT / name)
            images.append({"idiom": "mac", "scale": f"{scale}x", "size": f"{points}x{points}", "filename": name})
    (OUT / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2))
    art.save(ROOT / "Tools/icon-1024.png")
    print("icon written")


main()
