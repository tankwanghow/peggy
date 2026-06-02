defmodule PeggyWeb.Locale do
  @moduledoc """
  Sets the Gettext locale for the current request / LiveView from the
  authenticated user's `locale` field, falling back to the default.
  """

  import Plug.Conn

  @supported ~w(en ms zh)
  @default "en"

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)
    locale = locale_for(conn.assigns[:current_scope], conn.cookies["peggy_locale"])
    Gettext.put_locale(PeggyWeb.Gettext, locale)

    conn
    |> assign(:locale, locale)
    |> put_session(:locale, locale)
  end

  def on_mount(:default, _params, session, socket) do
    locale = locale_for(socket.assigns[:current_scope], session["locale"])
    Gettext.put_locale(PeggyWeb.Gettext, locale)
    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end

  # Precedence: logged-in user's locale, then the request/session fallback
  # (cookie for the plug, session value for LiveView), then the default.
  defp locale_for(%{user: %{locale: l}}, _fallback) when l in @supported, do: l
  defp locale_for(_scope, fallback) when fallback in @supported, do: fallback
  defp locale_for(_scope, _fallback), do: @default
end
