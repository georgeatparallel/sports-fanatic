Parent: `../../../CLAUDE.md`

# CLAUDE.md — Controllers

> See the Documentation Placement Rule in `../../../CLAUDE.md` before adding
> content here.

---

Phoenix controllers and their HTML modules. One controller per route group.

## Controller list

| Controller | Routes |
|------------|--------|
| `PageController` | `/`, `/health` |
| `PlayerController` | `/mlb/players`, `/mlb/players/:team_slug/:player_slug`, sources |
| `TeamController` | `/mlb/teams`, `/mlb/teams/:team_slug` (also renders team magazine section) |
| `LineupController` | `/mlb/lineups/:date` |
| `NewsController` | `/mlb/news/today` (redirect), `/mlb/news/:date/:slug` |
| `ScoutingController` | `/mlb/scouting/:team_slug/:player_slug` (public preview) |
| `GameDayController` | `/mlb/game-day/:date/:slug` (public preview) |
| `SitemapController` | `/sitemap.xml`, `/sitemaps/:type`, `/robots.txt` |
| `InjuryReportController` | `/mlb/injury-report`, `/mlb/injury-report/:player_slug`, `/mlb/injury-report/og/:player_slug.png` |
| `AuthController` | `/register`, `/login`, `/logout`, password reset |
| `SubscriptionController` | `/subscribe/*` |
| `StripeWebhookController` | `/webhooks/stripe` |
| `JoshuaController` | `/joshua/*` |
| `XOAuthController` | `/admin/x/oauth/start`, `/admin/x/oauth/callback` |

## SEO assigns (mandatory for public actions)

```elixir
conn
|> assign(:page_title, "...")
|> assign(:meta_description, "...")          # max 160 chars
|> assign(:canonical_url, SEO.absolute_url("/path"))  # NOT :canonical
|> assign(:og_type, "article")               # or "website" / "profile"
|> assign(:og_image, "...")                  # optional, defaults to site OG image
|> assign(:json_ld, Jason.encode!(...))      # NEVER raw strings
```

See `../CLAUDE.md` for the full set of optional assigns (article fields,
og_image_alt, etc.) and the `SportsFanaticWeb.SEO` helper API.

## Cache-read pattern

```elixir
cache_key = SportsFanatic.Cache.page_key(:player, team_slug, player_slug)

case SportsFanatic.Cache.get(cache_key) do
  {:ok, html} ->
    conn |> put_resp_content_type("text/html") |> send_resp(200, html)

  _ ->
    conn = build_assigns_and_render(conn, ...)
    # cache the rendered HTML for next time
    SportsFanatic.Cache.put(cache_key, render_to_string(conn), :timer.minutes(5))
    conn
end
```

## Slug regex

For any controller action that takes a slug, validate the slug with a
regex **before** any DB lookup or filesystem access:

```elixir
@slug_regex ~r/^[a-z0-9-]{1,100}$/

def show(conn, %{"player_slug" => slug}) do
  if Regex.match?(@slug_regex, slug) do
    # ... DB lookup
  else
    conn |> put_status(404) |> render(SportsFanaticWeb.ErrorHTML, "404.html")
  end
end
```

`InjuryReportController.show/2` and `og_image/2` follow this pattern. OG-image
file paths additionally route the slug through `Storage.sanitize_key/1` before
composing the path.

## Adding a new SEO page (recipe)

1. Add route in `router.ex` under the public `:browser` scope.
2. Create controller in `lib/sports_fanatic_web/controllers/`.
3. Create HTML module + HEEx templates in
   `lib/sports_fanatic_web/controllers/<name>_html/`.
4. Set the five SEO assigns above.
5. Add cache read/write in the controller action.
6. Update `GenerateSitemapWorker` to include new URLs.
7. Verify `git grep -n "raw(" lib/sports_fanatic_web/controllers/<name>_html`
   returns nothing.

## Stripe env vars

| Var | Purpose |
|-----|---------|
| `STRIPE_SECRET_KEY` | `stripity_stripe` API key |
| `STRIPE_WEBHOOK_SECRET` | `VerifyStripeWebhook` plug |
| `STRIPE_PRICE_MONTHLY`, `STRIPE_PRICE_YEARLY` | checkout session config |

Idempotency for Stripe webhooks is not yet implemented (SEC-004). Test
locally:

```bash
docker compose --profile dev up stripe-cli
```
