defmodule PeggyWeb.NavigationLive.Index do
  use PeggyWeb, :live_view

  @impl true
  def mount(_params, session, socket) do
    PeggyWeb.LiveHelpers.set_locale(session)

    {:ok,
     socket
     |> assign_current_user_farm(session)
     |> assign(:page_title, gettext("Navigation Page"))}
  end
end
