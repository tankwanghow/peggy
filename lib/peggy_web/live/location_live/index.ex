defmodule PeggyWeb.LocationLive.Index do
  use PeggyWeb, :live_view
  alias Peggy.Farm

  on_mount PeggyWeb.OnMountFunc

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:locations, Farm.list_locations(socket.assigns.current_farm_user))
     |> assign(:page_title, gettext("Locations List"))
     |> assign(:changeset, new_changeset(socket))}
  end

  defp new_changeset(socket) do
    Farm.change_location(%Farm.Location{}, %{farm_id: socket.assigns.current_farm_user.farm_id})
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
     |> assign(:changeset, new_changeset(socket))}
  end

  @impl true
  def handle_event("delete_location", %{"id" => id}, socket) do
    case Farm.delete_location(Farm.get_location!(id), socket.assigns.current_farm_user) do
      {:ok, _} ->
        {
          :noreply,
          socket
          |> assign(:locations, Farm.list_locations(socket.assigns.current_farm_user))
          |> assign(:changeset, new_changeset(socket))
          |> put_flash(:success, gettext("Delete Location Successfully"))
        }

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           changeset.errors |> Enum.map(fn {_, {m, _}} -> m end) |> Enum.join(". ")
         )}

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

  defp create_location(attrs, socket) do
    case Farm.create_location(attrs, socket.assigns.current_farm_user) do
      {:ok, _} ->
        {
          :noreply,
          socket
          |> assign(:locations, Farm.list_locations(socket.assigns.current_farm_user))
          |> assign(:changeset, new_changeset(socket))
          |> put_flash(:success, gettext("Insert Location Successfully"))
        }

      {:error, changeset} ->
        {:noreply, socket |> assign(:changeset, changeset)}

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
      {:ok, _} ->
        {
          :noreply,
          socket
          |> assign(:locations, Farm.list_locations(socket.assigns.current_farm_user))
          |> assign(:changeset, new_changeset(socket))
          |> put_flash(:success, gettext("Update Location Successfully"))
        }

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:changeset, changeset)
         |> put_flash(
           :error,
           changeset.errors |> Enum.map(fn {_, {m, _}} -> m end) |> Enum.join(". ")
         )}

      {:error, changeset, msg} ->
        {:noreply,
         socket
         |> assign(:changeset, changeset)
         |> put_flash(:error, msg)}
    end
  end
end
