defmodule PeggyWeb.FarmLive.Index do
  use PeggyWeb, :live_view
  alias Peggy.Company

  on_mount PeggyWeb.OnMountFunc

  @impl true
  def mount(_params, _session, socket) do
    farms = Company.list_farms(socket.assigns.current_user)

    title =
      if(Enum.count(farms) == 0,
        do: gettext("You have to Create a Farm to procced."),
        else:
          if(socket.assigns.current_farm_user == nil,
            do: gettext("Please select an active farm."),
            else: gettext("Farms Listing")
          )
      )

    {:ok,
     socket
     |> assign(:page_title, title)
     |> assign(:farms, farms)}
  end

  @impl true
  def handle_event("set_default", %{"id" => farm_id}, socket) do
    Company.set_default_farm(socket.assigns.current_user.id, farm_id)

    {:noreply, socket |> assign(:farms, Company.list_farms(socket.assigns.current_user))}
  end
end
