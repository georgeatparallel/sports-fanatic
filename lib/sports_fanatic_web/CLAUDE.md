Parent: `../../CLAUDE.md`

# CLAUDE.md — `lib/sports_fanatic_web/`

> See the Documentation Placement Rule in `../../CLAUDE.md` before adding
> content here.

---

Phoenix web layer. Controllers, LiveViews, plugs, components, layouts.

## Folder layout

```
lib/sports_fanatic_web/
  components/         seo_components.ex — json_ld/2, breadcrumbs/1,
                         subscribe_cta/1, date_nav/1
  controllers/        See controllers/CLAUDE.md
  live/               See live/CLAUDE.md
  plugs/              FetchCurrentUser, RequireAuthenticated, RequireAdmin,
                       RequireJoshua, JoshuaRateLimiter, SubscriptionGate,
                       VerifyStripeWebhook, CacheRawBody
  router.ex           Route definitions
  endpoint.ex         Phoenix Endpoint
  telemetry.ex        Telemetry registration
```

## SEO assigns (every public controller action)

`SportsFanaticWeb.SEO` (`lib/sports_fanatic_web/seo.ex`) is the single source
of truth for site-wide defaults and absolute-URL construction. All assigns are
optional — a page that sets none still renders complete OG + Twitter Card +
canonical tags from `SEO` defaults via `root.html.heex`.

```elixir
conn
|> assign(:page_title, "...")            # <title>; default SEO.default_title/0
|> assign(:meta_description, "...")      # max 160 chars; default SEO.default_description/0
|> assign(:canonical_url, "...")         # use :canonical_url (NOT :canonical)
|> assign(:og_type, "website")           # "website" (default), "article", or "profile"
|> assign(:og_image, "...")              # path ("/images/x.png") or absolute HTTPS URL; http:// rejected
|> assign(:og_image_alt, "...")          # default SEO.default_og_image_alt/0
|> assign(:json_ld, Jason.encode!(...))  # ALWAYS via Jason.encode!/1, never raw strings
```

When `og_type` is `"article"`, also assign:

```elixir
|> assign(:article_published_time, "2026-05-17")  # ISO 8601 string or %DateTime{}
|> assign(:article_author, "...")                  # optional; omitted if nil
|> assign(:article_section, "MLB News")            # e.g. "MLB News", "Scouting", "Game Day"
```

The root layout renders these automatically through `<.seo_meta>`. JSON-LD
must come from `Jason.encode!/1` output to prevent XSS via script injection.
Never hardcode `https://www.sports-fan-agent.com` — use `SEO.absolute_url/1`
or `SEO.site_url/0` so URLs are correct in dev (`localhost:4000`) and prod.

## Link previews (Open Graph / Twitter Card / iMessage)

Default OG image: `priv/static/images/og-default.png` (1200×630, 58.5 KB,
served at `/images/og-default.png` — stable URL, not fingerprinted, so
unfurler caches stay valid). SVG source at `priv/static/images/og-default.svg`;
regenerate via `python3 scripts/build_og_image_pillow.py` (Pillow) or
`python3 scripts/build_og_image.py` (cairosvg).

Verify after deploy:

```bash
curl -s -A "facebookexternalhit/1.1" https://www.sports-fan-agent.com/ \
  | grep -E 'og:|twitter:|canonical'
curl -sI https://www.sports-fan-agent.com/images/og-default.png
```

iMessage and Facebook cache previews aggressively (hours to days). Use the
[Facebook Sharing Debugger](https://developers.facebook.com/tools/debug/)
"Scrape Again" button to force-flush. iMessage cache cannot be flushed
remotely.

## Date navigation

`date_nav/1` in `SportsFanaticWeb.SEOComponents` renders prev/next date arrows.

```heex
<%# Controller template — full-page navigation %>
<.date_nav prev_date={@prev_date} next_date={@next_date} base_path="/mlb/news" />

<%# LiveView template — patch navigation keeps the WebSocket alive %>
<.date_nav prev_date={@prev_date} next_date={@next_date} base_path="/mlb/news" link_type={:patch} />
```

Attributes:

- `prev_date`, `next_date` — `%Date{}` or `nil`. nil suppresses that arrow.
- `base_path` — links resolve to `{base_path}/{YYYY-MM-DD}`.
- `link_type` — `:href` (default) or `:patch`.

**News date lookup** lives in `SportsFanatic.News`
(`nearest_news_date_before/1`, `nearest_news_date_after/1`). News
`next_date` is capped at today's Eastern date — future dates are never
linked. `NewsLive` recalculates this cap on every `:tick`.

**Lineup date lookup** lives privately in `LineupController` — no future-date
cap because scheduled games legitimately exist in the future.

## Breadcrumbs

MLB-section pages use a 4-level breadcrumb:
`Home / Baseball / <Section> / <Detail>`. "Baseball" links to `/mlb/teams`.
The same hierarchy appears in the visible `breadcrumbs/1` component **and** in
the JSON-LD `BreadcrumbList`.

Example for lineups: `Home → Baseball (/mlb/teams) → Lineups (/mlb/lineups/<today>) → <date>`.

## Lineups nav link

The Lineups link in the root layout nav (desktop and mobile) is **commented
out** but the `/mlb/lineups/:date` route is fully functional via direct URL.
The nav entry is hidden, not removed.

## Plug pipelines

Detailed in the root `CLAUDE.md`. Quick reminder of which plug enforces what:

| Pipeline | Plug | Effect |
|----------|------|--------|
| `:require_auth` | `RequireAuthenticated` | redirect to `/login` with `return_to` |
| `:require_subscription` | `SubscriptionGate` | redirect to `/subscribe` |
| `:require_admin` | `RequireAdmin` | redirect home; checks `user.is_admin` |
| `:require_joshua` | `RequireJoshua` | checks session passphrase flag |
| `:joshua_rate_limit` | `JoshuaRateLimiter` | per-IP throttle on `/joshua/login` |
| `:stripe_webhook` | `CacheRawBody` + `VerifyStripeWebhook` | sig check |

## Adding a new SEO page

See the recipe in `lib/sports_fanatic_web/controllers/CLAUDE.md`.
