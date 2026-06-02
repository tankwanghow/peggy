defmodule PeggyWeb.LocaleController do
  @moduledoc """
  Persists the logged-in user's UI locale and redirects back to the
  referring page, so `PeggyWeb.Locale` re-applies it on the next request.
  Mirrors `PeggyWeb.ViewModeController`.
  """
  use PeggyWeb, :controller

  alias Peggy.Accounts
  alias Peggy.Accounts.User

  @locales ~w(en ms zh)

  def update(conn, %{"locale" => locale}) when locale in @locales do
    case conn.assigns[:current_scope] do
      %{user: %User{} = user} -> Accounts.update_user_locale(user, locale)
      _ -> :noop
    end

    conn
    |> put_resp_cookie("peggy_locale", locale, max_age: 60 * 60 * 24 * 365, same_site: "Lax")
    |> redirect(to: return_path(conn))
  end

  def update(conn, _params), do: redirect(conn, to: return_path(conn))

  # Only redirect to internal paths; preserve the query string.
  defp return_path(conn) do
    conn |> get_req_header("referer") |> List.first() |> safe_path()
  end

  defp safe_path(referer) when is_binary(referer) do
    uri = URI.parse(referer)
    path = uri.path || "/"
    app_host = PeggyWeb.Endpoint.config(:url)[:host] || "localhost"

    # Allow only same-host or relative-path referers; reject external hosts.
    host_ok = is_nil(uri.host) or uri.host == app_host

    if host_ok and String.starts_with?(path, "/") and not String.starts_with?(path, "//") do
      path <> if(uri.query, do: "?" <> uri.query, else: "")
    else
      ~p"/"
    end
  end

  defp safe_path(_), do: ~p"/"
end
