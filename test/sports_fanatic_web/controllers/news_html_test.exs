defmodule SportsFanaticWeb.NewsHTMLTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  @endpoint SportsFanaticWeb.Endpoint

  # ---------------------------------------------------------------------------
  # category_badge/1
  # ---------------------------------------------------------------------------

  describe "category_badge/1 injury categories" do
    test "injury_elbow renders red badge with label 'Injury: Elbow'" do
      html =
        render_component(&SportsFanaticWeb.NewsHTML.category_badge/1, category: "injury_elbow")

      assert html =~ "Injury: Elbow"
      assert html =~ "bg-red-100"
      assert html =~ "text-red-800"
    end

    test "injury_shoulder renders red badge with label 'Injury: Shoulder'" do
      html =
        render_component(&SportsFanaticWeb.NewsHTML.category_badge/1, category: "injury_shoulder")

      assert html =~ "Injury: Shoulder"
      assert html =~ "bg-red-100"
      assert html =~ "text-red-800"
    end

    test "injury_oblique renders red badge with label 'Injury: Oblique'" do
      html =
        render_component(&SportsFanaticWeb.NewsHTML.category_badge/1, category: "injury_oblique")

      assert html =~ "Injury: Oblique"
      assert html =~ "bg-red-100"
    end

    test "injury_back renders red badge with label 'Injury: Back'" do
      html =
        render_component(&SportsFanaticWeb.NewsHTML.category_badge/1, category: "injury_back")

      assert html =~ "Injury: Back"
      assert html =~ "bg-red-100"
    end

    test "injury_knee renders red badge with label 'Injury: Knee'" do
      html =
        render_component(&SportsFanaticWeb.NewsHTML.category_badge/1, category: "injury_knee")

      assert html =~ "Injury: Knee"
      assert html =~ "bg-red-100"
    end

    test "injury_hamstring renders red badge with label 'Injury: Hamstring'" do
      html =
        render_component(&SportsFanaticWeb.NewsHTML.category_badge/1,
          category: "injury_hamstring"
        )

      assert html =~ "Injury: Hamstring"
      assert html =~ "bg-red-100"
    end

    test "injury_other renders red badge with label 'Injury: Other'" do
      html =
        render_component(&SportsFanaticWeb.NewsHTML.category_badge/1, category: "injury_other")

      assert html =~ "Injury: Other"
      assert html =~ "bg-red-100"
    end
  end

  describe "category_badge/1 trade category" do
    test "trade renders blue badge" do
      html = render_component(&SportsFanaticWeb.NewsHTML.category_badge/1, category: "trade")
      assert html =~ "Trade"
      assert html =~ "bg-blue-100"
      assert html =~ "text-blue-800"
    end

    test "trade badge does not contain red classes" do
      html = render_component(&SportsFanaticWeb.NewsHTML.category_badge/1, category: "trade")
      refute html =~ "bg-red-100"
    end
  end

  describe "category_badge/1 hit_by_pitch category" do
    test "hit_by_pitch renders orange badge" do
      html =
        render_component(&SportsFanaticWeb.NewsHTML.category_badge/1, category: "hit_by_pitch")

      assert html =~ "Hit by Pitch"
      assert html =~ "bg-orange-100"
      assert html =~ "text-orange-800"
    end
  end

  describe "category_badge/1 news and general categories" do
    test "news renders green badge with label 'News'" do
      html = render_component(&SportsFanaticWeb.NewsHTML.category_badge/1, category: "news")
      assert html =~ "News"
      assert html =~ "bg-green-100"
      assert html =~ "text-green-800"
    end

    test "general renders green badge with label 'News'" do
      html = render_component(&SportsFanaticWeb.NewsHTML.category_badge/1, category: "general")
      assert html =~ "News"
      assert html =~ "bg-green-100"
      assert html =~ "text-green-800"
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
