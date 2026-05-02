# Plan: Player Page Scouting Redesign

## Phase 1: Database Migration
1. Create migration to add `content_text` column (TEXT) to `content.player_source_urls`
2. Update `PlayerSourceUrl` schema to include `content_text` field in schema and changeset

## Phase 2: Pipeline Update
3. Update `Scouting.Pipeline.classify_and_store/2` to pass `source["text"]` as `content_text`

## Phase 3: Router
4. Add route `GET /mlb/players/:team_slug/:player_slug/sources/:category` in router.ex

## Phase 4: Controller Changes
5. Modify `PlayerController.show/2`:
   - Remove `scouting_sources` assign
   - Add `scouting_categories` assign (list of category slugs that have sources)
6. Add `PlayerController.sources/2` action:
   - Load team, player, validate category
   - Load sources for that category with content_text
   - Set SEO assigns
   - Render sources template

## Phase 5: Template Redesign
7. Rewrite `show.html.heex`:
   - Remove "AI Scouting Intelligence" section entirely
   - Add full scouting report section ABOVE Player Overview with:
     - Grade badge, summary, strengths, weaknesses, injury info, probabilities
   - Feature flag gating: full content when disabled, truncated + CTA when enabled
   - Remove old "Scouting Report Preview" section
   - Add category links in Quick Links sidebar
8. Create `sources.html.heex`:
   - Breadcrumbs, category heading, list of sources with summary, key_facts, content_text
   - SEO metadata

## Phase 6: HTML Module Update
9. Update `PlayerHTML` module -- keep category helpers, add any new helpers needed

## Phase 7: Tests
10. Update `PlayerControllerTest` -- update existing tests, add sources route tests
