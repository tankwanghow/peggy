defmodule PeggyWeb.ManifestController do
  use PeggyWeb, :controller

  @doc """
  Serves the web app manifest with absolute icon URLs for the current host.

  Mobile browsers (especially Android Chrome) are picky about manifest icons;
  host-absolute URLs avoid subtle resolution issues when the site is opened via
  a LAN IP or custom domain.
  """
  def show(conn, _params) do
    origin = url(conn, ~p"/")

    manifest = %{
      name: "Peggy",
      short_name: "Peggy",
      description: "Swine farm management for the barn floor and the office.",
      start_url: origin,
      scope: origin,
      display: "standalone",
      background_color: "#E85D26",
      theme_color: "#E85D26",
      icons: [
        %{
          src: url(conn, ~p"/images/icons/icon-192.png"),
          sizes: "192x192",
          type: "image/png",
          purpose: "any"
        },
        %{
          src: url(conn, ~p"/images/icons/icon-512.png"),
          sizes: "512x512",
          type: "image/png",
          purpose: "any"
        }
      ]
    }

    conn
    |> put_resp_content_type("application/manifest+json")
    |> send_resp(200, Jason.encode!(manifest))
  end
end