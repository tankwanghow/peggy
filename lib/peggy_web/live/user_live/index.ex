defmodule PeggyWeb.UserLive.Index do
  use PeggyWeb, :live_view
  alias Peggy.Sys

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-11/12 mx-auto">
      <p class="w-full text-2xl text-center font-bold"><%= @page_title %></p>
      <div class="flex justify-center gap-x-1">
        <.link navigate={~p"/farms/#{@current_farm.id}/users/new"} class="text-xl mb-2 blue button">
          🧑<%= gettext("Add User") %>
        </.link>
      </div>
      <%= for u <- @users do %>
        <.form
          :let={f}
          for={%{}}
          as={:user_list}
          id={"user-#{u.id}"}
          phx-change="update_role"
          autocomplete="off"
        >
          <div class="border-b-2 border-indigo-400 py-3 bg-indigo-100 text-center">
            <div class="email font-mono font-bold mb-4">
              <%= u.email %>

              <%= if u.email == @current_user.email do %>
                <%= gettext("is") %> <span class="text-amber-700"><%= u.role %></span>
              <% else %>
                <%= gettext("is") %>
                <%= Phoenix.HTML.Form.hidden_input(f, :id, value: u.id) %>
                <%= Phoenix.HTML.Form.select(f, :role, Peggy.Authorization.roles(),
                  class: "rounded py-[1px] pl-[2px] pr-[40px] border-0 bg-indigo-50",
                  value: u.role,
                  phx_page_loading: true
                ) %>
              <% end %>
            </div>
            <div id={"new_user_password_#{u.id}"} class="text-gray-500 mb-5">
              <%= if u.email != @current_user.email  do %>
                <%= if @new_password_id == u.id do %>
                  <span>Password reset to </span><span class="font-bold text-emerald-600"><%= @new_password %></span>
                <% else %>
                  <.link
                    id={"reset_user_password_#{u.id}"}
                    phx-click="reset_password"
                    phx-value-id={u.id}
                    class="blue button"
                  >
                    <span class="font-bold"><%= gettext("Reset Password") %></span>
                  </.link>
                <% end %>
              <% end %>
            </div>

            <.delete_confirm_modal
              id={"delete-object_#{u.id}"}
              msg1={gettext("Remove User from Farm.") <> " #{u.email}"}
              msg2={gettext("Cannot be recover.")}
              confirm={
                JS.push("delete_user", value: %{user_id: u.id})
                |> JS.hide(to: "#delete-object-modal")
              }
            />
          </div>
        </.form>
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("User List"))
     |> assign(:new_password_id, nil)
     |> assign(:new_password, nil)
     |> get_user_list()}
  end

  @impl true
  def handle_event("update_role", %{"user_list" => params}, socket) do
    case Sys.change_user_role_in(
           socket.assigns.current_farm,
           params["id"],
           params["role"],
           socket.assigns.current_user
         ) do
      {:ok, _cu} ->
        {:noreply,
         socket
         |> get_user_list()
         |> put_flash(
           :info,
           gettext("Successfully updated user role to ") <> params["role"]
         )}

      {:error, _cs} ->
        {:noreply,
         socket
         |> get_user_list()
         |> put_flash(
           :error,
           gettext("Failed to change user to ") <> params["role"]
         )}

      :not_authorise ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("You are not authorised to perform this action"))}
    end
  end

  @impl true
  def handle_event("reset_password", %{"id" => id}, socket) do
    user = Peggy.UserAccounts.get_user!(id)

    case Peggy.Sys.reset_user_password(
           user,
           socket.assigns.current_user,
           socket.assigns.current_farm
         ) do
      {:ok, user, pwd} ->
        {:noreply,
         socket
         |> assign(:new_password_id, user.id)
         |> assign(:new_password, pwd)}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           gettext("Failed Reset Password")
         )}

      :not_authorise ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("You are not authorised to perform this action"))}
    end
  end

  @impl true
  def handle_event("delete_user", %{"user_id" => id}, socket) do
    user = Peggy.UserAccounts.get_user!(id)

    case Peggy.Sys.delete_user_from_farm(
           socket.assigns.current_farm,
           user,
           socket.assigns.current_user
         ) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> push_navigate(to: ~p"/farms/#{socket.assigns.current_farm.id}/users")
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

  @impl true
  def handle_event("show_all", _, socket) do
    {:noreply, get_user_list(socket)}
  end

  @impl true
  def handle_event("show_active", _, socket) do
    {:noreply, get_user_list(socket)}
  end

  defp get_user_list(socket) do
    socket
    |> assign(
      :users,
      Sys.get_farm_users(socket.assigns.current_farm, socket.assigns.current_user)
    )
  end
end
