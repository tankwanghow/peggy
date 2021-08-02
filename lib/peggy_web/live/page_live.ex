defmodule PeggyWeb.PageLive do
  use PeggyWeb, :live_view

  @impl true
  def mount(_params, session, socket) do
    PeggyWeb.LiveHelpers.set_locale(session)

    socket = assign(socket, :page_title, gettext("Peggy Welcome Page"))

    if session["current_farm"] do
      {:ok, assign_current_farm(socket, session) }
    else
      {:ok, assign(socket, :current_farm, nil) }
    end
  end
end
