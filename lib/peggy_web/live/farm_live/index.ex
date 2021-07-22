defmodule PeggyWeb.FarmLive.Index do
  use PeggyWeb, :live_view
  alias Peggy.Company

  @impl true
  def mount(_params, session, socket) do
    PeggyWeb.LiveHelpers.set_locale(session)
    socket = assign_current_user(socket, session)

    {:ok, socket
          |> assign(:page_title, gettext("Farms Listing"))
          |> assign(:farms, Company.list_farms(socket.assigns.current_user))}
  end
end
