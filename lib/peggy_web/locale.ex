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
    locale = locale_for(conn.assigns[:current_scope])
    Gettext.put_locale(PeggyWeb.Gettext, locale)
    assign(conn, :locale, locale)
  end

  def on_mount(:default, _params, _session, socket) do
    locale = locale_for(socket.assigns[:current_scope])
    Gettext.put_locale(PeggyWeb.Gettext, locale)
    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end

  defp locale_for(%{user: %{locale: l}}) when l in @supported, do: l
  defp locale_for(_), do: @default
end
