defmodule SportsFanaticWeb.LineupHtmlAutofocusTest do
  @moduledoc """
  Pure file-content smoke tests for the autofocus + touch-strip changes in
  `lib/sports_fanatic_web/controllers/lineup_html/show.html.heex`.

  No database, no server, no Valkey required — just asserting that the
  expected HTML attribute and JS strings are present in the template source.
  """
  use ExUnit.Case, async: true

  @template_path Path.join([
                   File.cwd!(),
                   "lib/sports_fanatic_web/controllers/lineup_html/show.html.heex"
                 ])

  setup do
    {:ok, content} = File.read(@template_path)
    {:ok, content: content}
  end

  describe "show.html.heex — autofocus attribute" do
    test "player-search-input has the bare autofocus attribute", %{content: content} do
      assert content =~ ~r/id="player-search-input"[^>]*\bautofocus\b/,
             "Expected autofocus on #player-search-input"
    end

    test "autofocus is present before the closing > of the input tag", %{content: content} do
      # Grab the input opening tag
      assert content =~ "autofocus",
             "Template must contain the autofocus keyword"
    end
  end

  describe "show.html.heex — touch-strip JS" do
    test "inline script uses matchMedia to detect touch-only devices", %{content: content} do
      assert content =~ "matchMedia",
             "Expected matchMedia in inline script"
    end

    test "inline script uses (hover: none) media query string", %{content: content} do
      assert content =~ "(hover: none)",
             "Expected '(hover: none)' media query in touch-strip JS block"
    end

    test "inline script calls removeAttribute('autofocus')", %{content: content} do
      assert content =~ "removeAttribute('autofocus')",
             "Expected removeAttribute('autofocus') in touch-strip JS block"
    end

    test "inline script is wrapped in a try/catch for matchMedia safety", %{content: content} do
      assert content =~ "catch",
             "Expected try/catch guard around matchMedia call"
    end
  end
end
