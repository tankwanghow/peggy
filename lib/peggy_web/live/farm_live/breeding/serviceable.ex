defmodule PeggyWeb.FarmLive.Breeding.Serviceable do
  @moduledoc """
  Serviceable tab of the Breeding section. Lists sows ready for a new
  service (status active / open / dry; excludes served, lactating, and
  departed). Each row links through to the Gestating service form,
  pre-filled with the sow's ear tag.
  """
  use PeggyWeb, :live_view

  alias Peggy.{Animals, Breeding, FarmClock, Policy}
  alias PeggyWeb.FarmLive.Breeding.Shared

  @per_page Shared.per_page()

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-6xl">
        <.header>
          {gettext("Serviceable")}
          <:subtitle>{gettext("Sows ready for a new service")}</:subtitle>
        </.header>

        <section class="mt-4">
          <form
            id="serviceable-filters"
            phx-change="filter_serviceable"
            phx-submit="filter_serviceable"
            class="flex gap-1 flex-nowrap items-end overflow-x-auto"
          >
            <label class="form-control w-32">
              <div class="label py-1">
                <span class="label-text text-xs">{gettext("Sow tag")}</span>
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
            <label class="form-control w-44">
              <div class="label py-1">
                <span class="label-text text-xs">{gettext("Status")}</span>
              </div>
              <select name="status" class="select select-sm select-bordered">
                <option value="all" selected={@filters.status == "all"}>
                  {gettext("All")}
                </option>
                <option value="open" selected={@filters.status == "open"}>{gettext("Open")}</option>
                <option value="dry" selected={@filters.status == "dry"}>{gettext("Dry")}</option>
                <option value="active" selected={@filters.status == "active"}>
                  {gettext("Active")}
                </option>
                <option
                  value="served_outside_window"
                  selected={@filters.status == "served_outside_window"}
                >
                  {gettext("Served (still in heat)")}
                </option>
              </select>
            </label>
            <label class="form-control w-28">
              <div class="label py-1">
                <span class="label-text text-xs">{gettext("Pen")}</span>
              </div>
              <input
                type="text"
                name="pen_search"
                value={@filters.pen_search}
                phx-debounce="300"
                placeholder={gettext("H-P")}
                class="input input-sm input-bordered font-mono"
              />
            </label>
            <label class="form-control w-20">
              <div class="label py-1">
                <span class="label-text text-xs">{gettext("Min parity")}</span>
              </div>
              <input
                type="number"
                name="min_parity"
                value={@filters.min_parity}
                min="0"
                phx-debounce="300"
                class="input input-sm input-bordered"
              />
            </label>
            <label class="form-control w-20">
              <div class="label py-1">
                <span class="label-text text-xs">{gettext("Max parity")}</span>
              </div>
              <input
                type="number"
                name="max_parity"
                value={@filters.max_parity}
                min="0"
                phx-debounce="300"
                class="input input-sm input-bordered"
              />
            </label>
          </form>

          <div class="mt-4 overflow-x-auto">
            <table class="table table-sm w-full">
              <thead class="text-left text-base-content/60">
                <tr>
                  <th class="py-2">
                    <.sort_header label={gettext("Sow")} col="tag" sort={@sort} dir={@dir} />
                  </th>
                  <th class="py-2">
                    <.sort_header label={gettext("Status")} col="status" sort={@sort} dir={@dir} />
                  </th>
                  <th class="py-2">
                    <.sort_header label={gettext("Pen")} col="pen" sort={@sort} dir={@dir} />
                  </th>
                  <th class="py-2 text-right">
                    <.sort_header
                      label={gettext("Parity")}
                      col="parity"
                      sort={@sort}
                      dir={@dir}
                      align="right"
                    />
                  </th>
                  <th class="py-2">{gettext("Last event")}</th>
                  <th class="py-2 text-right">
                    <.sort_header
                      label={gettext("Idle(d)")}
                      col="idle"
                      sort={@sort}
                      dir={@dir}
                      align="right"
                    />
                  </th>
                  <th :if={@can_record} class="py-2"></th>
                </tr>
              </thead>
              <tbody id="serviceable-rows" phx-update="stream">
                <tr
                  :for={{dom_id, e} <- @streams.serviceable}
                  id={dom_id}
                  class="border-t border-base-200"
                >
                  <td class="py-2 font-mono font-semibold">
                    <.link
                      navigate={~p"/farms/#{@current_scope.farm.slug}/animals/#{e.animal.id}"}
                      class="text-primary underline underline-offset-2 decoration-dotted hover:decoration-solid"
                    >
                      {e.animal.ear_tag}
                    </.link>
                    <span :if={e.parity == 0} class="ml-1 badge badge-sm badge-info">
                      {gettext("Gilt")}
                    </span>
                    <Shared.recently_updated_badge at={e.animal.updated_at} />
                  </td>
                  <td class="py-2">
                    <span class={["uppercase font-semibold", status_color(e.animal.status)]}>
                      {e.animal.status}
                    </span>
                    <span
                      :if={e.animal.status == "served"}
                      class="ml-1 badge badge-sm badge-warning"
                      title={gettext("Still in heat — record another mounting if needed")}
                    >
                      {gettext("in heat")}
                    </span>
                  </td>
                  <td class="py-2 font-mono text-base-content/70">
                    {sow_pen_label(e.animal)}
                  </td>
                  <td class="py-2 text-right font-mono">{e.parity}</td>
                  <td class="py-2 text-xs text-base-content/70">
                    <Shared.last_event entry={e} />
                  </td>
                  <td class={[
                    "py-2 text-right font-mono",
                    idle_color(e.days_idle)
                  ]}>
                    {idle_text(e.days_idle)}
                  </td>
                  <td :if={@can_record} class="py-2 text-right">
                    <button
                      phx-click="open_service"
                      phx-value-sow-id={e.animal.id}
                      class="btn btn-sm btn-primary"
                    >
                      {if e.animal.status == "served",
                        do: gettext("+ Mount"),
                        else: gettext("Service")}
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
            <p :if={@total == 0} class="mt-2 text-sm text-base-content/60">
              {gettext("No serviceable females match the filters.")}
            </p>
          </div>

          <.infinite_scroll
            has_more={@has_more}
            total={@total}
            id="serviceable-sentinel"
          />
        </section>

        <Shared.modal :if={@svc} title={gettext("Record Service")} on_cancel="cancel_service">
          <form
            id="serviceable-service-form"
            phx-change="validate_service"
            phx-submit="save_service"
            phx-debounce="300"
            class="grid grid-cols-2 gap-x-4 gap-y-3"
          >
            <div class="col-span-2 text-sm">
              <span class="text-base-content/60">{gettext("Sow:")}</span>
              <span class="font-mono font-semibold ml-1">{@svc.sow_tag}</span>
              <span class="ml-2 text-xs text-base-content/50">
                ({@svc.sow_status})
              </span>
            </div>

            <div>
              <label class="label">
                <span class="label-text">{gettext("Service type")}</span>
              </label>
              <select name="service_type" class="select select-bordered w-full">
                <option value="ai" selected={@svc.service_type == "ai"}>{gettext("AI")}</option>
                <option value="natural" selected={@svc.service_type == "natural"}>
                  {gettext("Natural")}
                </option>
              </select>
            </div>

            <div>
              <label class="label">
                <span class="label-text">{gettext("Served at")}</span>
              </label>
              <input
                type="date"
                name="served_at"
                value={@svc.served_at}
                class="input input-bordered w-full"
              />
            </div>

            <div :if={@svc.service_type == "natural"} class="col-span-2">
              <.autocomplete
                id="serviceable-boar-picker"
                label={gettext("Boar")}
                name="boar_id"
                value={@svc.boar_id}
                items={@ac.boar_items}
                selected_label={@ac.boar_label}
                class="w-full input font-mono"
              />
            </div>

            <div>
              <label class="label">
                <span class="label-text">{gettext("Semen (optional)")}</span>
              </label>
              <input
                type="text"
                name="semen"
                value={@svc.semen}
                class="input input-bordered w-full font-mono"
              />
            </div>
            <div>
              <.autocomplete
                id="serviceable-pen-picker"
                label={gettext("Service pen (optional)")}
                name="pen_id"
                value={@svc.pen_id}
                items={@ac.pen_items}
                selected_label={@ac.pen_label}
                class="w-full input font-mono"
                placeholder={gettext("Search pens...")}
              />
              <p class="text-xs text-base-content/60">
                {gettext("If different from current pen.")}
              </p>
            </div>

            <div class="col-span-2">
              <label class="label">
                <span class="label-text">{gettext("Notes")}</span>
              </label>
              <textarea name="notes" rows="2" class="textarea textarea-bordered w-full">{@svc.notes}</textarea>
            </div>

            <p :if={@svc.error_message} class="col-span-2 text-sm text-error">
              {@svc.error_message}
            </p>

            <div class="col-span-2 flex gap-2 justify-end pt-2">
              <button type="button" phx-click="cancel_service" class="btn btn-ghost">
                {gettext("Cancel")}
              </button>
              <.button
                class="btn btn-primary"
                phx-disable-with={gettext("Saving...")}
                disabled={not service_save_enabled?(@svc)}
              >
                {gettext("Save service")}
              </.button>
            </div>
          </form>
        </Shared.modal>
      </div>
    </Layouts.app>
    """
  end

  # ── Mount ──────────────────────────────────────────────────────────

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     socket
     |> assign(
       can_record: Policy.can?(scope, :record_breeding),
       per_page: @per_page,
       today: FarmClock.today(scope),
       sort: "idle",
       dir: "desc",
       svc: nil,
       ac: Shared.default_ac(scope)
     )
     |> stream_configure(:serviceable, dom_id: &"serviceable-#{&1.animal.id}")
     |> stream(:serviceable, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = %{
      q: params["q"] || "",
      status: status_param(params["status"]),
      pen_search: params["pen_search"] || "",
      min_parity: params["min_parity"] || "",
      max_parity: params["max_parity"] || ""
    }

    {:noreply,
     socket
     |> assign(
       filters: filters,
       page: 1,
       sort: serviceable_sort_param(params["sort"]),
       dir: dir_param(params["dir"])
     )
     |> load_rows()}
  end

  @sort_columns ~w(tag pen parity idle status)
  defp serviceable_sort_param(s) when s in @sort_columns, do: s
  defp serviceable_sort_param(_), do: "idle"

  defp dir_param("asc"), do: "asc"
  defp dir_param(_), do: "desc"

  defp status_param(s) when s in ~w(open dry active served_outside_window), do: s
  defp status_param(_), do: "all"

  # ── Events ─────────────────────────────────────────────────────────

  @impl true
  def handle_event("filter_serviceable", params, socket) do
    query = %{
      "q" => params["q"] || "",
      "status" => params["status"] || "all",
      "pen_search" => params["pen_search"] || "",
      "min_parity" => params["min_parity"] || "",
      "max_parity" => params["max_parity"] || ""
    }

    {:noreply, push_patch(socket, to: tab_path(socket, query))}
  end

  def handle_event("load_more", _, socket), do: {:noreply, append_rows(socket)}

  def handle_event("open_service", %{"sow-id" => id}, socket) do
    if socket.assigns.can_record do
      scope = socket.assigns.current_scope
      sow = Animals.get_animal!(scope, String.to_integer(id))
      today = FarmClock.today(scope)

      # If the sow is already served (mid-heat), inherit service_type
      # and boar from her open service so the operator only has to
      # confirm today's date. The resolver will collapse this into a
      # mounting on the existing service.
      prior = Breeding.latest_open_service_for_sow(scope, sow.id)

      ac =
        Shared.default_ac(scope)
        |> Shared.maybe_preselect_pen(scope, sow)
        |> Shared.maybe_preselect_boar(scope, prior && prior.boar)

      svc = %{
        sow_id: sow.id,
        sow_tag: sow.ear_tag,
        sow_status: sow.status,
        service_type: (prior && prior.service_type) || "ai",
        served_at: to_string(today),
        boar_id: prior && prior.boar_id,
        pen_id: sow.current_pen_id,
        notes: nil,
        semen: prior && prior.semen,
        error_message: nil
      }

      {:noreply, assign(socket, svc: svc, ac: ac)}
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("validate_service", params, socket) do
    {:noreply, update_svc_from_params(socket, params)}
  end

  def handle_event("cancel_service", _, socket), do: {:noreply, close_form(socket)}

  def handle_event("save_service", params, socket) do
    if socket.assigns.can_record do
      socket = update_svc_from_params(socket, params)
      do_save_service(socket)
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("sort", %{"col" => col}, socket) do
    new_sort = serviceable_sort_param(col)

    new_dir =
      cond do
        new_sort == socket.assigns.sort and socket.assigns.dir == "asc" -> "desc"
        new_sort == socket.assigns.sort and socket.assigns.dir == "desc" -> "asc"
        true -> "asc"
      end

    {:noreply,
     push_patch(socket,
       to: tab_path(socket, %{"sort" => new_sort, "dir" => new_dir})
     )}
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp tab_path(socket, overrides) do
    slug = socket.assigns.current_scope.farm.slug
    f = socket.assigns.filters

    base = %{
      "q" => f.q,
      "status" => f.status,
      "pen_search" => f.pen_search,
      "min_parity" => f.min_parity,
      "max_parity" => f.max_parity,
      "sort" => socket.assigns.sort,
      "dir" => socket.assigns.dir
    }

    merged = base |> Map.merge(overrides) |> prune_query()
    path = ~p"/farms/#{slug}/breeding/serviceable"

    case merged do
      m when map_size(m) == 0 -> path
      m -> path <> "?" <> URI.encode_query(m)
    end
  end

  defp prune_query(q) do
    q
    |> Enum.reject(fn
      {_k, nil} -> true
      {_k, ""} -> true
      {"status", "all"} -> true
      {"sort", "idle"} -> true
      {"dir", "desc"} -> true
      _ -> false
    end)
    |> Map.new()
  end

  defp load_rows(socket) do
    scope = socket.assigns.current_scope
    f = socket.assigns.filters

    opts = list_opts(f, socket.assigns.sort, socket.assigns.dir, 0)
    rows = Breeding.list_serviceable(scope, opts)
    total = Breeding.count_serviceable(scope, opts)

    socket
    |> assign(total: total, page: 1, has_more: length(rows) < total)
    |> stream(:serviceable, rows, reset: true)
  end

  defp append_rows(socket) do
    scope = socket.assigns.current_scope
    f = socket.assigns.filters
    next_page = socket.assigns.page + 1
    offset = (next_page - 1) * @per_page

    opts = list_opts(f, socket.assigns.sort, socket.assigns.dir, offset)
    rows = Breeding.list_serviceable(scope, opts)
    loaded = next_page * @per_page

    socket =
      Enum.reduce(rows, socket, fn row, acc -> stream_insert(acc, :serviceable, row) end)

    assign(socket, page: next_page, has_more: loaded < socket.assigns.total)
  end

  defp list_opts(f, sort, dir, offset) do
    [
      search: f.q,
      status: f.status,
      pen_search: blank_to_nil(f.pen_search),
      min_parity: blank_to_nil(f.min_parity),
      max_parity: blank_to_nil(f.max_parity),
      sort: sort,
      dir: dir,
      limit: @per_page,
      offset: offset
    ]
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  defp sow_pen_label(%{current_pen: %{code: code, house: %{code: hcode}}}),
    do: "#{hcode}-#{code}"

  defp sow_pen_label(%{current_pen: %{code: code}}), do: code
  defp sow_pen_label(_), do: "—"

  defp idle_text(nil), do: "—"
  defp idle_text(d), do: Integer.to_string(d)

  defp idle_color(nil), do: "text-base-content/40"
  defp idle_color(d) when d >= 21, do: "text-error font-bold"
  defp idle_color(d) when d >= 10, do: "text-warning font-bold"
  defp idle_color(_), do: ""

  defp status_color("open"), do: "text-success"
  defp status_color("dry"), do: "text-info"
  defp status_color("active"), do: "text-base-content"
  defp status_color("served"), do: "text-warning"
  defp status_color(_), do: "text-base-content/60"

  # ── Service form helpers ───────────────────────────────────────────

  defp update_svc_from_params(socket, params) do
    svc = socket.assigns.svc
    if is_nil(svc), do: socket, else: do_update_svc(socket, svc, params)
  end

  defp do_update_svc(socket, svc, params) do
    service_type = Map.get(params, "service_type", svc.service_type)
    boar_id = parse_int(Map.get(params, "boar_id"))
    pen_id = parse_int(Map.get(params, "pen_id"))

    svc = %{
      svc
      | service_type: service_type,
        served_at: Map.get(params, "served_at", svc.served_at),
        boar_id: if(service_type == "natural", do: boar_id, else: nil),
        pen_id: pen_id,
        notes: Shared.presence(Map.get(params, "notes")),
        semen: Shared.presence(Map.get(params, "semen")),
        error_message: nil
    }

    assign(socket, svc: svc)
  end

  defp do_save_service(socket) do
    svc = socket.assigns.svc

    attrs =
      %{
        "sow_id" => svc.sow_id,
        "service_type" => svc.service_type,
        "served_at" => svc.served_at,
        "notes" => svc.notes
      }
      |> maybe_put("boar_id", svc.boar_id)
      |> maybe_put("pen_id", svc.pen_id)
      |> maybe_put("semen", svc.semen)

    case Breeding.record_service_with_backfill(socket.assigns.current_scope, attrs) do
      {:ok, %{sow: sow}} ->
        {:noreply,
         socket
         |> close_form()
         |> load_rows()
         |> put_flash(:info, gettext("Service recorded for %{tag}.", tag: sow.ear_tag))
         |> push_event("flash-row", %{id: "serviceable-#{sow.id}"})}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, svc: %{svc | error_message: Shared.format_cs_error(cs)})}

      {:error, reason} ->
        {:noreply, assign(socket, svc: %{svc | error_message: humanize(reason)})}
    end
  end

  defp close_form(socket) do
    assign(socket,
      svc: nil,
      ac: Shared.default_ac(socket.assigns.current_scope)
    )
  end

  defp service_save_enabled?(%{service_type: "natural", boar_id: nil}), do: false
  defp service_save_enabled?(%{served_at: served}) when served in [nil, ""], do: false
  defp service_save_enabled?(_), do: true

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(n) when is_integer(n), do: n

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {i, ""} -> i
      _ -> nil
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp humanize(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> String.replace("_", " ")

  defp humanize(reason), do: inspect(reason)
end
