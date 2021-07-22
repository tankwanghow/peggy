defmodule PeggyWeb.FarmLive.Form do
  use PeggyWeb, :live_view
  alias Peggy.Company
  alias Peggy.Company.Farm

  @impl true
  def mount(params, session, socket) do
    PeggyWeb.LiveHelpers.set_locale(session)
    socket = assign_current_user(socket, session)

    case socket.assigns.live_action do
      :new -> mount_new(socket)
      :edit -> mount_edit(params, socket)
    end
  end

  defp mount_new(socket) do
    {:ok, socket
          |> assign(:page_title, gettext("Please Create a Farm."))
          |> assign(:changeset, Company.change_farm(%Farm{}, %{}, socket.assigns.current_user))}
  end

  defp mount_edit(%{"id" => id}, socket) do
    farm = Company.get_farm!(id, socket.assigns.current_user)
    changeset = Company.change_farm(farm, %{}, socket.assigns.current_user)

    {:ok, socket
          |> assign(:page_title, gettext("Editing Farm."))
          |> assign(:changeset, changeset)
          |> assign(:farm, farm)}
  end


  @impl true
  def handle_event("validate", %{"farm" => params}, socket) do
    changeset =
      %Farm{}
      |> Company.change_farm(params, socket.assigns.current_user)
      |> Map.put(:action, :insert)

    socket = assign(socket, changeset: changeset)

    {:noreply, socket}
  end

  def handle_event("save", %{"farm" => farm_params}, socket) do
    IO.inspect(socket)
    save_farm(socket, socket.assigns.live_action, farm_params)
  end

  defp save_farm(socket, :edit, farm_params) do
    IO.inspect(socket)
    case Company.update_farm(socket.assigns.farm, farm_params, socket.assigns.current_user) do
      {:ok, farm} ->
        {:noreply,
         socket
         |> put_flash(:scroll_to_here_farm_id, farm.id)
         |> put_flash(:success, gettext("Farm updated successfully"))
         |> push_redirect(to: "/farms")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
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
