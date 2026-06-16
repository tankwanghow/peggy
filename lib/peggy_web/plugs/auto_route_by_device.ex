defmodule PeggyWeb.Plugs.AutoRouteByDevice do
  @moduledoc """
  Routes the user to the device-appropriate UI on first visit:

    * `/farms/<slug>/...` (desktop) → `/m/<slug>/...` for mobile UAs
    * `/m/<slug>/...` (mobile)      → `/farms/<slug>/...` for desktop UAs

  A `peggy_view=mobile|desktop` cookie short-circuits the UA check so
  the user's explicit choice (via the Mobile / Desktop toggle links)
  is respected on every subsequent request.

  Only redirects when the destination route is known to exist on the
  other side. Pages that exist on only one UI (audit, reports, batch
  forms, etc.) pass through untouched so we never 404 the user out.
  """
  @behaviour Plug
  import Plug.Conn

  # Desktop URLs that have a 1:1 mobile equivalent. Tail after the
  # "/farms/<slug>" prefix; "" represents the dashboard.
  @mobile_capable_tails [
    "",
    "/animals",
    "/locations",
    "/breeding/gestating",
    "/breeding/lactating"
  ]

  # All mobile URLs have a desktop counterpart at the same path with
  # /m/ swapped for /farms/, so no separate whitelist is needed for
  # the mobile→desktop direction.

  def init(opts), do: opts

  def call(conn, _opts) do
    # Only apply device routing to GET requests. POST/DELETE (form submissions,
    # log-out, invitation accepts) must reach their intended handler directly.
    if conn.method != "GET" do
      conn
    else
      do_route(conn)
    end
  end

  defp do_route(conn) do
    cookie = conn.cookies["peggy_view"]
    path = conn.request_path

    cond do
      cookie == "mobile" and desktop_url?(path) ->
        maybe_redirect_to_mobile(conn, path)

      cookie == "mobile" and invitation_landing?(path) ->
        redirect_swap(conn, path, "/invitations/", "/m/invitations/")

      cookie == "desktop" and mobile_invitation_landing?(path) ->
        redirect_swap(conn, path, "/m/invitations/", "/invitations/")

      cookie == "desktop" and mobile_url?(path) ->
        redirect_swap(conn, path, "/m/", "/farms/")

      cookie ->
        conn

      mobile_ua?(conn) and desktop_url?(path) ->
        maybe_redirect_to_mobile(conn, path)

      mobile_ua?(conn) and invitation_landing?(path) ->
        redirect_swap(conn, path, "/invitations/", "/m/invitations/")

      not mobile_ua?(conn) and mobile_invitation_landing?(path) ->
        redirect_swap(conn, path, "/m/invitations/", "/invitations/")

      not mobile_ua?(conn) and mobile_url?(path) ->
        redirect_swap(conn, path, "/m/", "/farms/")

      true ->
        conn
    end
  end

  defp desktop_url?(path), do: String.starts_with?(path, "/farms/")
  defp mobile_url?(path), do: String.starts_with?(path, "/m/")

  # Matches only the invitation landing page /invitations/<token>, not /invitations/<token>/accept
  defp invitation_landing?(path) do
    case String.split(path, "/invitations/", parts: 2) do
      ["", token] -> token != "" and not String.contains?(token, "/")
      _ -> false
    end
  end

  # Matches only /m/invitations/<token>, not /m/invitations/<token>/accept
  defp mobile_invitation_landing?(path) do
    case String.split(path, "/m/invitations/", parts: 2) do
      ["", token] -> token != "" and not String.contains?(token, "/")
      _ -> false
    end
  end

  defp mobile_ua?(conn), do: PeggyWeb.Device.mobile_ua?(conn)

  defp maybe_redirect_to_mobile(conn, path) do
    case path_tail(path, "/farms/") do
      {:ok, _slug, tail} ->
        if tail in @mobile_capable_tails or sow_detail?(tail) do
          redirect_swap(conn, path, "/farms/", "/m/")
        else
          conn
        end

      :error ->
        conn
    end
  end

  defp redirect_swap(conn, path, from, to) do
    new_path = String.replace_prefix(path, from, to)
    qs = if conn.query_string == "", do: "", else: "?" <> conn.query_string

    conn
    |> Phoenix.Controller.redirect(to: new_path <> qs)
    |> halt()
  end

  defp path_tail(path, prefix) do
    case String.split(path, prefix, parts: 2) do
      ["", rest] ->
        case String.split(rest, "/", parts: 2) do
          [slug] -> {:ok, slug, ""}
          [slug, rest_tail] -> {:ok, slug, "/" <> rest_tail}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  # /farms/<slug>/animals/<id> — animals detail has a mobile counterpart.
  defp sow_detail?(tail), do: String.match?(tail, ~r{^/animals/\d+$})
end
