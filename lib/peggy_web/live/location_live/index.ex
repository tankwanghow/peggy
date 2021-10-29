defmodule PeggyWeb.LocationLive.Index do
  use PeggyWeb, :live_view
  alias Peggy.Farm

  on_mount PeggyWeb.OnMountFunc

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:counter, 0)
     |> assign(page: 1, per_page: 10)
     |> assign(:page_title, gettext("Location List"))
     |> assign_search_terms()
     |> new_changeset()
     |> filter_locations(), temporary_assigns: [locations: []]}
  end

  @impl true
  def handle_event("search_location", %{"search" => params}, socket) do
    {:noreply,
     socket
     |> assign(page: 1, per_page: 10)
     |> assign_search_terms(params["terms"])
     |> assign(:counter, socket.assigns.counter + 1)
     |> filter_locations()}
  end

  @impl true
  def handle_event("validate", %{"location" => params}, socket) do
    changeset =
      if params["id"] != "" do
        Farm.change_location(Farm.get_location!(params["id"]), params)
        |> Map.put(:action, :update)
      else
        Farm.change_location(%Farm.Location{}, params) |> Map.put(:action, :insert)
      end

    {:noreply,
     socket
     |> assign(changeset: changeset)}
  end

  @impl true
  def handle_event("select_location", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(
       :changeset,
       Farm.change_location(Farm.get_location!(id)) |> Map.put(:action, :update)
     )}
  end

  @impl true
  def handle_event("clear_new", _params, socket) do
    {:noreply,
     socket
     |> new_changeset()}
  end

  @impl true
  def handle_event("delete_location", %{"id" => id}, socket) do
    case Farm.delete_location(Farm.get_location!(id), socket.assigns.current_farm_user) do
      {:ok, _} ->
        {
          :noreply,
          socket
          |> reset_locations()
          |> new_changeset()
          |> put_flash(:success, gettext("Delete Location Successfully"))
        }

      {:error, _location, msg} ->
        {:noreply, socket |> put_flash(:error, msg)}
    end
  end

  @impl true
  def handle_event("save", %{"location" => location}, socket) do
    if location["id"] == "" do
      create_location(location, socket)
    else
      update_location(location, socket)
    end
  end

  @impl true
  def handle_event("load-more", _, socket) do
    socket =
      socket
      |> update(:page, &(&1 + 1))
      |> filter_locations()

    {:noreply, socket}
  end

  defp create_location(attrs, socket) do
    case Farm.create_location(attrs, socket.assigns.current_farm_user) do
      {:ok, _location} ->
        {
          :noreply,
          socket
          |> reset_locations()
          |> new_changeset()
          |> put_flash(:success, gettext("Insert Location Successfully"))
        }

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:changeset, changeset)
         |> put_flash(
           :error,
           changeset.errors |> Enum.map(fn {k, {m, _}} -> "#{k} #{m}" end) |> Enum.join(". ")
         )}

      {:error, changeset, msg} ->
        {:noreply,
         socket
         |> assign(:changeset, changeset)
         |> put_flash(:error, msg)}
    end
  end

  defp update_location(attrs, socket) do
    case Farm.update_location(
           Farm.get_location!(attrs["id"]),
           attrs,
           socket.assigns.current_farm_user
         ) do
      {:ok, _location} ->
        {
          :noreply,
          socket
          |> reset_locations
          |> put_flash(:success, gettext("Update Location Successfully"))
        }

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:changeset, changeset)
         |> put_flash(
           :error,
           changeset.errors |> Enum.map(fn {k, {m, _}} -> "#{k} #{m}" end) |> Enum.join(". ")
         )}

      {:error, changeset, msg} ->
        {:noreply,
         socket
         |> assign(:changeset, changeset)
         |> put_flash(:error, msg)}
    end
  end

  defp assign_search_terms(socket, terms \\ "") do
    assign(socket, search: %{terms: terms})
  end

  defp new_changeset(socket) do
    assign(socket,
      changeset:
        Farm.change_location(%Farm.Location{}, %{
          farm_id: socket.assigns.current_farm_user.farm_id
        })
    )
  end

  defp filter_locations(socket) do
    locations =
      Farm.list_locations(socket.assigns.search.terms, socket.assigns.current_farm_user,
        page: socket.assigns.page,
        per_page: socket.assigns.per_page
      )

    assign(socket,
      locations: locations,
      locations_count: Enum.count(locations)
    )
  end

  defp reset_locations(socket) do
    socket
    |> assign(:counter, socket.assigns.counter + 1)
    |> assign(page: 1, per_page: 10)
    |> assign_search_terms()
    |> filter_locations()
  end
end
