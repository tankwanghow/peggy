defmodule PeggyWeb.FarmLive.BulkMove do
  @moduledoc """
  Spreadsheet-style bulk pen-move grid for individual animals.

  Each row moves one animal to a destination pen. The reason is inferred
  from the animal's current state — "placement" if the animal has no
  current pen yet, "pen_transfer" otherwise — so users don't have to
  pick it. Rows live in LiveView assigns until Commit, then flow through
  `Animals.record_bulk_individual_moves/2` in one atomic transaction.
  """
  use PeggyWeb, :live_view

  alias Peggy.Animals
  alias Peggy.Locations
  alias Peggy.Policy

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-6xl">
        <div class="text-sm text-base-content/60 mb-1">
          <.link
            navigate={~p"/farms/#{@current_scope.farm.slug}/animals"}
            class="text-primary underline hover:text-primary/80"
          >
            ← {gettext("All animals")}
          </.link>
        </div>

        <.header>
          {gettext("Bulk Move Sire/Dam")}
          <:subtitle>
            {gettext("Move many individual animals to destination pens in one commit.")}
          </:subtitle>
          <:actions>
            <span class="badge badge-ghost">
              {gettext("Ready")}: {length(non_empty_rows(@rows))}
            </span>
          </:actions>
        </.header>

        <section class="mt-6">
          <form
            id="bulk-move-grid"
            phx-change="update"
            phx-submit="commit"
            phx-debounce="300"
          >
            <table class="table w-full">
              <thead class="text-left text-base-content/60">
                <tr>
                  <th class="py-1 w-8">#</th>
                  <th class="py-1">{gettext("Animal")}</th>
                  <th class="py-1">{gettext("From pen")}</th>
                  <th class="py-1">{gettext("To pen")}</th>
                  <th class="py-1">{gettext("Action")}</th>
                  <th class="py-1 w-10"></th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={{row, i} <- Enum.with_index(@rows)}
                  class={[
                    "border-t border-base-200 align-middle",
                    @error_index == i && "bg-error/10"
                  ]}
                >
                  <td class="py-0.5 text-base-content/60">{i + 1}</td>
                  <td class="py-0.5">
                    <.autocomplete
                      id={"row-#{row.tmp_id}-animal"}
                      label=""
                      name={"rows[#{row.tmp_id}][animal_id]"}
                      value={row.animal_id}
                      items={@animal_items}
                      selected_label={row.animal_label}
                      class="input w-full font-mono"
                      placeholder={gettext("Search tag...")}
                    />
                  </td>
                  <td class="py-0.5 font-mono text-base-content/70">
                    {row.from_pen_label || "—"}
                  </td>
                  <td class="py-0.5">
                    <.autocomplete
                      id={"row-#{row.tmp_id}-to"}
                      label=""
                      name={"rows[#{row.tmp_id}][to_pen_id]"}
                      value={row.to_pen_id}
                      items={@pen_items}
                      selected_label={row.to_pen_label}
                      class="input w-full font-mono"
                      placeholder={gettext("Search pen...")}
                    />
                  </td>
                  <td class="py-0.5 text-base-content/70">
                    <span :if={row.reason == "placement"} class="badge badge-sm badge-info">
                      {gettext("Placement")}
                    </span>
                    <span :if={row.reason == "pen_transfer"} class="badge badge-sm">
                      {gettext("Transfer")}
                    </span>
                    <span :if={is_nil(row.reason)} class="text-base-content/30">—</span>
                  </td>
                  <td class="py-0.5 text-right">
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
                  navigate={~p"/farms/#{@current_scope.farm.slug}/animals"}
                  class="btn btn-ghost btn-sm"
                >
                  {gettext("Cancel")}
                </.link>
                <.button
                  class="btn btn-primary btn-sm"
                  phx-disable-with={gettext("Committing...")}
                  disabled={non_empty_rows(@rows) == []}
                >
                  {gettext("Commit %{n} moves", n: length(non_empty_rows(@rows)))}
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

    animals = Animals.list_animals(scope, status: "active")
    individual_animals = Enum.filter(animals, &(&1.tracking_type == "individual"))

    animal_items = animal_items(individual_animals)
    animal_lookup = Map.new(individual_animals, &{&1.id, &1})
    pen_items = pen_items(scope)
    pen_lookup = Map.new(pen_items, &{&1.id, &1.label})

    rows = Enum.map(1..3, fn _ -> blank_row() end)

    {:ok,
     socket
     |> assign(
       animal_items: animal_items,
       animal_lookup: animal_lookup,
       pen_items: pen_items,
       pen_lookup: pen_lookup,
       rows: rows,
       error_index: nil,
       error_message: nil,
       can_move: Policy.can?(scope, :record_movement)
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
     |> push_event("ac:reset", %{id: "row-#{tmp_id}-animal"})
     |> push_event("ac:reset", %{id: "row-#{tmp_id}-to"})}
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
    rows = non_empty_rows(socket.assigns.rows)

    entries =
      Enum.map(rows, fn r ->
        %{
          animal_id: r.animal_id,
          to_pen_id: r.to_pen_id,
          moved_at: Date.utc_today(),
          notes: r.notes
        }
      end)

    case Animals.record_bulk_individual_moves(scope, entries) do
      {:ok, movements} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Moved %{n} animals.", n: length(movements)))
         |> push_navigate(to: ~p"/farms/#{scope.farm.slug}/animals")}

      {:error, {i, cs_or_reason}} ->
        {:noreply,
         socket
         |> assign(error_index: i, error_message: format_row_error(i, cs_or_reason))}

      {:error, reason} ->
        {:noreply, assign(socket, error_index: nil, error_message: to_string(reason))}
    end
  end

  ## Row helpers

  defp blank_row do
    %{
      tmp_id: gen_tmp_id(),
      animal_id: nil,
      animal_label: nil,
      from_pen_label: nil,
      to_pen_id: nil,
      to_pen_label: nil,
      reason: nil,
      notes: nil
    }
  end

  defp gen_tmp_id do
    :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
  end

  defp merge_row(row, params, assigns) do
    animal_id = parse_int(Map.get(params, "animal_id"))
    to_pen_id = parse_int(Map.get(params, "to_pen_id"))
    notes = Map.get(params, "notes")

    animal = animal_id && Map.get(assigns.animal_lookup, animal_id)

    %{
      row
      | animal_id: animal_id,
        animal_label: animal && animal.ear_tag,
        from_pen_label: animal && current_pen_label(animal),
        to_pen_id: to_pen_id,
        to_pen_label: to_pen_id && Map.get(assigns.pen_lookup, to_pen_id),
        reason: infer_reason(animal),
        notes: notes
    }
  end

  defp infer_reason(nil), do: nil
  defp infer_reason(%{current_pen_id: nil}), do: "placement"
  defp infer_reason(%{current_pen_id: _}), do: "pen_transfer"

  defp current_pen_label(%{current_pen: %{code: code, house: %{code: hcode}}}),
    do: "#{hcode}-#{code}"

  defp current_pen_label(_), do: nil

  # A row is committable once it has an animal and a destination pen.
  defp non_empty_rows(rows) do
    Enum.filter(rows, fn r ->
      not is_nil(r.animal_id) and not is_nil(r.to_pen_id)
    end)
  end

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

  ## Picker sources

  defp animal_items(animals) do
    animals
    |> Enum.filter(&(&1.ear_tag != nil))
    |> Enum.map(fn a ->
      pen = current_pen_label(a)
      suffix = if pen, do: " (#{pen})", else: " (unplaced)"
      %{id: a.id, label: "#{a.ear_tag}#{suffix}"}
    end)
  end

  defp pen_items(scope) do
    scope
    |> Locations.list_all_pens()
    |> Enum.map(&%{id: &1.id, label: "#{&1.house.code}-#{&1.code}"})
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
