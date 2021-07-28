defmodule PeggyWeb.FarmLive.Index do
  use PeggyWeb, :live_view
  alias Peggy.Company

  @impl true
  def mount(_params, session, socket) do
    PeggyWeb.LiveHelpers.set_locale(session)
    socket = assign_current_user(socket, session)
    socket = assign(socket, :current_farm, session["current_farm"])
    
    farms = Company.list_farms(socket.assigns.current_user)

    title =
      if(Enum.count(farms) == 0,
        do: gettext("You have to Create a Farm to procced."),
        else:
          if(socket.assigns.current_farm == nil,
            do: gettext("Please select an active farm."),
            else: gettext("Farms Listing")
          )
      )

    {:ok,
     socket
     |> assign(:page_title, title)
     |> assign(:farms, farms)}
  end
end
