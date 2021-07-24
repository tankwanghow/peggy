defmodule PeggyWeb.NavigationLive do
  use PeggyWeb, :live_view

  @impl true
  def mount(_params, session, socket) do
    PeggyWeb.LiveHelpers.set_locale(session)

    {:ok,
     socket
     |> assign_current_user(session)
     |> assign_current_farm(session)
     |> assign(:page_title, gettext("Navigation Page"))}
  end
end
