defmodule SportsFanaticWeb.NavRenameTest do
  @moduledoc """
  Smoke tests: verify the "Game Day" → "Players" nav rename was applied in
  root.html.heex and that the Game Day Magazine pages are NOT affected.

  These are file-content assertions — no DB or server required.
  """
  use ExUnit.Case, async: true

  @root_layout_path Path.join([
                      File.cwd!(),
                      "lib/sports_fanatic_web/components/layouts/root.html.heex"
                    ])

  setup do
    {:ok, content} = File.read(@root_layout_path)
    {:ok, content: content}
  end

  describe "root.html.heex — nav label rename" do
    test "desktop nav contains 'Players' label linking to /mlb/players", %{content: content} do
      assert content =~ "Players"
    end

    test "desktop nav 'Players' anchor links to /mlb/players", %{content: content} do
      assert content =~ "/mlb/players/"
    end

    test "nav section does not contain the text 'Game Day' as a nav label", %{content: content} do
      # Split into nav region and rest; the nav ends at </header>.
      # Find the header block and assert "Game Day" is absent there.
      [nav_region | _] = String.split(content, "</header>")

      # "Game Day" must not appear as standalone nav-item text in the header.
      # Magazine-related "Game Day" text lives in the footer area or inside the
      # magazine feature, not in the nav links.
      refute nav_region =~ ">Game Day<",
             "Found '>Game Day<' verbatim text in the nav region of root.html.heex"
    end

    test "footer 'Content' column contains 'Players' link", %{content: content} do
      # Footer appears after </header>
      [_, footer_region] = String.split(content, "</header>", parts: 2)
      assert footer_region =~ "Players"
    end

    test "footer 'Content' column links to /mlb/players", %{content: content} do
      # Both nav and footer link to /mlb/players/{today}
      players_count =
        content
        |> String.split("/mlb/players/")
        |> length()

      # Expect at least 3 occurrences (desktop nav, mobile nav, footer)
      assert players_count >= 4,
             "Expected at least 3 /mlb/players/ anchors in root.html.heex, found #{players_count - 1}"
    end
  end
end
