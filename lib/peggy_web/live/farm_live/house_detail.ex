defmodule PeggyWeb.FarmLive.HouseDetail do
  use PeggyWeb, :live_view

  alias Peggy.Locations
  alias Peggy.Locations.Pen
  alias Peggy.Policy

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-6xl">
        <div class="text-sm text-base-content/60 mb-1">
          <.link
            navigate={~p"/farms/#{@current_scope.farm.slug}/locations"}
            class="text-primary underline hover:text-primary/80"
          >
            ← {gettext("All locations")}
          </.link>
        </div>
        <.header>
          <span class="font-mono">{@house.code}</span>
          <span class="ml-2 text-base-content/60 text-base font-normal">
            {@house.purpose} · {@pen_count} {gettext("pens")}
          </span>
        </.header>

        <section
          :if={@can_manage}
          class="mt-4 rounded border border-base-300 p-4 bg-base-200/40"
        >
          <button type="button" phx-click="toggle_generator" class="font-medium cursor-pointer">
            {if @gen_open, do: "▼", else: "▶"} {gettext("Generate pens in bulk")}
          </button>
          <div :if={@gen_open} class="mt-3">
            <.form
              for={@gen_form}
              id="generate-form"
              phx-submit="generate"
              phx-change="validate_generate"
              class="mt-3 grid grid-cols-2 md:grid-cols-6 gap-3"
            >
              <.input
                field={@gen_form[:prefix]}
                type="text"
                label={gettext("Prefix")}
                class="w-full input font-mono"
              />
              <.input field={@gen_form[:from]} type="number" label={gettext("From")} min="0" />
              <.input field={@gen_form[:to]} type="number" label={gettext("To")} min="0" />
              <.input
                field={@gen_form[:pad]}
                type="number"
                label={gettext("Pad digits")}
                min="0"
                max="6"
              />
              <.input
                field={@gen_form[:capacity]}
                type="number"
                label={gettext("Capacity each")}
                min="0"
              />
              <.input
                field={@gen_form[:status]}
                type="select"
                label={gettext("Status")}
                options={Enum.map(Pen.statuses(), &{String.capitalize(&1), &1})}
              />
              <div class="col-span-2 md:col-span-6 flex justify-end gap-2">
                <span class="text-sm self-center text-base-content/60">
                  {gettext("Preview:")} {preview_codes(@gen_form.source)}
                </span>
                <.button class="btn btn-primary btn-sm" phx-disable-with={gettext("Creating...")}>
                  {gettext("Create pens")}
                </.button>
              </div>
            </.form>
          </div>
        </section>

        <div :if={@can_manage && MapSet.size(@selected) > 0} class="mt-4 flex gap-2 items-center">
          <span class="text-sm">
            {gettext("%{n} selected", n: MapSet.size(@selected))}
          </span>
          <button
            phx-click="bulk_delete"
            data-confirm={gettext("Delete selected pens?")}
            class="btn btn-sm btn-error"
          >
            {gettext("Delete selected")}
          </button>
          <button phx-click="clear_selection" class="btn btn-sm btn-ghost">
            {gettext("Clear")}
          </button>
        </div>

        <div class="mt-4 overflow-x-auto">
          <table class="table table-sm">
            <thead class="sticky top-0 bg-base-100">
              <tr>
                <th :if={@can_manage} class="w-6"></th>
                <th>{gettext("Code")}</th>
                <th>{gettext("Capacity")}</th>
                <th>{gettext("Status")}</th>
                <th :if={@can_manage} class="w-16"></th>
              </tr>
            </thead>
            <tbody id="pens" phx-update="stream">
              <tr :for={{dom_id, p} <- @streams.pens} id={dom_id}>
                <td :if={@can_manage} class="!py-0.5">
                  <input
                    type="checkbox"
                    class="checkbox checkbox-sm"
                    checked={MapSet.member?(@selected, p.id)}
                    phx-click="toggle_select"
                    phx-value-id={p.id}
                  />
                </td>
                <%= if @can_manage do %>
                  <td colspan="3" class="!py-0.5">
                    <.form
                      for={to_form(%{}, as: :pen)}
                      id={"pen-form-#{p.id}"}
                      phx-change="update_pen"
                      phx-submit="update_pen"
                      phx-value-id={p.id}
                      class="contents"
                    >
                      <div class="grid grid-cols-3 gap-1.5">
                        <input
                          type="text"
                          name="pen[code]"
                          value={p.code}
                          phx-debounce="blur"
                          class="input input-bordered font-mono"
                          required
                        />
                        <input
                          type="number"
                          name="pen[capacity]"
                          value={p.capacity}
                          phx-debounce="blur"
                          min="0"
                          class="input input-bordered"
                        />
                        <select name="pen[status]" class="select select-bordered">
                          <option
                            :for={s <- Pen.statuses()}
                            value={s}
                            selected={s == p.status}
                          >
                            {String.capitalize(s)}
                          </option>
                        </select>
                      </div>
                    </.form>
                  </td>
                <% else %>
                  <td class="!py-0.5 font-mono">{p.code}</td>
                  <td class="!py-0.5">{p.capacity}</td>
                  <td class="!py-0.5">{p.status}</td>
                <% end %>
                <td :if={@can_manage} class="!py-0.5">
                  <button
                    phx-click="delete_pen"
                    phx-value-id={p.id}
                    data-confirm={gettext("Delete pen?")}
                    class="btn btn-xs btn-ghost text-error"
                  >
                    {gettext("Delete")}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div :if={@can_manage} class="mt-4 rounded border border-base-300 p-3">
          <h3 class="font-medium mb-2">{gettext("Add single pen")}</h3>
          <.form
            for={@new_form}
            id="new-pen-form"
            phx-submit="create_pen"
            phx-change="validate_new"
            class="grid grid-cols-2 md:grid-cols-4 gap-2"
          >
            <.input
              field={@new_form[:code]}
              type="text"
              placeholder={gettext("Code")}
              class="w-full input font-mono"
            />
            <.input
              field={@new_form[:capacity]}
              type="number"
              placeholder={gettext("Capacity")}
              min="0"
            />
            <.input
              field={@new_form[:status]}
              type="select"
              options={Enum.map(Pen.statuses(), &{String.capitalize(&1), &1})}
            />
            <.button class="btn btn-primary btn-sm">{gettext("Add")}</.button>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    house = Locations.get_house!(scope, String.to_integer(id))
    pens = Locations.list_pens(scope, house)

    {:ok,
     socket
     |> assign(:house, house)
     |> assign(:pen_count, length(pens))
     |> assign(:can_manage, Policy.can?(scope, :manage_locations))
     |> assign(:selected, MapSet.new())
     |> assign(:gen_open, false)
     |> assign(:gen_form, to_form(default_gen_params(), as: :gen))
     |> assign(
       :new_form,
       to_form(Locations.change_pen(%Pen{status: "active", capacity: 0}), as: :pen)
     )
     |> stream(:pens, pens)}
  end

  @impl true
  def handle_event("toggle_select", %{"id" => id}, socket) do
    id = String.to_integer(id)

    selected =
      if MapSet.member?(socket.assigns.selected, id) do
        MapSet.delete(socket.assigns.selected, id)
      else
        MapSet.put(socket.assigns.selected, id)
      end

    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("toggle_generator", _, socket),
    do: {:noreply, update(socket, :gen_open, &(!&1))}

  def handle_event("clear_selection", _, socket) do
    ids = MapSet.to_list(socket.assigns.selected)

    socket =
      Enum.reduce(ids, socket, fn id, acc ->
        pen = Locations.get_pen!(acc.assigns.current_scope, id)
        stream_insert(acc, :pens, pen)
      end)

    {:noreply, assign(socket, :selected, MapSet.new())}
  end

  def handle_event("update_pen", %{"id" => id, "pen" => attrs}, socket) do
    guard(socket, fn ->
      pen = Locations.get_pen!(socket.assigns.current_scope, String.to_integer(id))

      case Locations.update_pen(socket.assigns.current_scope, pen, attrs) do
        {:ok, p} ->
          {:noreply, stream_insert(socket, :pens, p)}

        {:error, cs} ->
          msg = cs |> errors_summary()
          {:noreply, put_flash(socket, :error, gettext("Save failed: %{m}", m: msg))}
      end
    end)
  end

  def handle_event("delete_pen", %{"id" => id}, socket) do
    guard(socket, fn ->
      id = String.to_integer(id)
      pen = Locations.get_pen!(socket.assigns.current_scope, id)
      {:ok, _} = Locations.delete_pen(socket.assigns.current_scope, pen)

      {:noreply,
       socket
       |> stream_delete(:pens, pen)
       |> update(:pen_count, &(&1 - 1))
       |> update(:selected, &MapSet.delete(&1, id))}
    end)
  end

  def handle_event("bulk_delete", _, socket) do
    guard(socket, fn ->
      ids = MapSet.to_list(socket.assigns.selected)

      case Locations.bulk_delete_pens(socket.assigns.current_scope, ids) do
        {:ok, _n} ->
          socket =
            Enum.reduce(ids, socket, fn id, acc ->
              Phoenix.LiveView.stream_delete_by_dom_id(acc, :pens, "pens-#{id}")
            end)

          {:noreply,
           socket
           |> assign(:selected, MapSet.new())
           |> update(:pen_count, &(&1 - length(ids)))
           |> put_flash(:info, gettext("%{n} pens deleted.", n: length(ids)))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Bulk delete failed."))}
      end
    end)
  end

  def handle_event("validate_new", %{"pen" => attrs}, socket) do
    cs =
      %Pen{status: "active", capacity: 0}
      |> Locations.change_pen(attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :new_form, to_form(cs, as: :pen))}
  end

  def handle_event("create_pen", %{"pen" => attrs}, socket) do
    guard(socket, fn ->
      case Locations.create_pen(socket.assigns.current_scope, socket.assigns.house, attrs) do
        {:ok, p} ->
          {:noreply,
           socket
           |> stream_insert(:pens, p, at: -1)
           |> update(:pen_count, &(&1 + 1))
           |> assign(
             :new_form,
             to_form(Locations.change_pen(%Pen{status: "active", capacity: 0}), as: :pen)
           )}

        {:error, cs} ->
          {:noreply, assign(socket, :new_form, to_form(cs, as: :pen))}
      end
    end)
  end

  def handle_event("validate_generate", %{"gen" => params}, socket),
    do: {:noreply, assign(socket, :gen_form, to_form(params, as: :gen))}

  def handle_event("generate", %{"gen" => params}, socket) do
    guard(socket, fn ->
      case build_rows(params) do
        {:ok, []} ->
          {:noreply, put_flash(socket, :error, gettext("From/To range is empty."))}

        {:ok, rows} ->
          case Locations.bulk_create_pens(
                 socket.assigns.current_scope,
                 socket.assigns.house,
                 rows
               ) do
            {:ok, pens} ->
              socket =
                Enum.reduce(pens, socket, fn p, acc -> stream_insert(acc, :pens, p, at: -1) end)

              {:noreply,
               socket
               |> update(:pen_count, &(&1 + length(pens)))
               |> assign(:gen_form, to_form(default_gen_params(), as: :gen))
               |> put_flash(:info, gettext("%{n} pens created.", n: length(pens)))}

            {:error, idx, cs} ->
              {:noreply,
               put_flash(
                 socket,
                 :error,
                 gettext("Row %{i} invalid: %{m}", i: idx + 1, m: errors_summary(cs))
               )}
          end

        {:error, msg} ->
          {:noreply, put_flash(socket, :error, msg)}
      end
    end)
  end

  ## Helpers

  defp guard(socket, fun) do
    if socket.assigns.can_manage do
      fun.()
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  defp default_gen_params,
    do: %{
      "prefix" => "",
      "from" => "1",
      "to" => "20",
      "pad" => "3",
      "capacity" => "20",
      "status" => "active"
    }

  defp build_rows(%{"from" => from, "to" => to} = p) do
    with {f, _} <- Integer.parse(to_string(from || "")),
         {t, _} <- Integer.parse(to_string(to || "")),
         true <- t >= f do
      prefix = p["prefix"] || ""
      pad = parse_int(p["pad"], 0)
      capacity = parse_int(p["capacity"], 0)
      status = p["status"] || "active"

      rows =
        f..t
        |> Enum.map(fn n ->
          num = n |> Integer.to_string() |> String.pad_leading(pad, "0")
          code = prefix <> num

          %{
            "code" => code,
            "capacity" => capacity,
            "status" => status
          }
        end)

      {:ok, rows}
    else
      false -> {:error, gettext("From must be ≤ To.")}
      _ -> {:error, gettext("Invalid range.")}
    end
  end

  defp build_rows(_), do: {:error, gettext("Invalid range.")}

  defp parse_int(nil, default), do: default
  defp parse_int(v, _default) when is_integer(v), do: v

  defp parse_int(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      _ -> default
    end
  end

  defp preview_codes(%{} = source) do
    case build_rows(source) do
      {:ok, [_ | _] = rows} ->
        codes = Enum.map(rows, & &1["code"])
        first = List.first(codes)
        last = List.last(codes)

        if length(codes) <= 2,
          do: Enum.join(codes, ", "),
          else: "#{first} … #{last} (#{length(codes)})"

      _ ->
        "—"
    end
  end

  defp errors_summary(%Ecto.Changeset{} = cs) do
    cs.errors
    |> Enum.map(fn {k, {msg, _}} -> "#{k} #{msg}" end)
    |> Enum.join("; ")
  end
end
