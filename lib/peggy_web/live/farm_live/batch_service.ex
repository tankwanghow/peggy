defmodule PeggyWeb.FarmLive.BatchService do
  @moduledoc """
  Spreadsheet-style batch entry for recording multiple breeding
  services at once in one atomic commit.
  """
  use PeggyWeb, :live_view

  alias Peggy.{Breeding, Animals, Policy}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-6xl">
        <div class="text-sm text-base-content/60 mb-1">
          <.link
            navigate={~p"/farms/#{@current_scope.farm.slug}/breeding"}
            class="text-primary underline hover:text-primary/80"
          >
            ← {gettext("Breeding")}
          </.link>
        </div>

        <.header>
          {gettext("Batch Service Entry")}
          <:subtitle>{gettext("Record multiple services at once")}</:subtitle>
        </.header>

        <section class="mt-6">
          <form
            id="batch-service-grid"
            phx-change="update"
            phx-submit="commit"
            phx-debounce="300"
          >
            <table class="table table-sm w-full text-sm">
              <thead class="text-left text-base-content/60">
                <tr>
                  <th class="py-2 w-8">#</th>
                  <th class="py-2">{gettext("Sow")}</th>
                  <th class="py-2">{gettext("Service type")}</th>
                  <th class="py-2">{gettext("Boar")}</th>
                  <th class="py-2">{gettext("Served at")}</th>
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
                    <.autocomplete
                      id={"row-#{row.tmp_id}-sow"}
                      label=""
                      name={"rows[#{row.tmp_id}][sow_id]"}
                      value={row.sow_id}
                      items={@sow_items}
                      selected_label={row.sow_label}
                      class="input w-full font-mono"
                      placeholder={gettext("Ear tag...")}
                    />
                  </td>
                  <td class="py-1">
                    <select
                      name={"rows[#{row.tmp_id}][service_type]"}
                      class="select w-full"
                    >
                      <option value="natural" selected={row.service_type == "natural"}>
                        {gettext("Natural")}
                      </option>
                      <option value="ai" selected={row.service_type == "ai"}>
                        {gettext("AI")}
                      </option>
                    </select>
                  </td>
                  <td class="py-1">
                    <.autocomplete
                      :if={row.service_type == "natural"}
                      id={"row-#{row.tmp_id}-boar"}
                      label=""
                      name={"rows[#{row.tmp_id}][boar_id]"}
                      value={row.boar_id}
                      items={@boar_items}
                      selected_label={row.boar_label}
                      class="input w-full font-mono"
                      placeholder={gettext("Ear tag...")}
                    />
                    <span
                      :if={row.service_type != "natural"}
                      class="text-base-content/30"
                    >
                      —
                    </span>
                  </td>
                  <td class="py-1">
                    <input
                      type="date"
                      name={"rows[#{row.tmp_id}][served_at]"}
                      value={row.served_at}
                      class="input w-full"
                    />
                  </td>
                  <td class="py-1 text-right">
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
    # Sows: only serviceable (active/open/dry); boars: any present male.
    sow_pool = Animals.list_animals(scope, status: "serviceable")
    boar_pool = Animals.list_animals(scope, status: "present")
    today = to_string(Date.utc_today())

    {:ok,
     socket
     |> assign(
       can_record: Policy.can?(scope, :record_breeding),
       sow_items: animal_items(sow_pool, "female"),
       boar_items: animal_items(boar_pool, "male"),
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
     |> push_event("ac:reset", %{id: "row-#{tmp_id}-boar"})}
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
        entry = %{
          sow_id: r.sow_id,
          service_type: r.service_type,
          served_at: r.served_at,
          notes: r.notes
        }

        if r.service_type == "natural" and r.boar_id,
          do: Map.put(entry, :boar_id, r.boar_id),
          else: entry
      end)

    case Breeding.record_batch_services(scope, entries) do
      {:ok, services} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Committed %{n} services.", n: length(services)))
         |> push_navigate(to: ~p"/farms/#{scope.farm.slug}/breeding")}

      {:error, {i, cs}} ->
        {:noreply, assign(socket, error_index: i, error_message: format_row_error(i, cs))}

      {:error, reason} ->
        {:noreply, assign(socket, error_index: nil, error_message: to_string(reason))}
    end
  end

  # ── Row helpers ──────────────────────────────────────────────────

  defp blank_row(default_date) do
    %{
      tmp_id: gen_tmp_id(),
      sow_id: nil,
      sow_label: nil,
      service_type: "natural",
      boar_id: nil,
      boar_label: nil,
      served_at: default_date,
      notes: nil
    }
  end

  defp gen_tmp_id do
    :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
  end

  defp merge_row(row, params, assigns) do
    sow_id = parse_int(Map.get(params, "sow_id"))
    boar_id = parse_int(Map.get(params, "boar_id"))
    service_type = Map.get(params, "service_type", row.service_type)

    %{
      row
      | sow_id: sow_id,
        sow_label: lookup_label(assigns.sow_items, sow_id),
        service_type: service_type,
        boar_id: if(service_type == "natural", do: boar_id, else: nil),
        boar_label:
          if(service_type == "natural",
            do: lookup_label(assigns.boar_items, boar_id),
            else: nil
          ),
        served_at: Map.get(params, "served_at", row.served_at),
        notes: Map.get(params, "notes")
    }
  end

  defp non_empty_rows(rows) do
    Enum.filter(rows, fn r -> not is_nil(r.sow_id) end)
  end

  defp animal_items(animals, sex) do
    animals
    |> Enum.filter(&(&1.sex == sex and &1.ear_tag != nil))
    |> Enum.map(&%{id: &1.id, label: &1.ear_tag})
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

  defp format_row_error(i, _), do: "Row #{i + 1} failed"

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
