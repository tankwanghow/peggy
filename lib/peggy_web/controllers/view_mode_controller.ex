defmodule PeggyWeb.ViewModeController do
  @moduledoc """
  Pins the user's UI preference (mobile vs. desktop) to a cookie so
  `PeggyWeb.Plugs.AutoRouteByDevice` respects their explicit choice
  across sessions.
  """
  use PeggyWeb, :controller

  @cookie_max_age 60 * 60 * 24 * 365

  def set(conn, %{"mode" => mode, "to" => to})
      when mode in ["mobile", "desktop"] and is_binary(to) do
    conn
    |> put_resp_cookie("peggy_view", mode, max_age: @cookie_max_age, same_site: "Lax")
    |> redirect(to: safe_redirect_path(to))
  end

  def set(conn, _params), do: redirect(conn, to: ~p"/")

  # Only redirect to internal paths to prevent open-redirects.
  defp safe_redirect_path("/" <> _ = path), do: path
  defp safe_redirect_path(_), do: ~p"/"
end
