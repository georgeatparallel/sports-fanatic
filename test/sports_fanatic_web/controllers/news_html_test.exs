defmodule SportsFanaticWeb.NewsHTMLTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  @endpoint SportsFanaticWeb.Endpoint

  # ---------------------------------------------------------------------------
  # category_badge/1 — injury severity categories
  # ---------------------------------------------------------------------------

  describe "category_badge/1 injury_new" do
    test "renders red badge with label 'Injury: New'" do
      html =
        render_component(&SportsFanaticWeb.NewsHTML.category_badge/1, category: "injury_new")

      assert html =~ "Injury: New"
      assert html =~ "bg-red-100"
      assert html =~ "text-red-800"
    end
  end

  describe "category_badge/1 injury_worsening" do
    test "renders red badge with label 'Injury: Worsening'" do
      html =
        render_component(&SportsFanaticWeb.NewsHTML.category_badge/1,
          category: "injury_worsening"
        )

      assert html =~ "Injury: Worsening"
      assert html =~ "bg-red-100"
      assert html =~ "text-red-800"
    end
  end

  describe "category_badge/1 injury_update" do
    test "renders yellow badge with label 'Injury: Update'" do
      html =
        render_component(&SportsFanaticWeb.NewsHTML.category_badge/1, category: "injury_update")

      assert html =~ "Injury: Update"
      assert html =~ "bg-yellow-100"
      assert html =~ "text-yellow-800"
    end

    test "does not render red classes" do
      html =
        render_component(&SportsFanaticWeb.NewsHTML.category_badge/1, category: "injury_update")

      refute html =~ "bg-red-100"
    end
  end

  describe "category_badge/1 injury_recovery" do
    test "renders lime badge with label 'Injury: Recovery'" do
      html =
        render_component(&SportsFanaticWeb.NewsHTML.category_badge/1,
          category: "injury_recovery"
        )

      assert html =~ "Injury: Recovery"
      assert html =~ "bg-lime-100"
      assert html =~ "text-lime-800"
    end
  end

  describe "category_badge/1 injury_cleared" do
    test "renders green badge with label 'Injury: Cleared'" do
      html =
        render_component(&SportsFanaticWeb.NewsHTML.category_badge/1, category: "injury_cleared")

      assert html =~ "Injury: Cleared"
      assert html =~ "bg-green-100"
      assert html =~ "text-green-800"
    end
  end

  # ---------------------------------------------------------------------------
  # category_badge/1 — legacy body-part injury categories (backward compat)
  # ---------------------------------------------------------------------------

  describe "category_badge/1 legacy injury categories" do
    test "injury_elbow renders red badge with generic 'Injury' label" do
      html =
        render_component(&SportsFanaticWeb.NewsHTML.category_badge/1, category: "injury_elbow")

      assert html =~ "Injury"
      assert html =~ "bg-red-100"
      assert html =~ "text-red-800"
    end

    test "injury_shoulder renders red badge with generic 'Injury' label" do
      html =
        render_component(&SportsFanaticWeb.NewsHTML.category_badge/1, category: "injury_shoulder")

      assert html =~ "Injury"
      assert html =~ "bg-red-100"
    end

    test "injury_knee renders red badge" do
      html =
        render_component(&SportsFanaticWeb.NewsHTML.category_badge/1, category: "injury_knee")

      assert html =~ "Injury"
      assert html =~ "bg-red-100"
    end

    test "hit_by_pitch renders red badge" do
      html =
        render_component(&SportsFanaticWeb.NewsHTML.category_badge/1, category: "hit_by_pitch")

      assert html =~ "Hit by Pitch"
      assert html =~ "bg-red-100"
      assert html =~ "text-red-800"
    end
  end

  # ---------------------------------------------------------------------------
  # category_badge/1 — non-injury categories
  # ---------------------------------------------------------------------------

  describe "category_badge/1 trade category" do
    test "renders purple badge" do
      html = render_component(&SportsFanaticWeb.NewsHTML.category_badge/1, category: "trade")
      assert html =~ "Trade"
      assert html =~ "bg-purple-100"
      assert html =~ "text-purple-800"
    end
  end

  describe "category_badge/1 performance category" do
    test "renders blue badge" do
      html =
        render_component(&SportsFanaticWeb.NewsHTML.category_badge/1, category: "performance")

      assert html =~ "Performance"
      assert html =~ "bg-blue-100"
      assert html =~ "text-blue-800"
    end
  end

  describe "category_badge/1 transaction category" do
    test "renders orange badge" do
      html =
        render_component(&SportsFanaticWeb.NewsHTML.category_badge/1, category: "transaction")

      assert html =~ "Transaction"
      assert html =~ "bg-orange-100"
      assert html =~ "text-orange-800"
    end
  end

  describe "category_badge/1 news and general categories" do
    test "news renders gray badge with label 'News'" do
      html = render_component(&SportsFanaticWeb.NewsHTML.category_badge/1, category: "news")
      assert html =~ "News"
      assert html =~ "bg-gray-100"
      assert html =~ "text-gray-700"
    end

    test "general renders gray badge with label 'News'" do
      html = render_component(&SportsFanaticWeb.NewsHTML.category_badge/1, category: "general")
      assert html =~ "News"
      assert html =~ "bg-gray-100"
      assert html =~ "text-gray-700"
    end
  end

  describe "category_badge/1 nil and unknown categories" do
    test "nil category renders nothing" do
      html = render_component(&SportsFanaticWeb.NewsHTML.category_badge/1, category: nil)
      refute html =~ "<span"
    end

    test "unknown category renders a gray badge with capitalized name" do
      html = render_component(&SportsFanaticWeb.NewsHTML.category_badge/1, category: "mystery")
      assert html =~ "Mystery"
      assert html =~ "bg-gray-100"
      assert html =~ "text-gray-600"
    end
  end

  # ---------------------------------------------------------------------------
  # sentiment_dot/1
  # ---------------------------------------------------------------------------

  describe "sentiment_dot/1 negative sentiment" do
    test "renders a red dot" do
      html = render_component(&SportsFanaticWeb.NewsHTML.sentiment_dot/1, sentiment: "negative")
      assert html =~ "bg-red-500"
    end

    test "includes title attribute with sentiment value" do
      html = render_component(&SportsFanaticWeb.NewsHTML.sentiment_dot/1, sentiment: "negative")
      assert html =~ ~s(title="Sentiment: negative")
    end

    test "renders a span element" do
      html = render_component(&SportsFanaticWeb.NewsHTML.sentiment_dot/1, sentiment: "negative")
      assert html =~ "<span"
    end
  end

  describe "sentiment_dot/1 neutral sentiment" do
    test "renders a gray dot" do
      html = render_component(&SportsFanaticWeb.NewsHTML.sentiment_dot/1, sentiment: "neutral")
      assert html =~ "bg-gray-400"
    end

    test "does not render red or green" do
      html = render_component(&SportsFanaticWeb.NewsHTML.sentiment_dot/1, sentiment: "neutral")
      refute html =~ "bg-red-500"
      refute html =~ "bg-green-500"
    end
  end

  describe "sentiment_dot/1 positive sentiment" do
    test "renders a green dot" do
      html = render_component(&SportsFanaticWeb.NewsHTML.sentiment_dot/1, sentiment: "positive")
      assert html =~ "bg-green-500"
    end

    test "includes title attribute with sentiment value" do
      html = render_component(&SportsFanaticWeb.NewsHTML.sentiment_dot/1, sentiment: "positive")
      assert html =~ ~s(title="Sentiment: positive")
    end
  end

  describe "sentiment_dot/1 nil and unknown sentiment" do
    test "nil sentiment renders nothing" do
      html = render_component(&SportsFanaticWeb.NewsHTML.sentiment_dot/1, sentiment: nil)
      refute html =~ "<span"
    end

    test "unknown sentiment renders nothing" do
      html = render_component(&SportsFanaticWeb.NewsHTML.sentiment_dot/1, sentiment: "mixed")
      refute html =~ "<span"
    end
  end
end
