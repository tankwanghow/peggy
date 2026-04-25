defmodule PeggyWeb.FarmLive.BatchEntry do
  @moduledoc """
  Spreadsheet-style batch entry for placement and pen-transfer of a
  single batch animal across many pens in one atomic commit.

  Rows live entirely in LiveView assigns until the user clicks Commit;
  they're then sent as one list to `Animals.record_batch_movements/3`
  where a single transaction validates the aggregate budget and writes
  every placement/movement row or none at all.
  """
  use PeggyWeb, :live_view

  alias Peggy.Animals
  alias Peggy.Animals.Animal
  alias Peggy.FarmClock
  alias Peggy.Locations
  alias Peggy.Policy

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-6xl">
        <div class="text-sm text-base-content/60 mb-1">
          <.link
            navigate={~p"/farms/#{@current_scope.farm.slug}/animals/#{@animal.id}"}
            class="text-primary underline hover:text-primary/80"
          >
            ← {gettext("Back to animal")}
          </.link>
        </div>

        <.header>
          {gettext("Batch Transfer")}
          <span class="ml-2 font-mono text-base font-normal">
            {@animal.ear_tag || "##{@animal.id}"}
          </span>
          <:subtitle>
            {String.capitalize(@animal.stage)} · {gettext("Batch of %{n}", n: @animal.quantity)}
          </:subtitle>
          <:actions>
            <span class={["badge", budget_badge(@unplaced_remaining)]}>
              {gettext("Unplaced")}: {@unplaced_remaining}
            </span>
          </:actions>
        </.header>

        <%!-- Current placements summary --%>
        <section :if={@placements != []} class="mt-4">
          <p class="text-sm text-base-content/60 mb-1">{gettext("Current placements")}</p>
          <div class="flex flex-wrap gap-2 text-sm font-mono">
            <span
              :for={p <- @placements}
              class="inline-flex items-center gap-1 rounded bg-base-200 px-2 py-0.5"
            >
              {p.pen.house.code}-{p.pen.code}
              <span class="text-base-content/60">×{p.quantity}</span>
            </span>
          </div>
        </section>

        <%!-- Grid --%>
        <section class="mt-6">
          <form
            id="batch-grid"
            phx-change="update"
            phx-submit="commit"
            phx-debounce="300"
          >
            <table class="table table-sm w-full text-sm">
              <thead class="text-left text-base-content/60">
                <tr>
                  <th class="py-2 w-8">#</th>
                  <th class="py-2">{gettext("Reason")}</th>
                  <th class="py-2">{gettext("From pen")}</th>
                  <th class="py-2">{gettext("To pen")}</th>
                  <th class="py-2 w-24">{gettext("Qty")}</th>
                  <th class="py-2">{gettext("Notes")}</th>
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
                  <td class="py-1 text-base-content/60">{i + 1}</td>
                  <td class="py-1">
                    <select
                      name={"rows[#{row.tmp_id}][reason]"}
                      class="select w-full"
                    >
                      <option value="placement" selected={row.reason == "placement"}>
                        {gettext("Placement")}
                      </option>
                      <option value="pen_transfer" selected={row.reason == "pen_transfer"}>
                        {gettext("Pen transfer")}
                      </option>
                    </select>
                  </td>
                  <td class="py-1">
                    <.autocomplete
                      :if={row.reason == "pen_transfer"}
                      id={"row-#{row.tmp_id}-from"}
                      label=""
                      name={"rows[#{row.tmp_id}][from_pen_id]"}
                      value={row.from_pen_id}
                      items={@placement_items}
                      selected_label={row.from_pen_label}
                      class="input w-full font-mono"
                      placeholder={gettext("Search...")}
                    />
                    <span :if={row.reason != "pen_transfer"} class="text-base-content/30">—</span>
                  </td>
                  <td class="py-1">
                    <.autocomplete
                      id={"row-#{row.tmp_id}-to"}
                      label=""
                      name={"rows[#{row.tmp_id}][to_pen_id]"}
                      value={row.to_pen_id}
                      items={@pen_items}
                      selected_label={row.to_pen_label}
                      class="input w-full font-mono"
                      placeholder={gettext("Search...")}
                    />
                  </td>
                  <td class="py-1">
                    <input
                      type="number"
                      min="1"
                      name={"rows[#{row.tmp_id}][quantity]"}
                      value={row.qty}
                      class="input w-full"
                    />
                  </td>
                  <td class="py-1">
                    <input
                      type="text"
                      name={"rows[#{row.tmp_id}][notes]"}
                      value={row.notes || ""}
                      class="input w-full"
                    />
                  </td>
                  <td class="py-1 text-right">
                    <button
                      type="button"
                      phx-click="remove_row"
                      phx-value-id={row.tmp_id}
                      class="btn btn-ghost btn-sm"
                      title={gettext("Remove row")}
                    >
                      ×
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>

            <p
              :if={@error_message}
              class="mt-3 text-sm text-error"
            >
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
                  navigate={~p"/farms/#{@current_scope.farm.slug}/animals/#{@animal.id}"}
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
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    animal = Animals.get_animal!(scope, String.to_integer(id))

    if animal.tracking_type != "batch" do
      {:ok,
       socket
       |> put_flash(:error, gettext("Batch entry is only for batch animals."))
       |> redirect(to: ~p"/farms/#{scope.farm.slug}/animals/#{animal.id}")}
    else
      placements = Animals.list_placements(scope, animal)
      pen_items = pen_items(scope)
      placement_items = placement_items(placements)
      rows = Enum.map(1..3, fn _ -> blank_row() end)

      {:ok,
       socket
       |> assign(
         animal: animal,
         placements: placements,
         pen_items: pen_items,
         placement_items: placement_items,
         rows: rows,
         error_index: nil,
         error_message: nil,
         can_move: Policy.can?(scope, :record_movement)
       )
       |> assign_derived()}
    end
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

    {:noreply,
     socket
     |> assign(rows: rows, error_index: nil, error_message: nil)
     |> assign_derived()}
  end

  def handle_event("add_row", _, socket) do
    {:noreply, assign(socket, rows: socket.assigns.rows ++ [blank_row()])}
  end

  def handle_event("add_rows", %{"count" => n}, socket) do
    count = String.to_integer(n)
    extra = Enum.map(1..count, fn _ -> blank_row() end)
    {:noreply, assign(socket, rows: socket.assigns.rows ++ extra)}
  end

  def handle_event("remove_row", %{"id" => tmp_id}, socket) do
    rows = Enum.reject(socket.assigns.rows, &(&1.tmp_id == tmp_id))
    # Keep at least one row so the grid doesn't collapse to zero.
    rows = if rows == [], do: [blank_row()], else: rows

    {:noreply,
     socket
     |> assign(rows: rows, error_index: nil, error_message: nil)
     |> push_event("ac:reset", %{id: "row-#{tmp_id}-from"})
     |> push_event("ac:reset", %{id: "row-#{tmp_id}-to"})
     |> assign_derived()}
  end

  def handle_event("commit", _params, socket) do
    if socket.assigns.can_move do
      do_commit(socket)
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  defp do_commit(socket) do
    scope = socket.assigns.current_scope
    animal = socket.assigns.animal
    rows = non_empty_rows(socket.assigns.rows)

    entries =
      Enum.map(rows, fn r ->
        %{
          reason: r.reason,
          quantity: r.qty,
          from_pen_id: r.from_pen_id,
          to_pen_id: r.to_pen_id,
          moved_at: FarmClock.today(scope),
          notes: r.notes
        }
      end)

    case Animals.record_batch_movements(scope, animal, entries) do
      {:ok, movements} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("Committed %{n} rows.", n: length(movements))
         )
         |> push_navigate(to: ~p"/farms/#{scope.farm.slug}/animals/#{animal.id}")}

      {:error, {i, cs_or_reason}} ->
        {:noreply,
         socket
         |> assign(error_index: i, error_message: format_row_error(i, cs_or_reason))}

      {:error, reason} ->
        {:noreply, assign(socket, error_index: nil, error_message: to_string(reason))}
    end
  end

  # -- Row helpers --

  defp blank_row do
    %{
      tmp_id: gen_tmp_id(),
      reason: "placement",
      from_pen_id: nil,
      to_pen_id: nil,
      qty: nil,
      notes: nil,
      from_pen_label: nil,
      to_pen_label: nil
    }
  end

  defp gen_tmp_id do
    :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
  end

  defp merge_row(row, params, assigns) do
    reason = Map.get(params, "reason", row.reason)
    from_pen_id = parse_int(Map.get(params, "from_pen_id"))
    to_pen_id = parse_int(Map.get(params, "to_pen_id"))
    qty = parse_int(Map.get(params, "quantity"))
    notes = Map.get(params, "notes")

    %{
      row
      | reason: reason,
        from_pen_id: from_pen_id,
        to_pen_id: to_pen_id,
        qty: qty,
        notes: notes,
        from_pen_label: lookup_label(assigns.placement_items, from_pen_id),
        to_pen_label: lookup_label(assigns.pen_items, to_pen_id)
    }
  end

  # A row is non-empty if it has both the mandatory destination pen and
  # a positive quantity. Empty rows are silently ignored on commit so
  # users can leave a few extras hanging around without manually deleting.
  defp non_empty_rows(rows) do
    Enum.filter(rows, fn r ->
      is_integer(r.qty) and r.qty > 0 and not is_nil(r.to_pen_id)
    end)
  end

  # Project the in-progress grid to show a live remaining-unplaced count.
  defp assign_derived(socket) do
    unplaced = unplaced_qty(socket.assigns.animal, socket.assigns.placements)

    staged_delta =
      socket.assigns.rows
      |> non_empty_rows()
      |> Enum.reduce(0, fn
        %{reason: "placement", qty: q}, acc when is_integer(q) -> acc + q
        _, acc -> acc
      end)

    assign(socket, unplaced_remaining: unplaced - staged_delta)
  end

  defp unplaced_qty(%Animal{quantity: q}, placements) do
    q - Enum.reduce(placements, 0, &(&1.quantity + &2))
  end

  defp budget_badge(n) when n < 0, do: "badge-error"
  defp budget_badge(0), do: "badge-success"
  defp budget_badge(_), do: "badge-ghost"

  defp format_row_error(i, %Ecto.Changeset{errors: errors}) do
    case errors do
      [{field, {msg, _}} | _] -> "Row #{i + 1}: #{field} #{msg}"
      _ -> "Row #{i + 1} failed"
    end
  end

  defp format_row_error(i, reason) when is_atom(reason) do
    "Row #{i + 1}: #{reason}"
  end

  defp format_row_error(i, _), do: "Row #{i + 1} failed"

  # -- Pickers --

  defp pen_items(scope) do
    scope
    |> Locations.list_all_pens()
    |> Enum.map(&%{id: &1.id, label: "#{&1.house.code}-#{&1.code}"})
  end

  defp placement_items(placements) do
    Enum.map(placements, fn p ->
      %{id: p.pen_id, label: "#{p.pen.house.code}-#{p.pen.code} (#{p.quantity})"}
    end)
  end

  defp lookup_label(_items, nil), do: nil

  defp lookup_label(items, id) do
    case Enum.find(items, &(&1.id == id)) do
      %{label: l} -> l
      _ -> nil
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
end
