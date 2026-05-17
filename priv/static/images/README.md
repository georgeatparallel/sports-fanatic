# Static Images

## `og-default.png` — Open Graph default preview (1200×630)

Default site preview image used by `<.seo_meta>` in the root layout when no
per-page `og_image` is assigned. Rendered into the page as:

```html
<meta property="og:image"        content="https://www.sports-fan-agent.com/images/og-default.png" />
<meta property="og:image:secure_url" content="..." />
<meta property="og:image:type"   content="image/png" />
<meta property="og:image:width"  content="1200" />
<meta property="og:image:height" content="630" />
<meta property="og:image:alt"    content="Sports Fan Agent — AI-powered MLB scouting, predictions, and game-day intelligence" />
<meta name="twitter:image"       content="..." />
```

Spec: PNG, 1200×630, ≤ 200 KB (iMessage/Slack/Facebook unfurlers spec
1200×630 for the large card; smaller file = faster prefetch).

### Source files

| File             | Purpose                                          |
|------------------|--------------------------------------------------|
| `og-default.svg` | Hand-authored source of truth (editable in any vector tool) |
| `og-default.png` | Rasterized output served to scrapers             |

### Regenerating the PNG

We support two paths so you can use whichever toolchain is on your machine.

**Option A — cairosvg (renders the SVG directly, recommended for fidelity).**

```bash
pip install cairosvg
python3 scripts/build_og_image.py
```

**Option B — Pillow (no SVG dep — paints the image procedurally).** Useful on
machines without cairosvg / rsvg-convert / imagemagick. Pillow is already in
the `python_bridge` service environment.

```bash
python3 scripts/build_og_image_pillow.py
```

Both scripts write to `priv/static/images/og-default.png` and abort with a
warning if the resulting file exceeds the 200 KB budget.

### Updating the design

1. Edit `og-default.svg` (vector source).
2. Run one of the rebuild commands above.
3. Re-commit both `.svg` and `.png`. The PNG is what scrapers fetch — the
   filename must stay stable (no fingerprint hashing) so existing unfurler
   caches (Facebook, iMessage) eventually pick up the new image.

### Cache invalidation note

Facebook, LinkedIn, and iMessage cache previews aggressively (hours to days).
After updating the image, use Facebook's "Scrape Again" debugger
(<https://developers.facebook.com/tools/debug/>) to force a re-scrape on
shared URLs. There is no equivalent for iMessage — the cache simply expires
over time.
