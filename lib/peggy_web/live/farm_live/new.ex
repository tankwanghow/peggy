defmodule PeggyWeb.FarmLive.New do
  use PeggyWeb, :live_view
  alias Peggy.Company
  alias Peggy.Company.Farm

  @impl true
  def mount(_params, session, socket) do
    PeggyWeb.LiveHelpers.set_locale(session)

    socket = socket
    |> assign(:page_title, "New Farm")
    |> assign(:changeset, Company.change_farm(%Farm{}))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"farm" => params}, socket) do
    changeset =
      %Farm{}
      |> Company.change_farm(params)
      |> Map.put(:action, :insert)

    socket = assign(socket, changeset: changeset)

    {:noreply, socket}
  end

  def handle_event("save", %{"farm" => farm_params}, socket) do
    save_farm(socket, socket.assigns.live_action, farm_params)
  end

  defp save_farm(socket, :edit, farm_params) do
    case Company.update_farm(socket.assigns.farm, farm_params) do
      {:ok, _farm} ->
        {:noreply,
         socket
         |> put_flash(:info, "Farm updated successfully")}
        #  |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp save_farm(socket, :new, farm_params) do
    case Company.create_farm(farm_params) do
      {:ok, _farm} ->
        {:noreply,
         socket
         |> put_flash(:info, "Farm created successfully")}
        #  |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  # @impl true
  # def handle_params(params, _url, socket) do
  #   {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  # end

  # defp apply_action(socket, :edit, %{"id" => id}) do
  #   socket
  #   |> assign(:page_title, "Edit Farm")
  #   |> assign(:farm, Company.get_farm!(id))
  # end

  # defp apply_action(socket, :new, _params) do
  #   socket
  #   |> assign(:page_title, "New Farm")
  #   |> assign(:farm, %Farm{})
  # end

  # defp apply_action(socket, :index, _params) do
  #   socket
  #   |> assign(:page_title, "Listing Farms")
  #   |> assign(:farm, nil)
  # end

  # @impl true
  # def handle_event("delete", %{"id" => id}, socket) do
  #   farm = Company.get_farm!(id)
  #   {:ok, _} = Company.delete_farm(farm)

  #   {:noreply, assign(socket, :farms, list_farms())}
  # end

  # defp list_farms do
  #   Company.list_farms()
  # end
end
