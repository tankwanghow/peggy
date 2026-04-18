defmodule PeggyWeb.FarmLive.HerdImport do
  @moduledoc """
  Onboarding wizard for importing an existing herd into a fresh farm.

  The key feature over plain batch registration is that each row can
  carry breeding history — `served` sows get an open `Service`,
  `lactating` sows get a closed service + farrowing (+ litter batch).
  Without this, every imported sow collapses to `active` and the
  reproductive KPIs start broken.

  See `Peggy.Animals.import_herd/2` for the atomic commit logic.
  """
  use PeggyWeb, :live_view

  alias Peggy.{Animals, Locations, Policy}
  alias Peggy.Animals.Animal

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-7xl">
        <div class="text-sm text-base-content/60 mb-1">
          <.link
            navigate={~p"/farms/#{@current_scope.farm.slug}/animals"}
            class="text-primary underline hover:text-primary/80"
          >
            ← {gettext("Animals")}
          </.link>
        </div>

        <.header>
          {gettext("Initial herd import")}
          <:subtitle>
            {gettext(
              "Import existing animals at onboarding. Status-aware: served/lactating sows get matching breeding history so KPIs start coherent."
            )}
          </:subtitle>
        </.header>

        <section class="mt-6">
          <div class="alert alert-info text-xs mb-4">
            {gettext(
              "Tip: set status to \"served\" with a last-service date to create an open gestation. Use \"lactating\" with a farrowing date + born-alive to create a closed service, farrowing, and litter batch."
            )}
          </div>

          <form
            id="herd-import-grid"
            phx-change="update"
            phx-submit="commit"
            phx-debounce="300"
          >
            <table class="table table-sm w-full text-sm">
              <thead class="text-left text-base-content/60">
                <tr>
                  <th class="py-2 w-8">#</th>
                  <th class="py-2">{gettext("Ear tag")}</th>
                  <th class="py-2">{gettext("Stage")}</th>
                  <th class="py-2">{gettext("Sex")}</th>
                  <th class="py-2">{gettext("Status")}</th>
                  <th class="py-2">{gettext("DOB")}</th>
                  <th class="py-2">{gettext("Pen")}</th>
                  <th class="py-2">{gettext("Last served")}</th>
                  <th class="py-2">{gettext("Last farrowed")}</th>
                  <th class="py-2">{gettext("Born alive")}</th>
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
                    <input
                      type="text"
                      name={"rows[#{row.tmp_id}][ear_tag]"}
                      value={row.ear_tag || ""}
                      class="input input-sm w-full font-mono"
                      placeholder={gettext("Tag...")}
                    />
                  </td>
                  <td class="py-1 px-1">
                    <select name={"rows[#{row.tmp_id}][stage]"} class="select select-sm w-full">
                      <option
                        :for={s <- Animal.stages_for("individual")}
                        value={s}
                        selected={row.stage == s}
                      >
                        {String.capitalize(s)}
                      </option>
                    </select>
                  </td>
                  <td class="py-1 px-1">
                    <select name={"rows[#{row.tmp_id}][sex]"} class="select select-sm w-full">
                      <option :for={s <- Animal.sexes()} value={s} selected={row.sex == s}>
                        {String.capitalize(s)}
                      </option>
                    </select>
                  </td>
                  <td class="py-1 px-1">
                    <select
                      name={"rows[#{row.tmp_id}][status]"}
                      class="select select-sm w-full"
                      title={Animal.status_description(row.status)}
                    >
                      <option
                        :for={st <- importable_statuses()}
                        value={st}
                        selected={row.status == st}
                      >
                        {String.capitalize(st)}
                      </option>
                    </select>
                  </td>
                  <td class="py-1 px-1">
                    <input
                      type="date"
                      name={"rows[#{row.tmp_id}][dob]"}
                      value={row.dob || ""}
                      class="input input-sm w-full"
                    />
                  </td>
                  <td class="py-1 px-1">
                    <select
                      name={"rows[#{row.tmp_id}][current_pen_id]"}
                      class="select select-sm w-full"
                    >
                      <option value="">—</option>
                      <option :for={p <- @pen_items} value={p.id} selected={row.pen_id == p.id}>
                        {p.label}
                      </option>
                    </select>
                  </td>
                  <td class="py-1 px-1">
                    <input
                      type="date"
                      name={"rows[#{row.tmp_id}][last_served_at]"}
                      value={row.last_served_at || ""}
                      class="input input-sm w-full"
                      disabled={row.status not in ~w(served lactating)}
                    />
                  </td>
                  <td class="py-1 px-1">
                    <input
                      type="date"
                      name={"rows[#{row.tmp_id}][last_farrowed_at]"}
                      value={row.last_farrowed_at || ""}
                      class="input input-sm w-full"
                      disabled={row.status != "lactating"}
                    />
                  </td>
                  <td class="py-1 px-1">
                    <input
                      type="number"
                      min="0"
                      name={"rows[#{row.tmp_id}][born_alive]"}
                      value={row.born_alive || ""}
                      class="input input-sm w-20"
                      disabled={row.status != "lactating"}
                    />
                  </td>
                  <td class="py-1 px-1">
                    <button
                      type="button"
                      phx-click="remove_row"
                      phx-value-id={row.tmp_id}
                      class="btn btn-ghost btn-xs text-error"
                      aria-label={gettext("Remove row")}
                    >
                      ✕
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>

            <p :if={@error_message} class="mt-3 text-sm text-error">{@error_message}</p>

            <div class="mt-4 flex gap-2 items-center">
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
                  phx-disable-with={gettext("Importing...")}
                  disabled={non_empty_rows(@rows) == []}
                >
                  {gettext("Import %{n} animals", n: length(non_empty_rows(@rows)))}
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
    pen_items = pen_items(scope)

    {:ok,
     socket
     |> assign(
       can_manage: Policy.can?(scope, :manage_animals),
       pen_items: pen_items,
       rows: Enum.map(1..3, fn _ -> blank_row() end),
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
          row_params -> merge_row(row, row_params)
        end
      end)

    {:noreply, assign(socket, rows: rows, error_index: nil, error_message: nil)}
  end

  def handle_event("add_rows", %{"count" => n}, socket) do
    count = String.to_integer(n)
    extra = Enum.map(1..count, fn _ -> blank_row() end)
    {:noreply, assign(socket, rows: socket.assigns.rows ++ extra)}
  end

  def handle_event("remove_row", %{"id" => tmp_id}, socket) do
    rows = Enum.reject(socket.assigns.rows, &(&1.tmp_id == tmp_id))
    rows = if rows == [], do: [blank_row()], else: rows
    {:noreply, assign(socket, rows: rows, error_index: nil, error_message: nil)}
  end

  def handle_event("commit", _params, socket) do
    if socket.assigns.can_manage do
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
          tracking_type: "individual",
          ear_tag: r.ear_tag,
          stage: r.stage,
          sex: r.sex,
          status: r.status,
          dob: r.dob,
          current_pen_id: r.pen_id,
          last_served_at: r.last_served_at,
          last_farrowed_at: r.last_farrowed_at,
          born_alive: r.born_alive
        }
      end)

    case Animals.import_herd(scope, entries) do
      {:ok, animals} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Imported %{n} animals.", n: length(animals)))
         |> push_navigate(to: ~p"/farms/#{scope.farm.slug}/animals")}

      {:error, {i, cs_or_reason}} ->
        {:noreply,
         assign(socket,
           error_index: i,
           error_message: format_row_error(i, cs_or_reason)
         )}

      {:error, reason} ->
        {:noreply, assign(socket, error_index: nil, error_message: to_string(reason))}
    end
  end

  # ── Row helpers ──────────────────────────────────────────────────

  defp blank_row do
    %{
      tmp_id: gen_tmp_id(),
      ear_tag: nil,
      stage: "sow",
      sex: "female",
      status: "active",
      dob: nil,
      pen_id: nil,
      last_served_at: nil,
      last_farrowed_at: nil,
      born_alive: nil
    }
  end

  defp gen_tmp_id do
    :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
  end

  defp merge_row(row, params) do
    stage = Map.get(params, "stage", row.stage)
    sex = auto_sex(stage, Map.get(params, "sex", row.sex))

    %{
      row
      | ear_tag: Map.get(params, "ear_tag"),
        stage: stage,
        sex: sex,
        status: Map.get(params, "status", row.status),
        dob: Map.get(params, "dob"),
        pen_id: parse_int(Map.get(params, "current_pen_id")),
        last_served_at: Map.get(params, "last_served_at"),
        last_farrowed_at: Map.get(params, "last_farrowed_at"),
        born_alive: Map.get(params, "born_alive")
    }
  end

  defp auto_sex("sow", _), do: "female"
  defp auto_sex("boar", _), do: "male"
  defp auto_sex(_, sex), do: sex

  defp non_empty_rows(rows) do
    Enum.filter(rows, fn r -> r.ear_tag not in [nil, ""] end)
  end

  # Statuses that make sense at import time. Departed statuses
  # (`sold` / `deceased` / `slaughtered` / `transferred`) are
  # intentionally excluded — there's no reason to import an animal
  # that has already left.
  defp importable_statuses, do: ~w(active served open lactating dry culled)

  defp pen_items(scope) do
    scope
    |> Locations.list_all_pens()
    |> Enum.map(&%{id: &1.id, label: "#{&1.house.code}/#{&1.code}"})
  end

  defp format_row_error(i, %Ecto.Changeset{errors: errors}) do
    case errors do
      [{field, {msg, _}} | _] -> "Row #{i + 1}: #{field} #{msg}"
      _ -> "Row #{i + 1} failed"
    end
  end

  defp format_row_error(i, reason) when is_binary(reason), do: "Row #{i + 1}: #{reason}"
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
