defmodule SportsFanaticWeb.SEOComponents do
  @moduledoc """
  Reusable SEO components: JSON-LD, Open Graph, breadcrumbs, subscribe CTA.
  """

  use Phoenix.Component
  import Phoenix.HTML, only: [raw: 1]

  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :canonical, :string, required: true
  attr :og_type, :string, default: "website"
  attr :og_image, :string, default: nil
  attr :twitter_card, :string, default: "summary_large_image"

  def seo_meta(assigns) do
    ~H"""
    <meta name="description" content={@description} />
    <link rel="canonical" href={@canonical} />
    <meta property="og:title" content={@title} />
    <meta property="og:description" content={@description} />
    <meta property="og:url" content={@canonical} />
    <meta property="og:type" content={@og_type} />
    <meta property="og:site_name" content="Sports Fanatic" />
    <%= if @og_image do %>
      <meta property="og:image" content={@og_image} />
    <% end %>
    <meta name="twitter:card" content={@twitter_card} />
    <meta name="twitter:title" content={@title} />
    <meta name="twitter:description" content={@description} />
    <%= if @og_image do %>
      <meta name="twitter:image" content={@og_image} />
    <% end %>
    """
  end

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

  attr :return_to, :string, default: "/subscribe"

  def subscribe_cta(assigns) do
    ~H"""
    <div class="bg-gradient-to-r from-blue-600 to-indigo-700 rounded-xl p-8 text-white text-center my-8">
      <h3 class="text-2xl font-bold mb-2">Unlock Full Premium Content</h3>
      <p class="text-blue-100 mb-6 max-w-xl mx-auto">
        Get complete scouting reports, Game Day Magazines, hit and HR predictions,
        and real-time updates. Start your 7-day free trial today.
      </p>
      <div class="flex justify-center gap-4">
        <a href="/subscribe" class="bg-white text-blue-700 font-semibold px-8 py-3 rounded-lg hover:bg-blue-50 transition">
          Start Free Trial
        </a>
        <a href={"/login?return_to=#{@return_to}"} class="border border-white text-white font-semibold px-8 py-3 rounded-lg hover:bg-white/10 transition">
          Sign In
        </a>
      </div>
      <p class="text-blue-200 text-sm mt-4">$9.99/mo or $79.99/yr after trial</p>
    </div>
    """
  end
end
