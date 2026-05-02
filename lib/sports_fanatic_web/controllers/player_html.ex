defmodule SportsFanaticWeb.PlayerHTML do
  use SportsFanaticWeb, :html

  embed_templates "player_html/*"

  @category_labels %{
    "performance_analysis" => "Performance Analysis",
    "injury_report" => "Injury Report",
    "trade_rumor" => "Trade Rumors",
    "prospect_evaluation" => "Prospect Evaluation",
    "fantasy_value" => "Fantasy Value",
    "betting_insight" => "Betting Insights",
    "general_news" => "General News"
  }

  @category_colors %{
    "performance_analysis" => "bg-blue-500",
    "injury_report" => "bg-red-500",
    "trade_rumor" => "bg-orange-500",
    "prospect_evaluation" => "bg-purple-500",
    "fantasy_value" => "bg-green-500",
    "betting_insight" => "bg-yellow-500",
    "general_news" => "bg-gray-500"
  }

  def category_label(category),
    do: Map.get(@category_labels, category, String.capitalize(category))

  def category_color(category), do: Map.get(@category_colors, category, "bg-gray-500")
end
