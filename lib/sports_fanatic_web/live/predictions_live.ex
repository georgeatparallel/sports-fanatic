defmodule SportsFanaticWeb.PredictionsLive do
  @moduledoc """
  Public hit-predictions feed at `/predictions`. Lists today's lineup
  players sorted by predicted hit % descending. Live-updates on
  `{:hits_ready, date}` PubSub broadcasts.
  """

  use SportsFanaticWeb, :live_view

  alias Phoenix.PubSub
  alias SportsFanatic.Predictions

  @impl true
  def mount(_params, _session, socket) do
    today = SportsFanatic.DateHelper.today()

    if connected?(socket) do
      PubSub.subscribe(SportsFanatic.PubSub, "predictions:hits:#{Date.to_iso8601(today)}")
    end

    predictions = Predictions.list_for_date(today)
    teams = teams_in(predictions)

    json_ld =
      %{
        "@context" => "https://schema.org",
        "@type" => "WebPage",
        "name" => "MLB Hit Predictions - #{Date.to_iso8601(today)}",
        "url" => "https://sportsfanatic.com/predictions"
      }
      |> Jason.encode!()

    {:ok,
     socket
     |> assign(:page_title, "MLB Hit Predictions for #{Date.to_iso8601(today)}")
     |> assign(
       :meta_description,
       "AI-powered MLB hit probability predictions for today's lineups, ranked by likelihood of a hit."
     )
     |> assign(:canonical_url, "https://sportsfanatic.com/predictions")
     |> assign(:og_image, "https://sportsfanatic.com/images/og-default.png")
     |> assign(:json_ld, json_ld)
     |> assign(:predictions_date, today)
     |> assign(:predictions, predictions)
     |> assign(:teams, teams)
     |> assign(:filter_team, nil)
     |> assign(:filter_min_prob, nil)}
  end

  @impl true
  def handle_info({:hits_ready, %Date{} = date}, socket) do
    if Date.compare(date, socket.assigns.predictions_date) == :eq do
      preds = Predictions.list_for_date(date)
      {:noreply, assign(socket, predictions: preds, teams: teams_in(preds))}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("filter_team", %{"team" => team}, socket) do
    team = if team in [nil, ""], do: nil, else: team
    {:noreply, assign(socket, :filter_team, team)}
  end

  def handle_event("filter_min_prob", %{"min" => min}, socket) do
    parsed =
      case Float.parse(min || "") do
        {f, _} -> f
        :error -> nil
      end

    {:noreply, assign(socket, :filter_min_prob, parsed)}
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  ## --- Render ---------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <header class="mb-6">
        <h1 class="text-3xl font-bold text-gray-900">
          Hit Predictions — <%= Calendar.strftime(@predictions_date, "%B %d, %Y") %>
        </h1>
        <p class="text-gray-600 mt-1 text-sm">
          Today's lineup ranked by predicted probability of recording at least one hit.
        </p>
      </header>

      <div class="flex flex-wrap items-center gap-3 mb-6">
        <form phx-change="filter_team" class="flex items-center gap-2">
          <label for="team-filter" class="text-sm text-gray-600">Team</label>
          <select
            id="team-filter"
            name="team"
            class="rounded border border-gray-300 text-sm py-1.5 px-2"
          >
            <option value="">All</option>
            <%= for t <- @teams do %>
              <option value={t} selected={@filter_team == t}><%= t %></option>
            <% end %>
          </select>
        </form>

        <form phx-change="filter_min_prob" class="flex items-center gap-2">
          <label for="min-prob" class="text-sm text-gray-600">Min %</label>
          <input
            id="min-prob"
            name="min"
            type="number"
            min="0"
            max="1"
            step="0.05"
            value={if @filter_min_prob, do: @filter_min_prob, else: ""}
            class="w-24 rounded border border-gray-300 text-sm py-1.5 px-2"
          />
        </form>
      </div>

      <%= if Enum.empty?(@predictions) do %>
        <div class="bg-amber-50 border border-amber-200 text-amber-900 px-4 py-3 rounded">
          Predictions for today are still being prepared — check back at 8:30 AM ET.
        </div>
      <% else %>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          <%= for pred <- filtered(@predictions, @filter_team, @filter_min_prob) do %>
            <.prediction_card pred={pred} />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp prediction_card(assigns) do
    ~H"""
    <article class="bg-white border border-gray-200 rounded-lg shadow-sm p-4 hover:shadow-md transition">
      <div class="flex items-start justify-between">
        <div>
          <h2 class="text-lg font-semibold text-gray-900">
            <%= @pred.player_name %>
          </h2>
          <p class="text-sm text-gray-600">
            <%= @pred.player_team %> <%= if @pred.is_home, do: "vs", else: "@" %> <%= @pred.vs_team %>
          </p>
        </div>
        <span class={"text-3xl font-bold #{prob_color(@pred.hit_prob)}"}>
          <%= format_pct(@pred.hit_prob) %>
        </span>
      </div>
      <dl class="mt-3 grid grid-cols-2 gap-1 text-xs text-gray-600">
        <%= if @pred.game_datetime do %>
          <div class="col-span-2">
            <dt class="inline font-medium text-gray-500">Game:</dt>
            <dd class="inline ml-1"><%= format_time(@pred.game_datetime) %></dd>
          </div>
        <% end %>
        <%= if @pred.batting_order do %>
          <div>
            <dt class="inline font-medium text-gray-500">Order:</dt>
            <dd class="inline ml-1">#<%= @pred.batting_order %></dd>
          </div>
        <% end %>
        <%= if @pred.probable_pitcher_name do %>
          <div class="col-span-2">
            <dt class="inline font-medium text-gray-500">vs:</dt>
            <dd class="inline ml-1"><%= @pred.probable_pitcher_name %></dd>
          </div>
        <% end %>
        <%= if @pred.venue_name do %>
          <div class="col-span-2">
            <dt class="inline font-medium text-gray-500">Park:</dt>
            <dd class="inline ml-1"><%= @pred.venue_name %></dd>
          </div>
        <% end %>
      </dl>
    </article>
    """
  end

  ## --- View helpers ---------------------------------------------------------

  defp teams_in(predictions) do
    predictions
    |> Enum.map(& &1.player_team)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp filtered(predictions, team, min_prob) do
    predictions
    |> Enum.filter(fn p ->
      (team in [nil, ""] or p.player_team == team) and
        (is_nil(min_prob) or p.hit_prob >= min_prob)
    end)
  end

  defp format_pct(nil), do: "—"
  defp format_pct(p) when is_float(p), do: "#{Float.round(p * 100, 1)}%"
  defp format_pct(_), do: "—"

  defp format_time(nil), do: ""

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%-I:%M %p UTC")
  end

  defp format_time(_), do: ""

  defp prob_color(p) when is_float(p) and p >= 0.70, do: "text-emerald-600"
  defp prob_color(p) when is_float(p) and p >= 0.55, do: "text-blue-600"
  defp prob_color(p) when is_float(p) and p >= 0.40, do: "text-gray-700"
  defp prob_color(p) when is_float(p), do: "text-rose-600"
  defp prob_color(_), do: "text-gray-700"
end
