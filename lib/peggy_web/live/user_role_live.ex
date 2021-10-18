defmodule PeggyWeb.UserRoleLive do
  use PeggyWeb, :live_view_without_layout
  alias Phoenix.PubSub

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket), do: PubSub.subscribe(Peggy.PubSub, "user_role_updated")
    socket = assign_current_user_farm(socket, session)

    {:ok, socket}
  end

  @impl true
  def handle_info({:log_out_user, data = %{}}, socket) do
    if data.farm_id == socket.assigns.current_farm_user.farm_id and
         data.user_id == socket.assigns.current_farm_user.user_id do
      {:noreply,
       socket
       |> redirect(to: Routes.user_session_path(socket, :force_logout))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    (<%= Util.attempt(@current_farm_user, :role) %>)
    """
  end
end
