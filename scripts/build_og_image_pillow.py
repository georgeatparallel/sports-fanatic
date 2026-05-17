#!/usr/bin/env python3
"""Pillow-only fallback for rendering the default Open Graph image.

Use this when no SVG rasterizer (cairosvg, rsvg-convert, magick, convert) is
available on the system. Pillow is in the python_bridge service environment
and is widely installed. Output: priv/static/images/og-default.png at 1200x630.

The image is painted procedurally to match the SVG source:
- Vertical gradient from blue-600 (#2563eb) to indigo-700 (#4338ca)
- Soft radial glow accent
- Decorative low-opacity baseball glyph (right side)
- "Sports Fan Agent" in white extrabold (left)
- Tagline "AI-Powered MLB Intelligence" in light blue
- Accent line under tagline
- Feature strip and domain hint at the bottom
"""
from __future__ import annotations

import pathlib
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
DST = ROOT / "priv" / "static" / "images" / "og-default.png"

WIDTH = 1200
HEIGHT = 630

# Brand palette (Tailwind blue-600 → indigo-700)
COLOR_TOP = (37, 99, 235)  # #2563eb (blue-600)
COLOR_MID = (55, 48, 163)  # #3730a3 (indigo-800)
COLOR_BOT = (67, 56, 202)  # #4338ca (indigo-700)
COLOR_WHITE = (255, 255, 255)
COLOR_BLUE_200 = (191, 219, 254)  # #bfdbfe
COLOR_BLUE_100 = (219, 234, 254)  # #dbeafe
COLOR_BLUE_300 = (147, 197, 253)  # #93c5fd
COLOR_BLUE_400 = (96, 165, 250)  # #60a5fa
COLOR_BASEBALL_STITCH = (220, 38, 38)  # #dc2626


def _interp(c1: tuple[int, int, int], c2: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    """Linear interpolation between two RGB colors."""
    return tuple(int(round(c1[i] + (c2[i] - c1[i]) * t)) for i in range(3))


def _paint_gradient(img: Image.Image) -> None:
    """Diagonal-ish gradient: top-left blue-600 → mid indigo → bottom-right indigo-700.

    Implemented as a vertical gradient with the midpoint at ~60% for visual depth.
    """
    pixels = img.load()
    for y in range(HEIGHT):
        t = y / (HEIGHT - 1)
        if t < 0.6:
            color = _interp(COLOR_TOP, COLOR_MID, t / 0.6)
        else:
            color = _interp(COLOR_MID, COLOR_BOT, (t - 0.6) / 0.4)
        for x in range(WIDTH):
            pixels[x, y] = color


def _paint_glow(img: Image.Image) -> None:
    """Soft radial highlight near the right side."""
    glow = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    # Concentric ellipses with decreasing alpha
    cx, cy = int(WIDTH * 0.85), int(HEIGHT * 0.5)
    max_r = 360
    for r in range(max_r, 0, -20):
        # alpha decreases as radius grows
        alpha = int(40 * (1 - r / max_r))
        gd.ellipse(
            (cx - r, cy - int(r * 0.85), cx + r, cy + int(r * 0.85)),
            fill=(96, 165, 250, alpha),
        )
    glow = glow.filter(ImageFilter.GaussianBlur(20))
    img.alpha_composite(glow)


def _paint_baseball(img: Image.Image) -> None:
    """Low-opacity decorative baseball glyph at the right side."""
    layer = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = 900, 330
    r = 220
    # White ball at ~10% opacity
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(255, 255, 255, 26))
    # Stitch arcs — Pillow's arc takes a bbox
    stitch_color = (*COLOR_BASEBALL_STITCH, 80)
    # Top stitch
    d.arc(
        (cx - 180, cy - 200, cx + 180, cy - 20),
        start=20,
        end=160,
        fill=stitch_color,
        width=6,
    )
    # Bottom stitch
    d.arc(
        (cx - 180, cy + 20, cx + 180, cy + 200),
        start=200,
        end=340,
        fill=stitch_color,
        width=6,
    )
    # Stitch ticks (small perpendicular lines along the arcs)
    for x_offset in (-150, -100, -50, 0, 50, 100, 150):
        # top
        d.line(
            (cx + x_offset, cy - 110, cx + x_offset, cy - 85),
            fill=stitch_color,
            width=3,
        )
        # bottom
        d.line(
            (cx + x_offset, cy + 85, cx + x_offset, cy + 110),
            fill=stitch_color,
            width=3,
        )
    img.alpha_composite(layer)


def _load_font(candidates: list[tuple[str, int]]) -> ImageFont.FreeTypeFont:
    """Try each (path, size) tuple in order; return the first that loads."""
    last_err: Exception | None = None
    for path, size in candidates:
        try:
            return ImageFont.truetype(path, size)
        except (OSError, IOError) as exc:
            last_err = exc
    if last_err is not None:
        sys.stderr.write(
            f"warning: no system font available, falling back to default ({last_err})\n"
        )
    return ImageFont.load_default()


def _bold_font(size: int) -> ImageFont.FreeTypeFont:
    return _load_font(
        [
            ("/System/Library/Fonts/Supplemental/Arial Black.ttf", size),
            ("/System/Library/Fonts/Supplemental/Arial Bold.ttf", size),
            ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", size),
            ("/Library/Fonts/Arial Bold.ttf", size),
        ]
    )


def _medium_font(size: int) -> ImageFont.FreeTypeFont:
    return _load_font(
        [
            ("/System/Library/Fonts/Supplemental/Arial.ttf", size),
            ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", size),
            ("/Library/Fonts/Arial.ttf", size),
        ]
    )


def _paint_text(img: Image.Image) -> None:
    d = ImageDraw.Draw(img)

    # Brand title
    title_font = _bold_font(92)
    d.text((80, 200), "Sports Fan Agent", font=title_font, fill=COLOR_WHITE)

    # Tagline
    tagline_font = _medium_font(38)
    d.text((80, 310), "AI-Powered MLB Intelligence", font=tagline_font, fill=COLOR_BLUE_200)

    # Accent line
    d.rounded_rectangle(
        (80, 372, 320, 380), radius=4, fill=COLOR_BLUE_400
    )

    # Feature strip near bottom
    strip_font = _medium_font(26)
    d.text(
        (80, 528),
        "Scouting  ·  Predictions  ·  Game Day  ·  News  ·  Chat",
        font=strip_font,
        fill=COLOR_BLUE_100,
    )

    # Domain hint
    domain_font = _medium_font(20)
    d.text(
        (80, 570),
        "sports-fan-agent.com",
        font=domain_font,
        fill=COLOR_BLUE_300,
    )


def build() -> int:
    img = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    _paint_gradient(img)
    _paint_glow(img)
    _paint_baseball(img)
    _paint_text(img)

    # Convert to RGB before save (PNG is fine with RGBA but RGB is smaller and
    # matches Open Graph expectations).
    final = img.convert("RGB")
    DST.parent.mkdir(parents=True, exist_ok=True)
    final.save(DST, "PNG", optimize=True, compress_level=9)

    size = DST.stat().st_size
    print(f"Wrote {DST} ({size:,} bytes, {WIDTH}x{HEIGHT})")
    if size > 200 * 1024:
        sys.stderr.write(
            f"warning: {DST.name} is {size:,} bytes, exceeds 200 KB budget\n"
        )
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(build())
