defmodule PeggyWeb.NavigationLive.Index do
  use PeggyWeb, :live_view

  on_mount PeggyWeb.OnMountFunc

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Navigation Page"))}
  end
end
