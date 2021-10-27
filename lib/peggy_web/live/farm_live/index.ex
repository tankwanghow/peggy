defmodule PeggyWeb.FarmLive.Index do
  use PeggyWeb, :live_view
  alias Peggy.Company

  on_mount PeggyWeb.OnMountFunc

  @impl true
  def mount(_params, _session, socket) do
    farms = Company.list_farms(socket.assigns.current_user)

    socket =
      if Enum.count(farms) == 0 do
        socket |> assign(:page_title, gettext("You have to Create a Farm to procced."))
      else
        if Util.attempt(socket.assigns, :current_farm_user) == nil do
          socket
          |> assign(:current_farm_user, nil)
          |> assign(:page_title, gettext("Please select an active farm."))
        else
          socket |> assign(:page_title, gettext("Farms Listing"))
        end
      end

    {:ok,
     socket
     |> assign(:farms, farms)}
  end

  @impl true
  def handle_event("set_default", %{"id" => farm_id}, socket) do
    Company.set_default_farm(socket.assigns.current_user.id, farm_id)

    {:noreply, socket |> assign(:farms, Company.list_farms(socket.assigns.current_user))}
  end
end
