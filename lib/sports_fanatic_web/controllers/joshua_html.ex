defmodule SportsFanaticWeb.JoshuaHTML do
  use SportsFanaticWeb, :html

  def login(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <meta name="robots" content="noindex, nofollow" />
        <title>Access</title>
        <link phx-track-static rel="stylesheet" href={~p"/assets/app.css"} />
      </head>
      <body class="bg-gray-100 min-h-screen flex items-center justify-center">
        <div class="w-full max-w-sm">
          <div class="bg-white shadow-md rounded-lg p-8">
            <h1 class="text-lg font-semibold text-gray-800 mb-6 text-center">Access</h1>

            <%= if @error do %>
              <div class="mb-4 p-3 bg-red-50 border border-red-200 rounded text-sm text-red-700">
                <%= @error %>
              </div>
            <% end %>

            <form action="/joshua/login" method="post">
              <input type="hidden" name="_csrf_token" value={get_csrf_token()} />

              <div class="mb-4">
                <label for="username" class="block text-sm font-medium text-gray-700 mb-1">
                  Username
                </label>
                <input
                  type="text"
                  id="username"
                  name="username"
                  required
                  autocomplete="off"
                  class="block w-full rounded-md border-gray-300 shadow-sm focus:border-gray-500 focus:ring-gray-500 sm:text-sm"
                />
              </div>

              <div class="mb-6">
                <label for="password" class="block text-sm font-medium text-gray-700 mb-1">
                  Password
                </label>
                <input
                  type="password"
                  id="password"
                  name="password"
                  required
                  autocomplete="off"
                  class="block w-full rounded-md border-gray-300 shadow-sm focus:border-gray-500 focus:ring-gray-500 sm:text-sm"
                />
              </div>

              <button
                type="submit"
                class="w-full bg-gray-800 text-white py-2 px-4 rounded-md text-sm font-medium hover:bg-gray-900 transition"
              >
                Sign In
              </button>
            </form>
          </div>
        </div>
      </body>
    </html>
    """
  end
end
