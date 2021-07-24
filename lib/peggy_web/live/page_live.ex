defmodule PeggyWeb.PageLive do
  use PeggyWeb, :live_view

  @impl true
  def mount(_params, session, socket) do
    PeggyWeb.LiveHelpers.set_locale(session)

    if session["current_farm"] do
      {:ok,
       socket
       |> assign_current_farm(session)}
    else
      {:ok, assign(socket, :current_farm, nil)}
    end
  end
end
