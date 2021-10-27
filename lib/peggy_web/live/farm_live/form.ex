defmodule PeggyWeb.FarmLive.Form do
  use PeggyWeb, :live_view
  alias Peggy.Company
  alias Peggy.Company.Farm

  on_mount PeggyWeb.OnMountFunc

  @impl true
  def mount(params, _session, socket) do
    case socket.assigns.live_action do
      :new -> mount_new(socket)
      :edit -> mount_edit(params, socket)
    end
  end

  defp mount_new(socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Please Create a Farm."))
     |> assign(:changeset, Company.change_farm(%Farm{}, %{}, socket.assigns.current_user))}
  end

  defp mount_edit(%{"id" => id}, socket) do
    farm = Company.get_farm!(id, socket.assigns.current_user)
    changeset = Company.change_farm(farm, %{}, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, gettext("Editing Farm."))
     |> assign(:changeset, changeset)
     |> assign(:farm, farm)}
  end

  @impl true
  def handle_event("validate", %{"farm" => params}, socket) do
    farm = if(socket.assigns[:farm], do: socket.assigns.farm, else: %Farm{})

    changeset =
      farm
      |> Company.change_farm(params, socket.assigns.current_user)
      |> Map.put(:action, :insert)

    socket = assign(socket, changeset: changeset)

    {:noreply, socket}
  end

  @impl true
  def handle_event("save", %{"farm" => farm_params}, socket) do
    save_farm(socket, socket.assigns.live_action, farm_params)
  end

  @impl true
  def handle_event("delete", _params, socket) do
    deleted_redirect_to =
      if(Util.attempt(socket.assigns, :current_farm_user),
        do:
          if(socket.assigns.current_farm_user.farm_id == socket.assigns.farm.id,
            do: "/clear_set_active_farm",
            else: "/farms"
          ),
        else: "/farms"
      )

    case Company.delete_farm(socket.assigns.farm, socket.assigns.current_user) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:success, gettext("Farm Deleted successfully"))
         |> push_redirect(to: deleted_redirect_to)}

      {:error, farm, msg} ->
        changeset = Company.change_farm(farm, %{}, socket.assigns.current_user)

        {:noreply,
         assign(socket, :changeset, changeset)
         |> put_flash(
           :error,
           msg <> " " <> gettext("Failed to Delete Farm")
         )}
    end
  end

  defp save_farm(socket, :edit, farm_params) do
    update_redirect_to =
      if(Util.attempt(socket.assigns, :current_farm_user),
        do:
          if(socket.assigns.current_farm_user.farm_id == socket.assigns.farm.id,
            do: "/update_active_farm?id=#{socket.assigns.farm.id}",
            else: "/farms"
          ),
        else: "/farms"
      )

    case Company.update_farm(socket.assigns.farm, farm_params, socket.assigns.current_user) do
      {:ok, farm} ->
        {:noreply,
         socket
         |> put_flash(:scroll_to_here_farm_id, farm.id)
         |> put_flash(:success, gettext("Farm updated successfully"))
         |> push_redirect(to: update_redirect_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}

      {:error, farm, msg} ->
        changeset = Company.change_farm(farm, %{}, socket.assigns.current_user)

        {:noreply,
         assign(socket, :changeset, changeset)
         |> put_flash(
           :error,
           msg <> " " <> gettext("Failed to Update Farm")
         )}
    end
  end

  defp save_farm(socket, :new, farm_params) do
    case Company.create_farm(farm_params, socket.assigns.current_user) do
      {:ok, farm} ->
        {:noreply,
         socket
         |> put_flash(:scroll_to_here_farm_id, farm.id)
         |> put_flash(:success, gettext("Farm created successfully"))
         |> push_redirect(to: "/farms")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end
end
