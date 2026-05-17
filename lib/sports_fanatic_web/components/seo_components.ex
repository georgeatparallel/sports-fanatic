defmodule SportsFanaticWeb.SEOComponents do
  @moduledoc """
  Reusable SEO components: JSON-LD, Open Graph, breadcrumbs, subscribe CTA.
  """

  use Phoenix.Component
  import Phoenix.HTML, only: [raw: 1]

  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :canonical_url, :string, required: true
  attr :og_type, :string, default: "website"
  attr :og_image, :string, required: true
  attr :og_image_width, :integer, default: 1200
  attr :og_image_height, :integer, default: 630
  attr :og_image_alt, :string, required: true
  attr :twitter_card, :string, default: "summary_large_image"
  attr :twitter_site, :string, default: nil
  attr :article_published_time, :any, default: nil
  attr :article_author, :string, default: nil
  attr :article_section, :string, default: nil

  def seo_meta(assigns) do
    ~H"""
    <meta name="description" content={@description} />
    <link rel="canonical" href={@canonical_url} />
    <%!-- Open Graph (Facebook, LinkedIn, iMessage, Slack, Discord) --%>
    <meta property="og:site_name" content="Sports Fan Agent" />
    <meta property="og:locale" content="en_US" />
    <meta property="og:type" content={@og_type} />
    <meta property="og:title" content={@title} />
    <meta property="og:description" content={@description} />
    <meta property="og:url" content={@canonical_url} />
    <meta property="og:image" content={@og_image} />
    <meta property="og:image:secure_url" content={@og_image} />
    <meta property="og:image:type" content="image/png" />
    <meta property="og:image:width" content={to_string(@og_image_width)} />
    <meta property="og:image:height" content={to_string(@og_image_height)} />
    <meta property="og:image:alt" content={@og_image_alt} />
    <%= if @og_type == "article" do %>
      <%= if @article_published_time do %>
        <meta property="article:published_time" content={iso8601(@article_published_time)} />
      <% end %>
      <%= if @article_author do %>
        <meta property="article:author" content={@article_author} />
      <% end %>
      <%= if @article_section do %>
        <meta property="article:section" content={@article_section} />
      <% end %>
    <% end %>
    <%!-- Twitter / X --%>
    <meta name="twitter:card" content={@twitter_card} />
    <meta name="twitter:title" content={@title} />
    <meta name="twitter:description" content={@description} />
    <meta name="twitter:image" content={@og_image} />
    <meta name="twitter:image:alt" content={@og_image_alt} />
    <%= if @twitter_site do %>
      <meta name="twitter:site" content={@twitter_site} />
    <% end %>
    """
  end

  # Coerce an %DateTime{}, %Date{}, or already-formatted string to an ISO 8601 string.
  defp iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp iso8601(%Date{} = d), do: Date.to_iso8601(d)
  defp iso8601(s) when is_binary(s), do: s

  attr :data, :map, required: true

  def json_ld(assigns) do
    ~H"""
    <script type="application/ld+json">
      <%= raw(Jason.encode!(@data)) %>
    </script>
    """
  end

  attr :items, :list, required: true

  def breadcrumbs(assigns) do
    ~H"""
    <nav aria-label="Breadcrumb" class="text-sm text-gray-500 mb-4">
      <ol class="flex items-center space-x-2" itemscope itemtype="https://schema.org/BreadcrumbList">
        <%= for {item, idx} <- Enum.with_index(@items) do %>
          <li itemprop="itemListElement" itemscope itemtype="https://schema.org/ListItem">
            <%= if idx > 0 do %>
              <span class="mx-1">/</span>
            <% end %>
            <%= if item[:href] do %>
              <a href={item.href} itemprop="item" class="hover:text-blue-600">
                <span itemprop="name"><%= item.label %></span>
              </a>
            <% else %>
              <span itemprop="name" class="text-gray-900 font-medium"><%= item.label %></span>
            <% end %>
            <meta itemprop="position" content={to_string(idx + 1)} />
          </li>
        <% end %>
      </ol>
    </nav>
    """
  end

  attr :prev_date, Date, default: nil
  attr :next_date, Date, default: nil
  attr :base_path, :string, required: true
  attr :link_type, :atom, default: :href, values: [:href, :patch]

  def date_nav(assigns) do
    ~H"""
    <nav class="flex justify-between items-center py-3" aria-label="Date navigation">
      <%= if @prev_date do %>
        <.date_nav_link
          path={"#{@base_path}/#{Date.to_iso8601(@prev_date)}"}
          link_type={@link_type}
          class="text-blue-600 hover:text-blue-800 font-medium text-sm"
        >
          &larr; <%= Calendar.strftime(@prev_date, "%b %d") %>
        </.date_nav_link>
      <% else %>
        <span></span>
      <% end %>
      <%= if @next_date do %>
        <.date_nav_link
          path={"#{@base_path}/#{Date.to_iso8601(@next_date)}"}
          link_type={@link_type}
          class="text-blue-600 hover:text-blue-800 font-medium text-sm"
        >
          <%= Calendar.strftime(@next_date, "%b %d") %> &rarr;
        </.date_nav_link>
      <% else %>
        <span></span>
      <% end %>
    </nav>
    """
  end

  attr :path, :string, required: true
  attr :link_type, :atom, required: true
  attr :class, :string, default: ""
  slot :inner_block, required: true

  defp date_nav_link(%{link_type: :patch} = assigns) do
    ~H"""
    <.link patch={@path} class={@class}>
      <%= render_slot(@inner_block) %>
    </.link>
    """
  end

  defp date_nav_link(%{link_type: :href} = assigns) do
    ~H"""
    <a href={@path} class={@class}>
      <%= render_slot(@inner_block) %>
    </a>
    """
  end

  attr :return_to, :string, default: "/subscribe"

  def subscribe_cta(assigns) do
    ~H"""
    <%= if SportsFanatic.FeatureFlags.enabled?("subscriptions_enabled") do %>
      <div class="bg-gradient-to-r from-blue-600 to-indigo-700 rounded-xl p-8 text-white text-center my-8">
        <h3 class="text-2xl font-bold mb-2">Unlock Full Premium Content</h3>
        <p class="text-blue-100 mb-6 max-w-xl mx-auto">
          Get complete scouting reports, Game Day Magazines, hit and HR predictions,
          and real-time updates. Start your 7-day free trial today.
        </p>
        <div class="flex justify-center gap-4">
          <a
            href="/subscribe"
            class="bg-white text-blue-700 font-semibold px-8 py-3 rounded-lg hover:bg-blue-50 transition"
          >
            Start Free Trial
          </a>
          <a
            href={"/login?return_to=#{@return_to}"}
            class="border border-white text-white font-semibold px-8 py-3 rounded-lg hover:bg-white/10 transition"
          >
            Sign In
          </a>
        </div>
        <p class="text-blue-200 text-sm mt-4">$9.99/mo or $79.99/yr after trial</p>
      </div>
    <% end %>
    """
  end
end
