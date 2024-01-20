defmodule PeggyWeb.UserLive.RougeUserIndex do
  use PeggyWeb, :live_view
  alias Peggy.Sys

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-6/12 mx-auto">
      <p class="w-full text-2xl text-center font-bold"><%= @page_title %></p>
      <div :if={@users == []} class="border-b border-indigo-400 py-3 m-2 bg-indigo-100 text-center">
        No Rouge User Found!!
      </div>
      <%= for u <- @users do %>
        <div class="shadow py-3 m-2 rounded bg-indigo-100 text-center">
          <.delete_confirm_modal
            id={"delete-object_#{u.id}"}
            msg1={gettext("Remove User from Farm.") <> " #{u.email}"}
            msg2={gettext("Cannot be recover.")}
            confirm={
              JS.push("delete_user", value: %{user_id: u.id})
              |> JS.hide(to: "#delete-object-modal")
            }
          />
          <span class="email font-mono font-bold"><%= u.email %></span>
          <span>
            created at <%= PeggyWeb.Helpers.format_datetime(u.inserted_at, @current_farm) %>
          </span>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Rouge User List"))
     |> assign(:new_password_id, nil)
     |> assign(:new_password, nil)
     |> get_user_list()}
  end

  @impl true
  def handle_event("delete_user", %{"user_id" => id}, socket) do
    user = Peggy.UserAccounts.get_user!(id)

    case Peggy.Sys.delete_rouge_user(
           socket.assigns.current_farm,
           user,
           socket.assigns.current_user
         ) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> push_navigate(to: ~p"/farms/#{socket.assigns.current_farm.id}/rouge_users")
         |> put_flash(:info, gettext("User Deleted!!"))}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Failed to Delete User"))}

      :not_authorise ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("You are not authorised to perform this action"))}
    end
  end

  defp get_user_list(socket) do
    socket
    |> assign(
      :users,
      Sys.get_rouge_users(socket.assigns.current_farm, socket.assigns.current_user)
    )
  end
end
