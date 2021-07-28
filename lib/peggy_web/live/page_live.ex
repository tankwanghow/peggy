defmodule PeggyWeb.PageLive do
  use PeggyWeb, :live_view

  @impl true
  def mount(_params, session, socket) do
    PeggyWeb.LiveHelpers.set_locale(session)

    if session["current_farm"] do
      {:ok,
        socket
        |> assign_current_farm(session)
        |>  assign(:page_title, nil)}
    else
      {:ok,
        socket
        |> assign(:current_farm, nil)
        |>  assign(:page_title, nil)}
    end
  end
end
