defmodule PeggyWeb.FarmLiveIndex do
  use PeggyWeb, :live_view
  alias Peggy.Sys

  @impl true
  def render(assigns) do
    ~H"""
    <p class="w-full text-3xl text-center font-medium"><%= @page_title %></p>
    <div id="farms_list" class="max-w-2xl mx-auto">
      <%= for c <- @farms do %>
        <div
          id={"farm-#{c.farm_id}"}
          class={"#{shake(c.updated_at, 2)} bg-green-200 p-3 m-2 border-y-2 border-green-500 text-center"}
        >
          <%= if Peggy.Authorization.can?(@current_user, :update_farm, c) do %>
            <.link
              navigate={~p"/edit_farm/#{c.farm_id}"}
              class="text-blue-800 text-3xl font-bold"
            >
              <%= c.name %>
            </.link>
          <% else %>
            <div class="text-3xl font-bold">
              <%= c.name %>
            </div>
          <% end %>
          <div class="text-xl">
            <%= [
              c.address1,
              c.address2,
              c.city,
              c.zipcode,
              c.state,
              c.country,
              c.tel,
              c.email
            ]
            |> Enum.reject(fn x -> is_nil(x) end)
            |> Enum.join(", ") %>
          </div>
          <div class="text-amber-700 font-semibold mb-2 text-xl">
            <%= gettext("Your are ") %><span class="text-red-500"><%= c.role %></span><%= gettext(
              " in this farm"
            ) %>
          </div>

          <%= if Util.attempt(assigns[:current_farm], :id) != c.farm_id do %>
            <.link
              class="set-active blue button mx-2"
              phx-value-id={c.farm_id}
              navigate={~p"/farms/#{c.farm_id}/main"}
            >
              <%= gettext("Set Active") %>
            </.link>
          <% else %>
            <span class="text-xl px-2 py-1 bg-cyan-300 mx-2">
              <%= gettext("Is Active Farm") %>
            </span>
          <% end %>

          <%= if !c.default_farm do %>
            <.link
              class="set-default blue button mx-2"
              phx-value-id={c.farm_id}
              phx-click="set_default"
            >
              <%= gettext("Set Default") %>
            </.link>
          <% else %>
            <span class="text-xl px-2 py-1 bg-cyan-300 mx-2">
              <%= gettext("Is Default Farm") %>
            </span>
          <% end %>
        </div>
      <% end %>
    </div>
    <div class="text-center">
      <.link
        navigate={~p"/farms/new"}
        class="border-2 border-amber-500 rounded-md text-center text-2xl px-2 py-1 bg-amber-200"
      >
        <%= gettext("Create a New Farm") %>
      </.link>
    </div>
    """
  end

  @impl true
  def mount(_params, session, socket) do
    farms = Sys.list_farms(socket.assigns.current_user)

    socket =
      socket
      |> assign(:page_title, gettext("Farm Listing"))
      |> assign(:current_farm, session["current_farm"])
      |> assign(:current_role, session["current_role"])

    {:ok,
     socket
     |> assign(:farms, farms)}
  end

  @impl true
  def handle_event("set_default", %{"id" => farm_id}, socket) do
    Sys.set_default_farm(socket.assigns.current_user.id, farm_id)

    {:noreply, socket |> assign(:farms, Sys.list_farms(socket.assigns.current_user))}
  end
end
