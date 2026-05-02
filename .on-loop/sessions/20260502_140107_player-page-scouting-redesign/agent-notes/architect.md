# Architect Notes: Player Page Scouting Redesign

## Current State Analysis

### Player Page (`/mlb/players/:team/:player`)
- Shows "AI Scouting Intelligence" section with categorized bullet points from `player_source_urls`
- Content is raw metadata (summaries of URL classifications), not useful narrative content
- Scouting report preview section shows grade + summary + link to full report page
- Quick Links sidebar has: Scouting Report, Team Page, Today's Lineups

### Data Model
- `ScoutingReport` has `summary` (text), `full_report` (map/JSON), `overall_grade`, `strengths`, `weaknesses`
- `full_report` is a JSON map from Claude with: `news_summary`, `positive_factors`, `negative_factors`, `hit_probability`, etc.
- `PlayerSourceUrl` stores: `url`, `source_type`, `classification`, `content_summary`, `key_facts`
- The Exa API returns `text` (up to 5000 chars) per result, but the pipeline discards it after classification -- only stores `content_summary` (1-2 sentence AI summary)

### Feature Flags
- `SportsFanatic.FeatureFlags.enabled?("subscriptions_enabled")` -- defaults to `false`
- Already used in `subscribe_cta` component and player show template

## Specification

### 1. Remove "AI Scouting Intelligence" Section
- Delete the entire categorized sources display (lines 57-90 of show.html.heex)
- Remove the `scouting_sources` assign from the controller
- Keep the `Scouting.classified_sources_for_player/1` function (used by pipeline)

### 2. Display Full Scouting Report Content Above Player Overview
- Position: After the header, before Player Overview
- Content from `scouting.full_report` map -- render as narrative HTML:
  - Summary paragraph from `scouting.summary`
  - Strengths list from `scouting.strengths`
  - Weaknesses list from `scouting.weaknesses`
  - Grade badge from `scouting.overall_grade`
  - Injury status from `scouting.injury_risk` / `scouting.injury_detail`
  - Probabilities from `scouting.hit_probability` / `scouting.hr_probability`
- Remove the old "Scouting Report Preview" section (lines 153-170)
- Keep "no scouting report" notice when `scouting` is nil

### 3. Feature Flag Gating
- When `subscriptions_enabled` is OFF (default): show full scouting report to everyone
- When `subscriptions_enabled` is ON: show truncated preview + subscribe CTA
  - Show summary + grade but hide strengths/weaknesses/probabilities behind CTA
  - Use existing `subscribe_cta` component

### 4. Category Source Sub-Pages
- New route: `GET /mlb/players/:team_slug/:player_slug/sources/:category`
- New controller action: `PlayerController.sources/2`
- New template: `player_html/sources.html.heex`
- Valid categories: the 7 classification values from `PlayerSourceUrl`
- Display: category label, list of sources with `content_summary`, `key_facts`, and `content_text`

### 5. Add Category Quick Links
- In the Quick Links sidebar, add links for each category that has sources
- Pass `scouting_categories` assign (list of category strings with content) to template
- Link format: `/mlb/players/:team/:player/sources/:category`

### 6. Store Full Exa Text in `content_text` Column
- Add migration: `ALTER TABLE content.player_source_urls ADD COLUMN content_text TEXT`
- Update `PlayerSourceUrl` schema to include `content_text` field
- Update pipeline `classify_and_store/2` to store `source["text"]` in `content_text`
- Update `PlayerSourceUrl.changeset/2` to cast `content_text`

## Files to Create/Modify

### New Files
- `priv/repo/migrations/TIMESTAMP_add_content_text_to_player_source_urls.exs`
- `lib/sports_fanatic_web/controllers/player_html/sources.html.heex`

### Modified Files
- `lib/sports_fanatic_web/controllers/player_controller.ex` -- add `sources` action, modify `show`, add `scouting_categories` assign
- `lib/sports_fanatic_web/controllers/player_html/show.html.heex` -- redesign layout
- `lib/sports_fanatic_web/controllers/player_html.ex` -- keep category helpers for sources page
- `lib/sports_fanatic_web/router.ex` -- add sources route
- `lib/sports_fanatic/content/player_source_url.ex` -- add `content_text` field
- `lib/sports_fanatic/scouting/pipeline.ex` -- store `content_text` in `classify_and_store`
- `test/sports_fanatic_web/controllers/player_controller_test.exs` -- update tests

## Cache Considerations
- Player page cache key unchanged: `sf:page:player:{team}:{slug}` TTL 5 min
- No new cache keys needed -- sources pages can be uncached initially (low traffic)
- Scouting report data is already loaded in the player show action

## SEO Considerations
- Sources pages need: page_title, meta_description, canonical_url, json_ld
- Breadcrumbs: Home > Baseball > Players > Team > Player > Sources > Category
