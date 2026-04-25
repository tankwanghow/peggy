defmodule PeggyWeb.FarmLive.BatchRegister do
  @moduledoc """
  Spreadsheet-style batch entry for registering multiple individual
  animals at once in one atomic commit.
  """
  use PeggyWeb, :live_view

  alias Peggy.{Animals, Locations, Policy}
  alias Peggy.Animals.Animal

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
            ← {gettext("Animals")}
          </.link>
        </div>

        <.header>
          {gettext("Batch Register")}
          <:subtitle>{gettext("Register multiple individual animals at once")}</:subtitle>
        </.header>

        <section class="mt-6">
          <form
            id="batch-register-grid"
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
                  <th class="py-2">{gettext("Breed")}</th>
                  <th class="py-2">{gettext("DOB")}</th>
                  <th class="py-2">{gettext("Pen")}</th>

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
                      class="input  w-full font-mono"
                      placeholder={gettext("Tag...")}
                    />
                  </td>
                  <td class="py-1 px-1">
                    <select
                      name={"rows[#{row.tmp_id}][stage]"}
                      class="select  w-full"
                    >
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
                    <input
                      type="text"
                      name={"rows[#{row.tmp_id}][breed]"}
                      value={row.breed || ""}
                      class="input  w-full"
                    />
                  </td>
                  <td class="py-1 px-1">
                    <input
                      type="date"
                      name={"rows[#{row.tmp_id}][dob]"}
                      value={row.dob || ""}
                      class="input  w-full"
                    />
                  </td>
                  <td class="py-1 px-1">
                    <.autocomplete
                      id={"row-#{row.tmp_id}-pen"}
                      label=""
                      name={"rows[#{row.tmp_id}][current_pen_id]"}
                      value={row.pen_id}
                      items={@pen_items}
                      selected_label={row.pen_label}
                      class="input  w-full font-mono"
                      placeholder={gettext("Pen...")}
                    />
                  </td>

                  <td class="py-1 px-1 text-right">
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
    rows = if rows == [], do: [blank_row()], else: rows

    {:noreply,
     socket
     |> assign(rows: rows, error_index: nil, error_message: nil)
     |> push_event("ac:reset", %{id: "row-#{tmp_id}-pen"})}
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
          ear_tag: r.ear_tag,
          stage: r.stage,
          breed: r.breed,
          dob: r.dob,
          current_pen_id: r.pen_id,
          notes: r.notes
        }
      end)

    case Animals.create_batch_animals(scope, entries) do
      {:ok, animals} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Registered %{n} animals.", n: length(animals)))
         |> push_navigate(to: ~p"/farms/#{scope.farm.slug}/animals")}

      {:error, {i, cs}} ->
        {:noreply, assign(socket, error_index: i, error_message: format_row_error(i, cs))}

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
      breed: nil,
      dob: nil,
      pen_id: nil,
      pen_label: nil,
      notes: nil
    }
  end

  defp gen_tmp_id do
    :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
  end

  defp merge_row(row, params, assigns) do
    stage = Map.get(params, "stage", row.stage)
    pen_id = parse_int(Map.get(params, "current_pen_id"))

    %{
      row
      | ear_tag: Map.get(params, "ear_tag"),
        stage: stage,
        breed: Map.get(params, "breed"),
        dob: Map.get(params, "dob"),
        pen_id: pen_id,
        pen_label: lookup_label(assigns.pen_items, pen_id),
        notes: Map.get(params, "notes")
    }
  end

  defp non_empty_rows(rows) do
    Enum.filter(rows, fn r ->
      r.ear_tag != nil and r.ear_tag != ""
    end)
  end

  defp pen_items(scope) do
    scope
    |> Locations.list_all_pens()
    |> Enum.map(&%{id: &1.id, label: "#{&1.house.code}-#{&1.code}"})
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
