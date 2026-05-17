#!/usr/bin/env python3
"""Render priv/static/images/og-default.svg to og-default.png at 1200x630.

Preferred method: cairosvg (`pip install cairosvg`). For an environment without
cairosvg, run `scripts/build_og_image_pillow.py` instead — it paints the image
programmatically with Pillow, which is installed in the python_bridge service.
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "priv" / "static" / "images" / "og-default.svg"
DST = ROOT / "priv" / "static" / "images" / "og-default.png"


def main() -> int:
    try:
        import cairosvg
    except ImportError:
        sys.stderr.write(
            "cairosvg not installed. Either `pip install cairosvg` or run "
            "scripts/build_og_image_pillow.py for a Pillow-only fallback.\n"
        )
        return 1

    cairosvg.svg2png(
        url=str(SRC),
        write_to=str(DST),
        output_width=1200,
        output_height=630,
    )
    size = DST.stat().st_size
    print(f"Wrote {DST} ({size:,} bytes)")
    if size > 200 * 1024:
        sys.stderr.write(
            f"warning: {DST.name} is {size:,} bytes, exceeds 200 KB budget\n"
        )
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
