defmodule PeggyWeb.FarmLive.BatchFarrowing do
  @moduledoc """
  Spreadsheet-style batch entry for recording multiple farrowings at
  once in one atomic commit. Pre-loads currently-gestating sows so the
  user picks a sow (resolved to its open service) per row.
  """
  use PeggyWeb, :live_view

  alias Peggy.{Breeding, Locations, Policy}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-7xl">
        <div class="text-sm text-base-content/60 mb-1">
          <.link
            navigate={~p"/farms/#{@current_scope.farm.slug}/breeding"}
            class="text-primary underline hover:text-primary/80"
          >
            ← {gettext("Breeding")}
          </.link>
        </div>

        <.header>
          {gettext("Batch Farrowing Entry")}
          <:subtitle>{gettext("Record multiple farrowings at once")}</:subtitle>
        </.header>

        <p :if={@sow_items == []} class="mt-6 text-sm text-base-content/60">
          {gettext("No gestating sows. Record a service first.")}
        </p>

        <section :if={@sow_items != []} class="mt-6">
          <form
            id="batch-farrowing-grid"
            phx-change="update"
            phx-submit="commit"
            phx-debounce="300"
          >
            <table class="table table-sm w-full text-sm">
              <thead class="text-left text-base-content/60">
                <tr>
                  <th class="py-2 w-8">#</th>
                  <th class="py-2 min-w-[10rem]">{gettext("Sow")}</th>
                  <th class="py-2 min-w-[9rem]">{gettext("Farrowed at")}</th>
                  <th class="py-2 min-w-[10rem]">{gettext("Pen")}</th>
                  <th class="py-2 w-20 text-right">{gettext("Born alive")}</th>
                  <th class="py-2 w-20 text-right">{gettext("Stillborn")}</th>
                  <th class="py-2 w-20 text-right">{gettext("Mummified")}</th>
                  <th class="py-2 w-24 text-right">{gettext("Wt (g)")}</th>
                  <th class="py-2 w-10"></th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={{row, i} <- Enum.with_index(@rows)}
                  class={[
                    "border-t border-base-200 align-top",
                    @error_index == i && "bg-error/10"
                  ]}
                >
                  <td class="py-1 px-1 text-base-content/60">{i + 1}</td>
                  <td class="py-1 px-1">
                    <.autocomplete
                      id={"row-#{row.tmp_id}-sow"}
                      label=""
                      name={"rows[#{row.tmp_id}][service_id]"}
                      value={row.service_id}
                      items={@sow_items}
                      selected_label={row.sow_label}
                      class="input w-full font-mono"
                      placeholder={gettext("Ear tag...")}
                    />
                  </td>
                  <td class="py-1 px-1">
                    <input
                      type="date"
                      name={"rows[#{row.tmp_id}][farrowed_at]"}
                      value={row.farrowed_at}
                      class="input w-full"
                    />
                  </td>
                  <td class="py-1 px-1">
                    <.autocomplete
                      id={"row-#{row.tmp_id}-pen"}
                      label=""
                      name={"rows[#{row.tmp_id}][pen_id]"}
                      value={row.pen_id}
                      items={@pen_items}
                      selected_label={row.pen_label}
                      class="input w-full font-mono"
                      placeholder={gettext("Pen...")}
                    />
                  </td>
                  <td class="py-1 px-1">
                    <input
                      type="number"
                      min="0"
                      name={"rows[#{row.tmp_id}][born_alive]"}
                      value={row.born_alive}
                      class="input w-full text-right"
                    />
                  </td>
                  <td class="py-1 px-1">
                    <input
                      type="number"
                      min="0"
                      name={"rows[#{row.tmp_id}][stillborn]"}
                      value={row.stillborn}
                      class="input w-full text-right"
                    />
                  </td>
                  <td class="py-1 px-1">
                    <input
                      type="number"
                      min="0"
                      name={"rows[#{row.tmp_id}][mummified]"}
                      value={row.mummified}
                      class="input w-full text-right"
                    />
                  </td>
                  <td class="py-1 px-1">
                    <input
                      type="number"
                      min="0"
                      name={"rows[#{row.tmp_id}][total_birth_weight_g]"}
                      value={row.total_birth_weight_g}
                      class="input w-full text-right"
                    />
                  </td>
                  <td class="py-1 px-1 text-right">
                    <button
                      type="button"
                      phx-click="remove_row"
                      phx-value-id={row.tmp_id}
                      class="btn btn-ghost btn-xs"
                      title={gettext("Remove row")}
                    >
                      ×
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>

            <p :if={@error_message} class="mt-3 text-sm text-error">
              {@error_message}
            </p>

            <div class="mt-4 flex flex-wrap gap-2 items-center">
              <button type="button" phx-click="add_row" class="btn btn-sm">
                + {gettext("Add row")}
              </button>
              <button
                type="button"
                phx-click="add_rows"
                phx-value-count="5"
                class="btn btn-ghost btn-sm"
              >
                + {gettext("Add 5 rows")}
              </button>
              <div class="ml-auto flex gap-2">
                <.link
                  navigate={~p"/farms/#{@current_scope.farm.slug}/breeding"}
                  class="btn btn-ghost btn-sm"
                >
                  {gettext("Cancel")}
                </.link>
                <.button
                  class="btn btn-primary btn-sm"
                  phx-disable-with={gettext("Committing...")}
                  disabled={non_empty_rows(@rows) == []}
                >
                  {gettext("Commit %{n} rows", n: length(non_empty_rows(@rows)))}
                </.button>
              </div>
            </div>
          </form>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    today = to_string(Date.utc_today())

    gestating = Breeding.list_gestating_sows(scope, limit: :all)
    sow_items = Enum.map(gestating, &gestating_item/1)
    sow_index = Map.new(gestating, fn g -> {g.service.id, g} end)

    pens = Locations.list_all_pens(scope)
    pen_items = Enum.map(pens, &%{id: &1.id, label: "#{&1.house.code}/#{&1.code}"})

    {:ok,
     socket
     |> assign(
       can_record: Policy.can?(scope, :record_breeding),
       sow_items: sow_items,
       sow_index: sow_index,
       pen_items: pen_items,
       rows: Enum.map(1..3, fn _ -> blank_row(today) end),
       default_date: today,
       error_index: nil,
       error_message: nil
     )}
  end

  @impl true
  def handle_event("update", %{"rows" => params}, socket) do
    rows =
      Enum.map(socket.assigns.rows, fn row ->
        case Map.get(params, row.tmp_id) do
          nil -> row
          row_params -> merge_row(row, row_params, socket.assigns)
        end
      end)

    {:noreply, assign(socket, rows: rows, error_index: nil, error_message: nil)}
  end

  def handle_event("add_row", _, socket) do
    {:noreply,
     assign(socket, rows: socket.assigns.rows ++ [blank_row(socket.assigns.default_date)])}
  end

  def handle_event("add_rows", %{"count" => n}, socket) do
    count = String.to_integer(n)
    extra = Enum.map(1..count, fn _ -> blank_row(socket.assigns.default_date) end)
    {:noreply, assign(socket, rows: socket.assigns.rows ++ extra)}
  end

  def handle_event("remove_row", %{"id" => tmp_id}, socket) do
    rows = Enum.reject(socket.assigns.rows, &(&1.tmp_id == tmp_id))
    rows = if rows == [], do: [blank_row(socket.assigns.default_date)], else: rows

    {:noreply,
     socket
     |> assign(rows: rows, error_index: nil, error_message: nil)
     |> push_event("ac:reset", %{id: "row-#{tmp_id}-sow"})
     |> push_event("ac:reset", %{id: "row-#{tmp_id}-pen"})}
  end

  def handle_event("commit", _params, socket) do
    if socket.assigns.can_record do
      do_commit(socket)
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  defp do_commit(socket) do
    scope = socket.assigns.current_scope
    rows = non_empty_rows(socket.assigns.rows)

    entries =
      Enum.map(rows, fn r ->
        %{
          service_id: r.service_id,
          farrowed_at: r.farrowed_at,
          pen_id: r.pen_id,
          born_alive: to_int_or_zero(r.born_alive),
          stillborn: to_int_or_zero(r.stillborn),
          mummified: to_int_or_zero(r.mummified),
          total_birth_weight_g: to_int_or_nil(r.total_birth_weight_g)
        }
      end)

    case Breeding.record_batch_farrowings(scope, entries) do
      {:ok, farrowings} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Committed %{n} farrowings.", n: length(farrowings)))
         |> push_navigate(to: ~p"/farms/#{scope.farm.slug}/breeding?tab=lactating")}

      {:error, {i, %Ecto.Changeset{} = cs}} ->
        {:noreply, assign(socket, error_index: i, error_message: format_row_error(i, cs))}

      {:error, {i, reason}} ->
        {:noreply,
         assign(socket,
           error_index: i,
           error_message: "Row #{i + 1}: #{inspect(reason)}"
         )}

      {:error, reason} ->
        {:noreply, assign(socket, error_index: nil, error_message: inspect(reason))}
    end
  end

  # ── Row helpers ──────────────────────────────────────────────────

  defp blank_row(default_date) do
    %{
      tmp_id: gen_tmp_id(),
      service_id: nil,
      sow_label: nil,
      farrowed_at: default_date,
      pen_id: nil,
      pen_label: nil,
      born_alive: nil,
      stillborn: 0,
      mummified: 0,
      total_birth_weight_g: nil
    }
  end

  defp gen_tmp_id do
    :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
  end

  defp merge_row(row, params, assigns) do
    new_service_id = parse_int(Map.get(params, "service_id"))
    new_pen_id = parse_int(Map.get(params, "pen_id"))

    {service_id, sow_label, pen_id, pen_label} =
      apply_sow_pick(row, new_service_id, new_pen_id, assigns)

    %{
      row
      | service_id: service_id,
        sow_label: sow_label,
        farrowed_at: Map.get(params, "farrowed_at", row.farrowed_at),
        pen_id: pen_id,
        pen_label: pen_label,
        born_alive: Map.get(params, "born_alive", row.born_alive),
        stillborn: Map.get(params, "stillborn", row.stillborn),
        mummified: Map.get(params, "mummified", row.mummified),
        total_birth_weight_g: Map.get(params, "total_birth_weight_g", row.total_birth_weight_g)
    }
  end

  # When the user picks a new sow, default the pen to the sow's
  # current pen (if it has one and the row hasn't been pen-edited yet).
  defp apply_sow_pick(row, new_service_id, new_pen_id, assigns) do
    sow_label = lookup_label(assigns.sow_items, new_service_id)

    sow_changed? = new_service_id != row.service_id

    {pen_id, pen_label} =
      cond do
        sow_changed? and new_service_id != nil ->
          case Map.get(assigns.sow_index, new_service_id) do
            %{service: %{sow: %{current_pen_id: cur}}} when not is_nil(cur) ->
              {cur, lookup_label(assigns.pen_items, cur)}

            _ ->
              {new_pen_id, lookup_label(assigns.pen_items, new_pen_id)}
          end

        true ->
          {new_pen_id, lookup_label(assigns.pen_items, new_pen_id)}
      end

    {new_service_id, sow_label, pen_id, pen_label}
  end

  defp non_empty_rows(rows) do
    Enum.filter(rows, fn r -> not is_nil(r.service_id) end)
  end

  defp gestating_item(%{service: s}) do
    %{id: s.id, label: s.sow.ear_tag}
  end

  defp lookup_label(_items, nil), do: nil

  defp lookup_label(items, id) do
    case Enum.find(items, &(&1.id == id)) do
      %{label: l} -> l
      _ -> nil
    end
  end

  defp format_row_error(i, %Ecto.Changeset{errors: errors}) do
    case errors do
      [{field, {msg, _}} | _] -> "Row #{i + 1}: #{field} #{msg}"
      _ -> "Row #{i + 1} failed"
    end
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(i) when is_integer(i), do: i

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {i, ""} -> i
      _ -> nil
    end
  end

  defp to_int_or_zero(nil), do: 0
  defp to_int_or_zero(""), do: 0
  defp to_int_or_zero(i) when is_integer(i), do: i

  defp to_int_or_zero(s) when is_binary(s) do
    case Integer.parse(s) do
      {i, ""} -> i
      _ -> 0
    end
  end

  defp to_int_or_nil(nil), do: nil
  defp to_int_or_nil(""), do: nil
  defp to_int_or_nil(i) when is_integer(i), do: i

  defp to_int_or_nil(s) when is_binary(s) do
    case Integer.parse(s) do
      {i, ""} -> i
      _ -> nil
    end
  end
end
