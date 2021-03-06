defmodule PeggyWeb.UserLive.Index do
  use PeggyWeb, :live_view
  alias Peggy.Company

  on_mount PeggyWeb.OnMountFunc

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("User List"))
     |> get_user_list}
  end

  @impl true
  def handle_event("update_role", params, socket) do
    user = target_user(params)

    if user do
      p = params[user]
      {user_id, _} = Integer.parse(p["id"])

      case Company.change_user_role_in_farm(
             user_id,
             p["role"],
             socket.assigns.current_farm_user
           ) do
        {:ok, _farm_user} ->
          {:noreply,
           socket
           |> get_user_list()
           |> put_flash(
             :success,
             gettext("Successfully updated user role to ") <> p["role"]
           )}

        {:error, %Ecto.Changeset{}, message} ->
          {:noreply,
           socket
           |> get_user_list()
           |> put_flash(
             :error,
             message <> " " <> gettext("Failed to change user to ") <> p["role"]
           )}
      end
    else
      {:noreply, socket}
    end
  end

  defp get_user_list(socket) do
    socket
    |> assign(
      :users,
      Company.farm_users(socket.assigns.current_farm_user)
    )
  end

  defp target_user(params) do
    targets = params["_target"]

    if Enum.find(targets, nil, fn v -> v == "role" end) do
      Enum.find(targets, nil, fn v -> v =~ "user_" end)
    else
      nil
    end
  end
end
