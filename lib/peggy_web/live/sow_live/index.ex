defmodule PeggyWeb.SowLive.Index do
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
     |> assign(:page_title, gettext("Sow Listing"))
     |> assign_search_terms()
     |> new_changeset()
     |> filter_sows(), temporary_assigns: [sows: []]}
  end

  @impl true
  def handle_event("search_sow", %{"search" => params}, socket) do
    {:noreply,
     socket
     |> assign(page: 1, per_page: @per_page)
     |> assign_search_terms(params["terms"])
     |> assign(:counter, socket.assigns.counter + 1)
     |> filter_sows()}
  end

  @impl true
  def handle_event("validate", %{"sow" => params}, socket) do
    changeset =
      if params["id"] != "" do
        Breeder.change_sow(Breeder.get_sow!(params["id"]), params)
        |> Map.put(:action, :update)
      else
        Breeder.change_sow(%Breeder.Sow{}, socket.assigns.current_farm_user, params)
        |> Map.put(:action, :insert)
      end

    {:noreply,
     socket
     |> assign(changeset: changeset)}
  end

  @impl true
  def handle_event("select_sow", %{"id" => id}, socket) do
    socket = socket
     |> assign(
       :changeset,
       Breeder.change_sow(Breeder.get_sow!(id), socket.assigns.current_farm_user)
       |> Map.put(:action, :update)
     )
     IO.inspect(socket.assigns.changeset.data)
    {:noreply, socket
     }
  end

  @impl true
  def handle_event("clear_new", _params, socket) do
    {:noreply,
     socket
     |> new_changeset()}
  end

  @impl true
  def handle_event("delete_sow", %{"id" => id}, socket) do
    case Breeder.delete_sow(Breeder.get_sow!(id), socket.assigns.current_farm_user) do
      {:ok, _} ->
        {
          :noreply,
          socket
          |> reset_sows()
          |> new_changeset()
          |> put_flash(:success, gettext("Delete Sow Successfully"))
        }

      {:error, _location, msg} ->
        {:noreply, socket |> put_flash(:error, msg)}
    end
  end

  @impl true
  def handle_event("save", %{"sow" => sow}, socket) do
    if sow["id"] == "" do
      create_sow(sow, socket)
    else
      update_sow(sow, socket)
    end
  end

  @impl true
  def handle_event("load-more", _, socket) do
    socket =
      socket
      |> update(:page, &(&1 + 1))
      |> filter_sows()

    {:noreply, socket}
  end

  defp create_sow(attrs, socket) do
    case Breeder.create_sow(attrs, socket.assigns.current_farm_user) do
      {:ok, _sow} ->
        {
          :noreply,
          socket
          |> reset_sows()
          |> new_changeset()
          |> put_flash(:success, gettext("Insert Sow Successfully"))
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

  defp update_sow(attrs, socket) do
    case Breeder.update_sow(
           Breeder.get_sow!(attrs["id"]),
           attrs,
           socket.assigns.current_farm_user
         ) do
      {:ok, _sow} ->
        {
          :noreply,
          socket
          |> reset_sows
          |> put_flash(:success, gettext("Update Sow Successfully"))
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
        Breeder.change_sow(%Breeder.Sow{}, socket.assigns.current_farm_user, %{
          farm_id: socket.assigns.current_farm_user.farm_id
        })
    )
  end

  defp filter_sows(socket) do
    sows =
      Breeder.list_sows(socket.assigns.search.terms, socket.assigns.current_farm_user,
        page: socket.assigns.page,
        per_page: socket.assigns.per_page
      )

    assign(socket,
      sows: sows,
      sows_count: Enum.count(sows)
    )
  end

  defp reset_sows(socket) do
    socket
    |> assign(:counter, socket.assigns.counter + 1)
    |> assign(page: 1, per_page: @per_page)
    |> assign_search_terms()
    |> new_changeset()
    |> filter_sows()
  end
end
