defmodule PeggyWeb.PageLive do
  use PeggyWeb, :live_view

  @impl true
  def mount(_params, session, socket) do
    PeggyWeb.LiveHelpers.set_locale(session)
    {:ok, assign(socket, query: "", results: %{})}
  end
end
