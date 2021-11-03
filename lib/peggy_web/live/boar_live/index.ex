defmodule PeggyWeb.BoarLive.Index do
  use PeggyWeb, :live_view
  alias Peggy.Breeder

  on_mount PeggyWeb.OnMountFunc
  @per_page 20

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:counter, 0)
     |> assign(page: 1, per_page: @per_page)
     |> assign(:page_title, gettext("Boar Listing"))
     |> assign_search_terms()
     |> new_changeset()
     |> filter_boars(), temporary_assigns: [boars: []]}
  end

  @impl true
  def handle_event("search_boar", %{"search" => params}, socket) do
    {:noreply,
     socket
     |> assign(page: 1, per_page: @per_page)
     |> assign_search_terms(params["terms"])
     |> assign(:counter, socket.assigns.counter + 1)
     |> filter_boars()}
  end

  @impl true
  def handle_event("validate", %{"boar" => params}, socket) do
    changeset =
      if params["id"] != "" do
        Breeder.change_boar(Breeder.get_boar!(params["id"]), params)
        |> Map.put(:action, :update)
      else
        Breeder.change_boar(%Breeder.Boar{}, socket.assigns.current_farm_user, params)
        |> Map.put(:action, :insert)
      end

    {:noreply,
     socket
     |> assign(changeset: changeset)}
  end

  @impl true
  def handle_event("select_boar", %{"id" => id}, socket) do
    {:noreply,
     assign(
       socket,
       :changeset,
       Breeder.change_boar(Breeder.get_boar!(id), socket.assigns.current_farm_user)
       |> Map.put(:action, :update)
     )}
  end

  @impl true
  def handle_event("clear_new", _params, socket) do
    {:noreply,
     socket
     |> new_changeset()}
  end

  @impl true
  def handle_event("delete_boar", %{"id" => id}, socket) do
    case Breeder.delete_boar(Breeder.get_boar!(id), socket.assigns.current_farm_user) do
      {:ok, _} ->
        {
          :noreply,
          socket
          |> reset_boars()
          |> new_changeset()
          |> put_flash(:success, gettext("Delete Boar Successfully"))
        }

      {:error, _location, msg} ->
        {:noreply, socket |> put_flash(:error, msg)}
    end
  end

  @impl true
  def handle_event("save", %{"boar" => boar}, socket) do
    if boar["id"] == "" do
      create_boar(boar, socket)
    else
      update_boar(boar, socket)
    end
  end

  @impl true
  def handle_event("load-more", _, socket) do
    socket =
      socket
      |> update(:page, &(&1 + 1))
      |> filter_boars()

    {:noreply, socket}
  end

  defp create_boar(attrs, socket) do
    case Breeder.create_boar(attrs, socket.assigns.current_farm_user) do
      {:ok, _boar} ->
        {
          :noreply,
          socket
          |> reset_boars()
          |> new_changeset()
          |> put_flash(:success, gettext("Insert Boar Successfully"))
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

  defp update_boar(attrs, socket) do
    case Breeder.update_boar(
           Breeder.get_boar!(attrs["id"]),
           attrs,
           socket.assigns.current_farm_user
         ) do
      {:ok, _boar} ->
        {
          :noreply,
          socket
          |> reset_boars
          |> put_flash(:success, gettext("Update Boar Successfully"))
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
        Breeder.change_boar(%Breeder.Boar{}, socket.assigns.current_farm_user, %{
          farm_id: socket.assigns.current_farm_user.farm_id
        })
    )
  end

  defp filter_boars(socket) do
    boars =
      Breeder.list_boars(socket.assigns.search.terms, socket.assigns.current_farm_user,
        page: socket.assigns.page,
        per_page: socket.assigns.per_page
      )

    assign(socket,
      boars: boars,
      boars_count: Enum.count(boars)
    )
  end

  defp reset_boars(socket) do
    socket
    |> assign(:counter, socket.assigns.counter + 1)
    |> assign(page: 1, per_page: @per_page)
    |> assign_search_terms()
    |> new_changeset()
    |> filter_boars()
  end
end
