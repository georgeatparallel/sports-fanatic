defmodule SportsFanaticWeb.NewsHTML do
  use SportsFanaticWeb, :html

  embed_templates "news_html/*"

  attr :category, :string, default: nil
  attr :injury_area, :string, default: nil
  attr :injury_grade, :string, default: nil

  def category_badge(assigns) do
    {label, color_classes} = category_display(assigns.category)

    injury_detail =
      injury_detail_label(assigns.category, assigns.injury_area, assigns.injury_grade)

    assigns =
      assign(assigns, label: label, color_classes: color_classes, injury_detail: injury_detail)

    ~H"""
    <%= if @label do %>
      <span class={"inline-flex items-center px-2 py-0.5 rounded text-xs font-medium #{@color_classes}"}>
        <%= if @injury_detail do %>
          <%= @injury_detail %>
        <% else %>
          <%= @label %>
        <% end %>
      </span>
    <% end %>
    """
  end

  attr :sentiment, :string, default: nil

  def sentiment_dot(assigns) do
    color = sentiment_color(assigns.sentiment)
    assigns = assign(assigns, color: color)

    ~H"""
    <%= if @color do %>
      <span
        class={"inline-block w-2.5 h-2.5 rounded-full #{@color}"}
        title={"Sentiment: #{@sentiment}"}
      >
      </span>
    <% end %>
    """
  end

  # Build a combined injury detail label like "Oblique Strain . 10-Day IL"
  defp injury_detail_label(category, injury_area, injury_grade)
       when is_binary(category) and binary_part(category, 0, 7) == "injury_" do
    area_part = if injury_area && injury_area != "", do: injury_area, else: nil
    grade_part = format_injury_grade(injury_grade)

    case {area_part, grade_part} do
      {nil, nil} -> nil
      {area, nil} -> area
      {nil, grade} -> grade
      {area, grade} -> "#{area} \u00B7 #{grade}"
    end
  end

  defp injury_detail_label(_category, _injury_area, _injury_grade), do: nil

  defp format_injury_grade(nil), do: nil
  defp format_injury_grade("day_to_day"), do: "Day-to-Day"
  defp format_injury_grade("10_day_il"), do: "10-Day IL"
  defp format_injury_grade("15_day_il"), do: "15-Day IL"
  defp format_injury_grade("60_day_il"), do: "60-Day IL"
  defp format_injury_grade("season_ending"), do: "Season-Ending"
  defp format_injury_grade("pending_imaging"), do: "Pending Imaging"
  defp format_injury_grade("cleared"), do: "Cleared"
  defp format_injury_grade("rehab_assignment"), do: "Rehab Assignment"
  defp format_injury_grade("unknown"), do: "Unknown"
  defp format_injury_grade(_), do: nil

  defp category_display(nil), do: {nil, ""}

  defp category_display("injury_new"),
    do: {"Injury: New", "bg-red-100 text-red-800"}

  defp category_display("injury_worsening"),
    do: {"Injury: Worsening", "bg-red-100 text-red-800"}

  defp category_display("injury_update"),
    do: {"Injury: Update", "bg-yellow-100 text-yellow-800"}

  defp category_display("injury_recovery"),
    do: {"Injury: Recovery", "bg-lime-100 text-lime-800"}

  defp category_display("injury_cleared"),
    do: {"Injury: Cleared", "bg-green-100 text-green-800"}

  defp category_display("trade"),
    do: {"Trade", "bg-purple-100 text-purple-800"}

  defp category_display("performance"),
    do: {"Performance", "bg-blue-100 text-blue-800"}

  defp category_display("transaction"),
    do: {"Transaction", "bg-orange-100 text-orange-800"}

  defp category_display("news"),
    do: {"News", "bg-gray-100 text-gray-700"}

  defp category_display("general"),
    do: {"News", "bg-gray-100 text-gray-700"}

  # Legacy body-part injury categories — render as generic red "Injury" badge
  defp category_display("injury_" <> _body_part),
    do: {"Injury", "bg-red-100 text-red-800"}

  defp category_display("hit_by_pitch"),
    do: {"Hit by Pitch", "bg-red-100 text-red-800"}

  defp category_display(other),
    do: {String.capitalize(other), "bg-gray-100 text-gray-600"}

  defp sentiment_color("negative"), do: "bg-red-500"
  defp sentiment_color("neutral"), do: "bg-gray-400"
  defp sentiment_color("positive"), do: "bg-green-500"
  defp sentiment_color(_), do: nil
end
