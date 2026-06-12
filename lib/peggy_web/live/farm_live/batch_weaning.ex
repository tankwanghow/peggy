defmodule PeggyWeb.FarmLive.BatchWeaning do
  @moduledoc """
  Spreadsheet-style batch entry for recording multiple weanings at
  once in one atomic commit.

  Supports the back-fill cascade: each row takes an ear tag. Existing
  sows without an open farrowing get an inferred service + farrowing
  back-dated from the weaned_at; unknown tags also create an inferred
  sow.
  """
  use PeggyWeb, :live_view

  alias Peggy.{Breeding, Animals, FarmClock, Locations, Policy}

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
          {gettext("Batch Weaning Entry")}
          <:subtitle>
            {gettext("Type ear tags — missing services/farrowings are back-filled on commit")}
          </:subtitle>
        </.header>

        <section class="mt-6">
          <form
            id="batch-weaning-grid"
            phx-change="update"
            phx-submit="commit"
            phx-debounce="300"
          >
            <table class="table table-sm w-full text-sm">
              <thead class="text-left text-base-content/60">
                <tr>
                  <th class="py-2 w-8">#</th>
                  <th class="py-2 min-w-[11rem]">{gettext("Sow ear tag")}</th>
                  <th class="py-2 min-w-[9rem]">{gettext("Weaned at")}</th>
                  <th class="py-2 w-24 text-right">{gettext("Weaned")}</th>
                  <th class="py-2 w-24 text-right">{gettext("Avg wt (g)")}</th>
                  <th class="py-2 min-w-[9rem]">{gettext("Batch tag")}</th>
                  <th class="py-2 min-w-[9rem]">{gettext("Destination pen")}</th>
                  <th class="py-2 min-w-[8rem]">{gettext("Breed (new sow)")}</th>
                  <th class="py-2 w-10"></th>
                </tr>
              </thead>
              <tbody>
                <%= for {row, i} <- Enum.with_index(@rows) do %>
                  <tr class={[
                    "border-t border-base-200 align-top",
                    @error_index == i && "bg-error/10",
                    row.sow_state == :existing_open && "bg-success/5",
                    row.sow_state == :existing_no_farrowing && "bg-warning/5",
                    row.sow_state == :new && "bg-warning/5",
                    row.sow_state == :similar && "bg-error/10",
                    row.sow_state == :similar_overridable && "bg-warning/5"
                  ]}>
                    <td class="py-1 px-0.5 text-base-content/60">{i + 1}</td>
                    <td class="py-1 px-0.5">
                      <input
                        type="text"
                        name={"rows[#{row.tmp_id}][sow_ear_tag]"}
                        value={row.sow_ear_tag}
                        phx-debounce="300"
                        autocomplete="off"
                        spellcheck="false"
                        class={[
                          "input input-bordered w-full font-mono text-sm",
                          sow_input_class(row.sow_state)
                        ]}
                        placeholder={gettext("e.g. SOW1234")}
                      />
                      <p class={[
                        "mt-0.5 text-xs",
                        row.sow_state == :existing_open && "text-success",
                        row.sow_state == :existing_no_farrowing && "text-warning",
                        row.sow_state == :new && "text-warning",
                        row.sow_state == :similar && "text-error",
                        row.sow_state == :similar_overridable && "text-warning",
                        row.sow_state == :empty && "text-base-content/40"
                      ]}>
                        {row_state_text(row)}
                      </p>
                      <div
                        :if={row.sow_state in [:similar, :similar_overridable]}
                        class="mt-1"
                      >
                        <div class="flex flex-wrap gap-1">
                          <button
                            :for={t <- row.similar_tags}
                            type="button"
                            phx-click="pick_similar"
                            phx-value-id={row.tmp_id}
                            phx-value-tag={t}
                            class="btn btn-sm btn-outline btn-error font-mono"
                          >
                            {t}
                          </button>
                        </div>
                        <label class="mt-1 flex items-center gap-2 cursor-pointer">
                          <input
                            type="hidden"
                            name={"rows[#{row.tmp_id}][force_create]"}
                            value="false"
                          />
                          <input
                            type="checkbox"
                            name={"rows[#{row.tmp_id}][force_create]"}
                            value="true"
                            checked={row.force_create}
                            class="checkbox checkbox-xs"
                          />
                          <span class="text-xs">
                            {gettext("Create anyway")}
                          </span>
                        </label>
                      </div>
                    </td>
                    <td class="py-1 px-0.5">
                      <input
                        type="date"
                        name={"rows[#{row.tmp_id}][weaned_at]"}
                        value={row.weaned_at}
                        class="input w-full"
                      />
                    </td>
                    <td class="py-1 px-0.5">
                      <input
                        type="number"
                        min="0"
                        name={"rows[#{row.tmp_id}][weaned_count]"}
                        value={row.weaned_count}
                        class="input w-full text-right"
                      />
                    </td>
                    <td class="py-1 px-0.5">
                      <input
                        type="number"
                        min="0"
                        name={"rows[#{row.tmp_id}][avg_wean_weight_g]"}
                        value={row.avg_wean_weight_g}
                        class="input w-full text-right"
                      />
                    </td>
                    <td class="py-1 px-0.5">
                      <input
                        type="text"
                        name={"rows[#{row.tmp_id}][batch_tag]"}
                        value={row.batch_tag}
                        autocomplete="off"
                        spellcheck="false"
                        class="input input-bordered w-full font-mono"
                        placeholder={gettext("e.g. W20260612")}
                      />
                    </td>
                    <td class="py-1 px-0.5">
                      <input
                        type="text"
                        name={"rows[#{row.tmp_id}][pen_input]"}
                        value={row.pen_input}
                        phx-debounce="300"
                        autocomplete="off"
                        spellcheck="false"
                        class={[
                          "input input-bordered w-full font-mono",
                          row.pen_state == :found && "border-success",
                          row.pen_state == :not_found && "border-error"
                        ]}
                        placeholder={gettext("e.g. H1/N1")}
                      />
                      <p
                        :if={row.pen_state == :not_found}
                        class="mt-0.5 text-xs text-error"
                      >
                        {gettext("pen not found")}
                      </p>
                    </td>
                    <td class="py-1 px-0.5">
                      <input
                        :if={row.sow_state in [:new, :similar_overridable]}
                        type="text"
                        name={"rows[#{row.tmp_id}][breed]"}
                        value={row.breed}
                        class="input input-bordered w-full"
                        placeholder={gettext("Optional")}
                      />
                      <span
                        :if={row.sow_state not in [:new, :similar_overridable]}
                        class="text-base-content/30"
                      >
                        —
                      </span>
                    </td>
                    <td class="py-1 px-0.5 text-right">
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
                <% end %>
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
                  disabled={not commit_ready?(@rows)}
                >
                  {gettext("Commit %{n} rows", n: length(committable_rows(@rows)))}
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
    pens = Locations.list_all_pens(scope)
    today = to_string(FarmClock.today(scope))

    pens_by_label = Map.new(pens, fn p -> {pen_label(p), p.id} end)
    pens_by_id = Map.new(pens, fn p -> {p.id, pen_label(p)} end)

    {:ok,
     socket
     |> assign(
       can_record: Policy.can?(scope, :record_breeding),
       pens_by_label: pens_by_label,
       pens_by_id: pens_by_id,
       rows: Enum.map(1..3, fn _ -> blank_row(today) end),
       default_date: today,
       error_index: nil,
       error_message: nil
     )}
  end

  defp pen_label(%{house: house, code: code}), do: "#{house.code}-#{code}"

  @impl true
  def handle_event("update", params, socket) do
    row_params = Map.get(params, "rows", %{})

    rows =
      Enum.map(socket.assigns.rows, fn row ->
        case Map.get(row_params, row.tmp_id) do
          nil -> row
          p -> merge_row(row, p, socket.assigns)
        end
      end)
      |> Enum.map(&resolve_row(&1, socket.assigns))

    {:noreply,
     assign(socket,
       rows: rows,
       error_index: nil,
       error_message: nil
     )}
  end

  def handle_event("pick_similar", %{"id" => tmp_id, "tag" => tag}, socket) do
    rows =
      Enum.map(socket.assigns.rows, fn r ->
        if r.tmp_id == tmp_id do
          %{r | sow_ear_tag: tag, force_create: false}
        else
          r
        end
      end)
      |> Enum.map(&resolve_row(&1, socket.assigns))

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

    {:noreply, assign(socket, rows: rows, error_index: nil, error_message: nil)}
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
    rows = committable_rows(socket.assigns.rows)

    entries = Enum.map(rows, &build_entry(scope, &1))

    case Breeding.record_batch_weanings_with_backfill(scope, entries) do
      {:ok, results} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Committed %{n} weanings.", n: length(results)))
         |> push_navigate(to: ~p"/farms/#{scope.farm.slug}/breeding?tab=weaned")}

      {:error, {i, reason}} ->
        {:noreply,
         assign(socket,
           error_index: i,
           error_message: format_row_error(i, reason)
         )}

      {:error, reason} ->
        {:noreply, assign(socket, error_index: nil, error_message: to_string(reason))}
    end
  end

  defp build_entry(scope, r) do
    weaned_at = parse_date(r.weaned_at)
    farrowed_at = weaned_at && Date.add(weaned_at, -Breeding.lactation_days(scope))
    served_at = farrowed_at && Date.add(farrowed_at, -Breeding.gestation_days(scope))

    base = %{
      weaned_at: r.weaned_at,
      farrowed_at: farrowed_at && to_string(farrowed_at),
      served_at: served_at && to_string(served_at),
      weaned_count: to_int_or_zero(r.weaned_count),
      avg_wean_weight_g: to_int_or_nil(r.avg_wean_weight_g),
      batch_tag: presence(r.batch_tag) || Breeding.default_wean_batch_tag(r.weaned_at),
      destination_pen_id: r.pen_id,
      pen_id: r.pen_id,
      born_alive: to_int_or_zero(r.weaned_count)
    }

    case r.sow_state do
      :existing_open ->
        Map.put(base, :sow_id, r.resolved_sow_id)

      :existing_no_farrowing ->
        Map.put(base, :sow_ear_tag, r.sow_ear_tag)

      :new ->
        base
        |> Map.put(:sow_ear_tag, r.sow_ear_tag)
        |> Map.put(:backfill_sow, %{breed: presence(r.breed)})

      :similar_overridable ->
        base
        |> Map.put(:sow_ear_tag, r.sow_ear_tag)
        |> Map.put(:backfill_sow, %{breed: presence(r.breed), force_create: true})

      _ ->
        base
    end
  end

  # ── Row helpers ──────────────────────────────────────────────────

  defp blank_row(default_date) do
    %{
      tmp_id: gen_tmp_id(),
      sow_ear_tag: "",
      sow_state: :empty,
      resolved_sow_id: nil,
      similar_tags: [],
      force_create: false,
      weaned_at: default_date,
      weaned_count: nil,
      avg_wean_weight_g: nil,
      batch_tag: Breeding.default_wean_batch_tag(default_date),
      pen_input: "",
      pen_id: nil,
      pen_state: :empty,
      breed: nil
    }
  end

  defp gen_tmp_id do
    :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
  end

  defp merge_row(row, params, assigns) do
    pen_input =
      params |> Map.get("pen_input", row.pen_input) |> to_string() |> String.trim()

    {pen_id, pen_state} = resolve_pen(pen_input, assigns.pens_by_label)
    weaned_at = Map.get(params, "weaned_at", row.weaned_at)

    %{
      row
      | sow_ear_tag:
          params |> Map.get("sow_ear_tag", row.sow_ear_tag) |> to_string() |> String.trim(),
        force_create: truthy?(Map.get(params, "force_create")),
        weaned_at: weaned_at,
        weaned_count: Map.get(params, "weaned_count", row.weaned_count),
        avg_wean_weight_g: Map.get(params, "avg_wean_weight_g", row.avg_wean_weight_g),
        batch_tag:
          refresh_row_batch_tag(
            Map.get(params, "batch_tag", row.batch_tag),
            row.weaned_at,
            weaned_at
          ),
        pen_input: pen_input,
        pen_id: pen_id,
        pen_state: pen_state,
        breed: presence(Map.get(params, "breed"))
    }
  end

  defp resolve_pen("", _pens), do: {nil, :empty}

  defp resolve_pen(label, pens) do
    case Map.get(pens, label) do
      nil -> {nil, :not_found}
      id -> {id, :found}
    end
  end

  defp resolve_row(%{sow_ear_tag: tag} = row, _assigns) when tag in [nil, ""] do
    %{row | sow_state: :empty, similar_tags: [], resolved_sow_id: nil}
  end

  defp resolve_row(%{sow_ear_tag: tag} = row, assigns) do
    scope = assigns.current_scope

    case Animals.find_by_ear_tag(scope, tag) do
      %{id: id} ->
        state =
          case Breeding.latest_open_farrowing_for_sow(scope, id) do
            nil -> :existing_no_farrowing
            _ -> :existing_open
          end

        %{row | sow_state: state, resolved_sow_id: id, similar_tags: []}

      nil ->
        case Animals.similar_ear_tags(scope, tag) do
          [] ->
            %{row | sow_state: :new, similar_tags: [], resolved_sow_id: nil}

          tags ->
            state = if row.force_create, do: :similar_overridable, else: :similar
            %{row | sow_state: state, similar_tags: tags, resolved_sow_id: nil}
        end
    end
  end

  defp committable_rows(rows) do
    Enum.filter(rows, &row_committable?/1)
  end

  defp row_committable?(row) do
    weaned_count = to_int_or_zero(row.weaned_count)

    row.sow_state in [:existing_open, :existing_no_farrowing, :new, :similar_overridable] and
      row.pen_state in [:found, :empty] and
      not is_nil(row.weaned_at) and row.weaned_at != "" and
      weaned_count > 0
  end

  defp refresh_row_batch_tag(tag, prev_weaned_at, new_weaned_at) do
    Breeding.refresh_auto_batch_tag(tag, prev_weaned_at, new_weaned_at)
  end

  defp commit_ready?(rows) do
    committable = committable_rows(rows)

    committable != [] and
      not Enum.any?(rows, &(&1.sow_state == :similar or &1.pen_state == :not_found))
  end

  defp sow_input_class(:existing_open), do: "border-success"
  defp sow_input_class(:existing_no_farrowing), do: "border-warning"
  defp sow_input_class(:new), do: "border-warning"
  defp sow_input_class(:similar), do: "border-error"
  defp sow_input_class(:similar_overridable), do: "border-warning"
  defp sow_input_class(_), do: ""

  defp row_state_text(%{sow_state: :empty}), do: ""

  defp row_state_text(%{sow_state: :existing_open}),
    do: gettext("existing sow (open farrowing)")

  defp row_state_text(%{sow_state: :existing_no_farrowing}),
    do: gettext("existing sow — will back-fill service + farrowing")

  defp row_state_text(%{sow_state: :new}),
    do: gettext("new sow — will be registered")

  defp row_state_text(%{sow_state: :similar}),
    do: gettext("similar tag exists — pick one or tick \"Create anyway\"")

  defp row_state_text(%{sow_state: :similar_overridable}),
    do: gettext("new sow (override) — will be registered")

  defp format_row_error(i, %Ecto.Changeset{errors: errors}) do
    case errors do
      [{field, {msg, _}} | _] -> "Row #{i + 1}: #{field} #{msg}"
      _ -> "Row #{i + 1} failed"
    end
  end

  defp format_row_error(i, {:similar_tag, tags}),
    do: "Row #{i + 1}: similar tag exists (#{Enum.join(tags, ", ")}) — tick \"Create anyway\""

  defp format_row_error(i, :sow_not_found),
    do: "Row #{i + 1}: sow not found and no back-fill data"

  defp format_row_error(i, :duplicate_ear_tag),
    do: "Row #{i + 1}: duplicate ear tag earlier in the grid"

  defp format_row_error(i, :weaned_at_required),
    do: "Row #{i + 1}: weaned_at is required"

  defp format_row_error(i, :served_at_required),
    do: "Row #{i + 1}: served_at could not be derived"

  defp format_row_error(i, :farrowed_at_required),
    do: "Row #{i + 1}: farrowed_at could not be derived"

  defp format_row_error(i, :gestation_out_of_range),
    do: "Row #{i + 1}: gestation window out of range"

  defp format_row_error(i, :batch_tag_required),
    do: "Row #{i + 1}: batch tag is required when weaned_count ≥ 1"

  defp format_row_error(i, other), do: "Row #{i + 1}: #{inspect(other)}"

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

  defp presence(nil), do: nil
  defp presence(""), do: nil

  defp presence(s) when is_binary(s) do
    case String.trim(s) do
      "" -> nil
      t -> t
    end
  end

  defp presence(v), do: v

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(_), do: false

  defp parse_date(%Date{} = d), do: d

  defp parse_date(s) when is_binary(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  defp parse_date(_), do: nil
end
