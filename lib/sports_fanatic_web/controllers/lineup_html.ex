defmodule SportsFanaticWeb.LineupHTML do
  @moduledoc """
  HTML module for `/mlb/lineups/:date` (the rewritten Players page).

  The page is composed entirely with the canonical
  `SportsFanaticWeb.CoreComponents.player_card/1` component plus the global
  SEO components (`breadcrumbs/1`, `date_nav/1`); no per-template helpers
  are required.
  """

  use SportsFanaticWeb, :html

  embed_templates "lineup_html/*"
end
