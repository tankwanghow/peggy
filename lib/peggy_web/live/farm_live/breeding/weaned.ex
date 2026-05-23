defmodule PeggyWeb.FarmLive.Breeding.Weaned do
  @moduledoc """
  Weaned tab of the Breeding section. Lists recent weanings with a
  soft-delete action.
  """
  use PeggyWeb, :live_view

  alias Peggy.{Breeding, Policy}
  alias PeggyWeb.FarmLive.Breeding.Shared

  @per_page Shared.per_page()

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-6xl">
        <.header>
          {gettext("Weaned")}
          <:subtitle>{gettext("Recently weaned litters")}</:subtitle>
        </.header>

        <section class="mt-4">
          <form
            id="weaned-filters"
            phx-change="filter_weaned"
            phx-submit="filter_weaned"
            class="flex flex-wrap gap-3 items-end"
          >
            <label class="form-control w-full sm:w-56">
              <div class="label py-1">
                <span class="label-text text-xs">{gettext("Search sow tag")}</span>
              </div>
              <input
                type="text"
                name="q"
                value={@filters.q}
                phx-debounce="300"
                placeholder={gettext("e.g. 1234")}
                class="input input-sm input-bordered font-mono"
              />
            </label>

            <label class="form-control w-40">
              <div class="label py-1">
                <span class="label-text text-xs">{gettext("Weaned from")}</span>
              </div>
              <input
                type="date"
                name="weaned_from"
                value={@filters.weaned_from}
                class="input input-sm input-bordered"
              />
            </label>

            <label class="form-control w-40">
              <div class="label py-1">
                <span class="label-text text-xs">{gettext("Weaned to")}</span>
              </div>
              <input
                type="date"
                name="weaned_to"
                value={@filters.weaned_to}
                class="input input-sm input-bordered"
              />
            </label>
          </form>

          <div class="mt-4 overflow-x-auto">
            <table class="table table-sm w-full">
              <thead class="text-left text-base-content/60">
                <tr>
                  <th class="py-2">{gettext("Sow")}</th>
                  <th class="py-2">{gettext("Weaned at")}</th>
                  <th class="py-2 text-right">{gettext("Weaned count")}</th>
                  <th class="py-2 text-right">
                    {gettext("Avg wt (%{u})", u: Peggy.Units.weight_g_unit(@current_scope))}
                  </th>
                  <th class="py-2">{gettext("Batch")}</th>
                  <th class="py-2">{gettext("Dest. pen")}</th>
                  <th :if={@can_record} class="py-2"></th>
                </tr>
              </thead>
              <tbody id="weaned-rows" phx-update="stream">
                <tr
                  :for={{dom_id, w} <- @streams.weaned}
                  id={dom_id}
                  class="border-t border-base-200"
                >
                  <td class="py-2 font-mono font-semibold">
                    {w.farrowing && w.farrowing.sow && w.farrowing.sow.ear_tag}
                  </td>
                  <td class="py-2">{w.weaned_at}</td>
                  <td class="py-2 text-right">{w.weaned_count}</td>
                  <td class="py-2 text-right">
                    {Peggy.Units.format_weight_g(w.avg_wean_weight_g, @current_scope)}
                  </td>
                  <td class="py-2 font-mono">
                    <.link
                      :if={w.batch_animal}
                      navigate={~p"/farms/#{@current_scope.farm.slug}/animals/#{w.batch_animal.id}"}
                      class="text-primary underline underline-offset-2 decoration-dotted hover:decoration-solid"
                    >
                      {w.batch_animal.ear_tag}
                    </.link>
                  </td>
                  <td class="py-2 font-mono">
                    {w.destination_pen &&
                      "#{w.destination_pen.house.code}-#{w.destination_pen.code}"}
                  </td>
                  <td :if={@can_record} class="py-2 text-right">
                    <button
                      phx-click="delete_weaning"
                      phx-value-weaning-id={w.id}
                      data-confirm={
                        gettext("Delete this weaning? The litter batch and sow will be reverted.")
                      }
                      class="btn btn-ghost btn-sm text-error/70"
                      title={gettext("Delete weaning")}
                    >
                      <.icon name="hero-trash" class="size-4" />
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
            <p :if={@total == 0} class="mt-2 text-sm text-base-content/60">
              {gettext("No weanings match the filters.")}
            </p>
          </div>

          <.infinite_scroll has_more={@has_more} total={@total} id="weaned-sentinel" />
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     socket
     |> assign(
       can_record: Policy.can?(scope, :record_breeding),
       per_page: @per_page,
       page: 1,
       total: 0,
       has_more: false
     )
     |> stream_configure(:weaned, dom_id: &"weaning-#{&1.id}")
     |> stream(:weaned, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = %{
      q: params["q"] || "",
      weaned_from: params["weaned_from"] || "",
      weaned_to: params["weaned_to"] || ""
    }

    {:noreply,
     socket
     |> assign(filters: filters)
     |> load_rows()}
  end

  @impl true
  def handle_event("filter_weaned", params, socket) do
    query = %{
      "q" => params["q"] || "",
      "weaned_from" => params["weaned_from"] || "",
      "weaned_to" => params["weaned_to"] || "",
      "page" => 1
    }

    {:noreply, push_patch(socket, to: Shared.tab_path(socket, "weaned", query))}
  end

  def handle_event("load_more", _, socket), do: {:noreply, append_rows(socket)}

  def handle_event("delete_weaning", %{"weaning-id" => id}, socket) do
    scope = socket.assigns.current_scope

    if socket.assigns.can_record do
      weaning = Breeding.get_weaning!(scope, String.to_integer(id))

      case Breeding.delete_weaning(scope, weaning) do
        {:ok, _} ->
          {:noreply,
           socket
           |> load_rows()
           |> put_flash(:info, gettext("Weaning deleted. Restore from the Deleted tab."))}

        {:error, :weaning_has_activity} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("Cannot delete — the litter has moved or changed since weaning.")
           )}

        {:error, :already_deleted} ->
          {:noreply, put_flash(socket, :error, gettext("Weaning is already deleted."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not delete weaning."))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  defp load_rows(socket) do
    scope = socket.assigns.current_scope

    opts = list_opts(socket, 0)
    rows = Breeding.list_recent_weanings(scope, opts)
    total = Breeding.count_recent_weanings(scope, opts)

    socket
    |> assign(total: total, page: 1, has_more: length(rows) < total)
    |> stream(:weaned, rows, reset: true)
  end

  defp append_rows(socket) do
    scope = socket.assigns.current_scope
    next_page = socket.assigns.page + 1
    offset = (next_page - 1) * @per_page

    opts = list_opts(socket, offset)
    rows = Breeding.list_recent_weanings(scope, opts)
    loaded = next_page * @per_page

    socket =
      Enum.reduce(rows, socket, fn row, acc -> stream_insert(acc, :weaned, row) end)

    assign(socket, page: next_page, has_more: loaded < socket.assigns.total)
  end

  defp list_opts(socket, offset) do
    f = socket.assigns.filters

    [
      search: f.q,
      weaned_from: blank_to_nil(f.weaned_from),
      weaned_to: blank_to_nil(f.weaned_to),
      limit: @per_page,
      offset: offset
    ]
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(v), do: v
end
