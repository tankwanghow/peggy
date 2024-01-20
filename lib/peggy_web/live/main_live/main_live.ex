defmodule PeggyWeb.MainLive do
  use PeggyWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <p class="w-full text-3xl text-center font-medium"><%= @page_title %></p>
    <div class="mx-auto text-center">
      <div :if={@current_role == "admin"} class="font-medium text-xl">
        Administrator Functions
      </div>
      <div :if={@current_role == "admin"} class="mb-4 flex flex-wrap justify-center">
        <.link navigate={~p"/farms/#{@current_farm.id}/users"} class="nav-btn">
          <%= gettext("Users") %>
        </.link>
        <.link navigate={~p"/farms/#{@current_farm.id}/rouge_users"} class="nav-btn">
          <%= gettext("Rouge Users") %>
        </.link>
      </div>
      </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:back_to_route, "#") |> assign(page_title: gettext("Main"))}
  end
end
