defmodule PeggyWeb.FarmLive.BatchCloseServices do
  @moduledoc """
  Spreadsheet-style entry for closing gestation cycles —
  abortion / death / cull — for one or many sows at once with
  back-fill cascade.

  Each row resolves a sow by ear tag (existing or back-filled), with
  optional `served_at` for inserting an inferred service when the sow
  has no open one. Defaults `served_at = result_at − 60` days.
  """
  use PeggyWeb, :live_view

  alias Peggy.{Animals, Breeding, FarmClock, Policy}

  @backfill_offset 60

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
          {gettext("Close Services")}
          <:subtitle>
            {gettext(
              "Record abortion, death, or cull — unknown ear tags become new sows on commit. Served-at defaults to result date minus 60 days."
            )}
          </:subtitle>
        </.header>

        <section class="mt-6">
          <form
            id="batch-close-services-grid"
            phx-change="update"
            phx-submit="commit"
            phx-debounce="300"
          >
            <table class="table table-sm w-full text-sm">
              <thead class="text-left text-base-content/60">
                <tr>
                  <th class="py-2 w-8">#</th>
                  <th class="py-2">{gettext("Sow ear tag")}</th>
                  <th class="py-2">{gettext("Result")}</th>
                  <th class="py-2">{gettext("Result date")}</th>
                  <th class="py-2">{gettext("Served at (backfill)")}</th>
                  <th class="py-2">{gettext("Breed (new sow)")}</th>
                  <th class="py-2">{gettext("Notes")}</th>
                  <th class="py-2 w-10"></th>
                </tr>
              </thead>
              <tbody>
                <%= for {row, i} <- Enum.with_index(@rows) do %>
                  <tr class={[
                    "border-t border-base-200 align-top",
                    @error_index == i && "bg-error/10",
                    row.sow_state == :existing && "bg-success/5",
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
                        row.sow_state == :existing && "text-success",
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
                      <select
                        name={"rows[#{row.tmp_id}][result]"}
                        class="select w-full"
                      >
                        <option value="abortion" selected={row.result == "abortion"}>
                          {gettext("Abortion")}
                        </option>
                        <option
                          value="failed_pregnancy"
                          selected={row.result == "failed_pregnancy"}
                        >
                          {gettext("Failed pregnancy")}
                        </option>
                        <option value="death" selected={row.result == "death"}>
                          {gettext("Death")}
                        </option>
                        <option value="cull" selected={row.result == "cull"}>
                          {gettext("Cull")}
                        </option>
                      </select>
                    </td>
                    <td class="py-1 px-0.5">
                      <input
                        type="date"
                        name={"rows[#{row.tmp_id}][result_at]"}
                        value={row.result_at}
                        class="input w-full"
                      />
                    </td>
                    <td class="py-1 px-0.5">
                      <input
                        type="date"
                        name={"rows[#{row.tmp_id}][served_at]"}
                        value={row.served_at}
                        class="input w-full"
                        title={gettext("Used only when the sow has no open service to close")}
                      />
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
                    <td class="py-1 px-0.5">
                      <input
                        type="text"
                        name={"rows[#{row.tmp_id}][notes]"}
                        value={row.notes}
                        class="input input-bordered w-full"
                      />
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
    today = FarmClock.today(scope)
    today_s = to_string(today)
    backfill_default = to_string(Date.add(today, -@backfill_offset))

    {:ok,
     socket
     |> assign(
       can_record: Policy.can?(scope, :record_breeding),
       rows: Enum.map(1..3, fn _ -> blank_row(today_s, backfill_default) end),
       default_result_at: today_s,
       error_index: nil,
       error_message: nil
     )}
  end

  @impl true
  def handle_event("update", params, socket) do
    row_params = Map.get(params, "rows", %{})

    rows =
      Enum.map(socket.assigns.rows, fn row ->
        case Map.get(row_params, row.tmp_id) do
          nil -> row
          p -> merge_row(row, p)
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
    rows =
      socket.assigns.rows ++
        [
          blank_row(
            socket.assigns.default_result_at,
            default_served_at(socket.assigns.default_result_at)
          )
        ]

    {:noreply, assign(socket, rows: rows)}
  end

  def handle_event("add_rows", %{"count" => n}, socket) do
    count = String.to_integer(n)
    served_default = default_served_at(socket.assigns.default_result_at)

    extra =
      Enum.map(1..count, fn _ -> blank_row(socket.assigns.default_result_at, served_default) end)

    {:noreply, assign(socket, rows: socket.assigns.rows ++ extra)}
  end

  def handle_event("remove_row", %{"id" => tmp_id}, socket) do
    rows = Enum.reject(socket.assigns.rows, &(&1.tmp_id == tmp_id))

    rows =
      if rows == [],
        do: [
          blank_row(
            socket.assigns.default_result_at,
            default_served_at(socket.assigns.default_result_at)
          )
        ],
        else: rows

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
    entries = Enum.map(rows, &build_entry/1)

    case Breeding.record_batch_close_services_with_backfill(scope, entries) do
      {:ok, services} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Closed %{n} services.", n: length(services)))
         |> push_navigate(to: ~p"/farms/#{scope.farm.slug}/breeding")}

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

  defp build_entry(r) do
    base = %{
      result: r.result,
      result_at: r.result_at,
      served_at: r.served_at,
      notes: r.notes
    }

    case r.sow_state do
      :existing ->
        Map.put(base, :sow_id, r.resolved_sow_id)

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

  defp blank_row(default_result_at, default_served_at) do
    %{
      tmp_id: gen_tmp_id(),
      sow_ear_tag: "",
      sow_state: :empty,
      resolved_sow_id: nil,
      similar_tags: [],
      force_create: false,
      result: "abortion",
      result_at: default_result_at,
      served_at: default_served_at,
      served_at_user_set?: false,
      breed: nil,
      notes: nil
    }
  end

  defp gen_tmp_id do
    :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
  end

  defp merge_row(row, params) do
    new_result_at = Map.get(params, "result_at", row.result_at)
    new_served_at_input = Map.get(params, "served_at", row.served_at)

    # Track whether the user has explicitly typed a served_at distinct
    # from the auto-derived default. Once they have, stop auto-syncing.
    user_set? =
      row.served_at_user_set? or
        (new_served_at_input != row.served_at and
           new_served_at_input != derive_served_at(new_result_at) and
           new_served_at_input != "")

    served_at =
      if user_set?,
        do: new_served_at_input,
        else: derive_served_at(new_result_at)

    %{
      row
      | sow_ear_tag:
          params |> Map.get("sow_ear_tag", row.sow_ear_tag) |> to_string() |> String.trim(),
        force_create: truthy?(Map.get(params, "force_create")),
        result: Map.get(params, "result", row.result),
        result_at: new_result_at,
        served_at: served_at,
        served_at_user_set?: user_set?,
        breed: presence(Map.get(params, "breed")),
        notes: Map.get(params, "notes")
    }
  end

  defp derive_served_at(""), do: ""

  defp derive_served_at(date_s) when is_binary(date_s) do
    case Date.from_iso8601(date_s) do
      {:ok, d} -> to_string(Date.add(d, -@backfill_offset))
      _ -> date_s
    end
  end

  defp derive_served_at(_), do: ""

  defp default_served_at(""), do: ""
  defp default_served_at(s), do: derive_served_at(s)

  defp resolve_row(%{sow_ear_tag: tag} = row, _assigns) when tag in [nil, ""] do
    %{row | sow_state: :empty, similar_tags: [], resolved_sow_id: nil}
  end

  defp resolve_row(%{sow_ear_tag: tag} = row, assigns) do
    scope = assigns.current_scope

    case Animals.find_by_ear_tag(scope, tag) do
      %{id: id} ->
        %{row | sow_state: :existing, resolved_sow_id: id, similar_tags: []}

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
    row.sow_state in [:existing, :new, :similar_overridable] and
      presence(row.result_at) != nil and
      row.result in ~w(abortion death cull)
  end

  defp commit_ready?(rows) do
    committable = committable_rows(rows)
    committable != [] and not Enum.any?(rows, &(&1.sow_state == :similar))
  end

  defp sow_input_class(:existing), do: "border-success"
  defp sow_input_class(:new), do: "border-warning"
  defp sow_input_class(:similar), do: "border-error"
  defp sow_input_class(:similar_overridable), do: "border-warning"
  defp sow_input_class(_), do: ""

  defp row_state_text(%{sow_state: :empty}), do: ""
  defp row_state_text(%{sow_state: :existing}), do: gettext("existing sow")
  defp row_state_text(%{sow_state: :new}), do: gettext("new sow — will be registered (backfill)")

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
    do: "Row #{i + 1}: sow ear tag missing"

  defp format_row_error(i, :result_at_required),
    do: "Row #{i + 1}: result date required"

  defp format_row_error(i, :result_invalid),
    do: "Row #{i + 1}: result must be abortion, death, or cull"

  defp format_row_error(i, :already_closed),
    do: "Row #{i + 1}: sow's open service is already closed"

  defp format_row_error(i, other), do: "Row #{i + 1}: #{inspect(other)}"

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
end
