defmodule PeggyWeb.MobileLive.Breeding.Serviceable do
  @moduledoc """
  Mobile-first Serviceable tab.

  Card-per-sow list of females ready for a new service (status active /
  open / dry). Tap a card to navigate into the Gestating service form
  with the sow's tag pre-filled — keeps record-service paths centralized.
  """
  use PeggyWeb, :live_view

  alias Peggy.{Animals, Breeding, FarmClock, Locations, Policy}
  alias PeggyWeb.FarmLive.Breeding.Shared
  alias PeggyWeb.MobileLive.Breeding.MovementForm

  @per_page 25

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_app flash={@flash} current_scope={@current_scope} active={:breeding}>
      <div>
        <%!-- Sticky top bar --%>
        <header class="sticky top-0 z-10 bg-base-100 border-b border-base-200 px-3 py-2">
          <form phx-change="search" phx-submit="search" class="flex gap-2 items-center">
            <input
              type="search"
              name="q"
              value={@filters.q}
              placeholder={gettext("Sow tag…")}
              inputmode="numeric"
              phx-debounce="300"
              autocomplete="off"
              class="input input-bordered input-lg flex-1 font-mono text-base"
            />
            <button
              type="button"
              phx-click="open_filters"
              class="btn btn-ghost btn-square btn-lg relative"
              aria-label={gettext("Filters")}
            >
              <.icon name="hero-funnel" class="size-6" />
              <span
                :if={active_filter_count(assigns) > 0}
                class="absolute -top-1 -right-1 badge badge-sm badge-primary"
              >
                {active_filter_count(assigns)}
              </span>
            </button>
          </form>
        </header>

        <%!-- Tab strip --%>
        <nav class="px-3 pt-2 flex gap-2 text-xs">
          <.link
            navigate={~p"/m/#{@current_scope.farm.slug}/breeding/serviceable"}
            class="px-3 py-1 rounded-full bg-primary text-primary-content font-semibold"
          >
            {gettext("Serviceable")}
          </.link>
          <.link
            navigate={~p"/m/#{@current_scope.farm.slug}/breeding/gestating"}
            class="px-3 py-1 rounded-full border border-base-300 text-base-content/70"
          >
            {gettext("Gestating")}
          </.link>
          <.link
            navigate={~p"/m/#{@current_scope.farm.slug}/breeding/lactating"}
            class="px-3 py-1 rounded-full border border-base-300 text-base-content/70"
          >
            {gettext("Lactating")}
          </.link>
        </nav>

        <%!-- Cards --%>
        <ul id="serviceable-cards" phx-update="stream" class="px-3 py-2 space-y-2">
          <li
            :for={{dom_id, e} <- @streams.serviceable}
            id={dom_id}
            phx-click={@can_record && "open_actions"}
            phx-value-sow-id={e.animal.id}
            class={[
              "p-4 rounded-xl border border-base-300 bg-base-100 shadow-sm",
              @can_record && "active:bg-base-200 cursor-pointer touch-manipulation"
            ]}
          >
            <div class="flex items-baseline justify-between">
              <span class="font-mono font-bold text-xl">
                {e.animal.ear_tag}
              </span>
              <span>
                <.icon name="hero-map-pin-micro" class="size-4 text-blue-600" />
                <span class="font-mono">{sow_pen_label(e.animal)}</span>
              </span>
              <span class={[
                "uppercase font-semibold",
                status_color(e.animal.status)
              ]}>
                {e.animal.status}
                <span
                  :if={e.animal.status == "served"}
                  class="ml-1 badge badge-sm badge-warning"
                >
                  {gettext("in heat")}
                </span>
              </span>
            </div>

            <div class="flex items-center gap-2 text-sm text-base-content/70 justify-between">
              <span class="text-base-content/50">
                {gettext("Parity")}
                <span class="font-mono font-bold text-info ml-1">{e.parity}</span>
              </span>
              <div class="text-base-content/60">
                <Shared.last_event entry={e} empty_text={gettext("No history")} />
              </div>
              <div class={[
                "text-xl font-mono font-bold leading-none",
                idle_color(e.days_idle)
              ]}>
                {idle_display(e.days_idle)}
              </div>
            </div>
            <Shared.recently_updated_badge at={e.animal.updated_at} />
          </li>
        </ul>

        <p :if={@total == 0} class="px-4 py-8 text-center text-sm text-base-content/60">
          {gettext("No serviceable females match the filters.")}
        </p>

        <.infinite_scroll
          has_more={@has_more}
          total={@total}
          id="serviceable-mobile-sentinel"
        />

        <%!-- Filter drawer --%>
        <div
          :if={@filter_drawer_open}
          class="fixed inset-0 z-40 bg-black/40 flex justify-end"
          phx-click="close_filters"
        >
          <aside
            class="w-80 max-w-[85vw] h-full bg-base-100 shadow-xl overflow-y-auto
                   pb-[env(safe-area-inset-bottom)] flex flex-col"
            phx-click="ignore_click"
          >
            <header class="px-4 py-3 border-b border-base-200 flex items-center justify-between">
              <h2 class="font-semibold">{gettext("Filters")}</h2>
              <button
                phx-click="close_filters"
                class="btn btn-ghost btn-square btn-sm"
                aria-label={gettext("Close")}
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </header>
            <form phx-change="filter" phx-submit="filter" class="p-4 space-y-4 flex-1">
              <label class="block">
                <span class="text-xs uppercase text-base-content/60">{gettext("Status")}</span>
                <select name="status" class="select select-bordered select-lg w-full mt-1">
                  <option value="all" selected={@filters.status == "all"}>{gettext("All")}</option>
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

              <label class="block">
                <span class="text-xs uppercase text-base-content/60">{gettext("Pen")}</span>
                <input
                  type="text"
                  name="pen_search"
                  value={@filters.pen_search}
                  placeholder="H-P"
                  phx-debounce="300"
                  class="input input-bordered input-lg w-full font-mono mt-1"
                />
              </label>

              <div class="grid grid-cols-2 gap-3">
                <label class="block">
                  <span class="text-xs uppercase text-base-content/60">{gettext("Min parity")}</span>
                  <input
                    type="number"
                    name="min_parity"
                    value={@filters.min_parity}
                    min="0"
                    inputmode="numeric"
                    class="input input-bordered input-lg w-full mt-1"
                  />
                </label>
                <label class="block">
                  <span class="text-xs uppercase text-base-content/60">{gettext("Max parity")}</span>
                  <input
                    type="number"
                    name="max_parity"
                    value={@filters.max_parity}
                    min="0"
                    inputmode="numeric"
                    class="input input-bordered input-lg w-full mt-1"
                  />
                </label>
              </div>
              <label class="block text-success">
                <span class="text-xs uppercase text-base-content/60">{gettext("Sort by")}</span>
                <select name="sort" class="select select-bordered select-lg w-full mt-1">
                  <option
                    :for={{value, label} <- sort_options()}
                    value={value}
                    selected={"#{@sort}-#{@dir}" == value}
                  >
                    {label}
                  </option>
                </select>
              </label>
            </form>
            <footer
              :if={active_filter_count(assigns) > 0}
              class="px-4 py-3 border-t border-base-200"
            >
              <button phx-click="reset_filters" class="btn btn-ghost w-full">
                {gettext("Reset filters")}
              </button>
            </footer>
          </aside>
        </div>

        <%!-- Action sheet --%>
        <div
          :if={@action_sheet_for}
          class="fixed inset-0 z-40 bg-black/40 flex items-end"
          phx-click="close_actions"
        >
          <div
            class="w-full bg-base-100 rounded-t-2xl pb-[env(safe-area-inset-bottom)]
                   max-h-[90vh] overflow-y-auto"
            phx-click="ignore_click"
          >
            <div class="flex justify-center pt-2 pb-1">
              <div class="w-10 h-1 rounded-full bg-base-300"></div>
            </div>

            <div class="px-4 py-2 border-b border-base-200 flex items-center gap-3">
              <button
                :if={@sheet_mode != :menu}
                phx-click="action_back"
                class="btn btn-ghost btn-square btn-sm"
                aria-label={gettext("Back")}
              >
                <.icon name="hero-chevron-left" class="size-5" />
              </button>
              <div class={["flex-1", @sheet_mode == :menu && "text-center"]}>
                <.link
                  :if={@sheet_animal}
                  navigate={~p"/m/#{@current_scope.farm.slug}/animals/#{@sheet_animal.id}"}
                  class="font-mono font-bold text-lg text-primary underline underline-offset-2 decoration-dotted active:decoration-solid"
                >
                  {@sheet_sow_tag}
                </.link>
                <div
                  :if={is_nil(@sheet_animal)}
                  class="font-mono font-bold text-lg"
                >
                  {@sheet_sow_tag}
                </div>
                <div :if={@sheet_animal} class="text-xs text-base-content/60">
                  <span class={["uppercase font-semibold", status_color(@sheet_animal.status)]}>
                    {@sheet_animal.status}
                  </span>
                  <span class="ml-2 font-mono">{sow_pen_label(@sheet_animal)}</span>
                </div>
              </div>
            </div>

            <%!-- Action menu --%>
            <div
              :if={@sheet_mode == :menu and @can_record}
              class="grid grid-cols-2 gap-px bg-base-200"
            >
              <button
                phx-click="action_service"
                class="bg-base-100 py-5 flex flex-col items-center gap-1 active:bg-pink-500/10"
              >
                <.icon name="hero-heart" class="size-7 text-pink-500" />
                <span class="text-xs">
                  {if @sheet_animal && @sheet_animal.status == "served",
                    do: gettext("+ Mount"),
                    else: gettext("Service")}
                </span>
              </button>
              <button
                phx-click="action_move"
                class="bg-base-100 py-5 flex flex-col items-center gap-1 active:bg-info/10"
              >
                <.icon name="hero-truck" class="size-7 text-info" />
                <span class="text-xs">{gettext("Move")}</span>
              </button>
            </div>

            <%!-- Service form --%>
            <form
              :if={@sheet_mode == :service and @svc}
              phx-change="validate_service"
              phx-submit="save_service"
              class="px-4 py-3 space-y-3"
            >
              <label class="block">
                <span class="text-xs uppercase text-base-content/60">{gettext("Service type")}</span>
                <select name="service_type" class="select select-bordered select-lg w-full mt-1">
                  <option value="ai" selected={@svc.service_type == "ai"}>{gettext("AI")}</option>
                  <option value="natural" selected={@svc.service_type == "natural"}>
                    {gettext("Natural")}
                  </option>
                </select>
              </label>

              <label :if={@svc.service_type == "natural"} class="block">
                <span class="text-xs uppercase text-base-content/60">{gettext("Boar ear tag")}</span>
                <input
                  type="text"
                  name="boar_tag"
                  value={@svc.boar_tag}
                  phx-debounce="300"
                  autocomplete="off"
                  class={[
                    "input input-bordered input-lg w-full mt-1 font-mono",
                    @svc.boar_state == :resolved && "border-success focus:border-success",
                    @svc.boar_state == :not_found && "border-error focus:border-error"
                  ]}
                />
                <span class={[
                  "text-xs mt-1 block",
                  @svc.boar_state == :resolved && "text-success",
                  @svc.boar_state == :not_found && "text-error",
                  @svc.boar_state == :empty && "text-base-content/50"
                ]}>
                  {boar_state_text(@svc.boar_state)}
                </span>
              </label>

              <label class="block">
                <span class="text-xs uppercase text-base-content/60">{gettext("Served at")}</span>
                <input
                  type="date"
                  name="served_at"
                  value={@svc.served_at}
                  class="input input-bordered input-lg w-full mt-1"
                />
              </label>

              <label class="block">
                <span class="text-xs uppercase text-base-content/60">
                  {gettext("Semen (optional)")}
                </span>
                <input
                  type="text"
                  name="semen"
                  value={@svc.semen}
                  phx-debounce="300"
                  autocomplete="off"
                  placeholder={gettext("Semen code")}
                  class="input input-bordered input-lg w-full mt-1 font-mono"
                />
              </label>

              <label class="block">
                <span class="text-xs uppercase text-base-content/60">
                  {gettext("Pen (HOUSE-PEN, optional)")}
                </span>
                <input
                  type="text"
                  name="pen_code"
                  value={@svc.pen_code}
                  phx-debounce="300"
                  autocomplete="off"
                  placeholder="EB-12"
                  class={[
                    "input input-bordered input-lg w-full mt-1 font-mono",
                    @svc.pen_state == :resolved && "border-success focus:border-success",
                    @svc.pen_state == :not_found && "border-error focus:border-error"
                  ]}
                />
                <span class={[
                  "text-xs mt-1 block",
                  @svc.pen_state == :resolved && "text-success",
                  @svc.pen_state == :not_found && "text-error",
                  @svc.pen_state == :empty && "text-base-content/50"
                ]}>
                  {pen_state_text(@svc.pen_state)}
                </span>
              </label>

              <p :if={@svc.error_message} class="text-sm text-error">{@svc.error_message}</p>

              <div class="grid grid-cols-2 gap-3 pt-2">
                <button type="button" phx-click="action_back" class="btn btn-lg btn-ghost">
                  {gettext("Cancel")}
                </button>
                <button
                  type="submit"
                  phx-disable-with={gettext("Saving…")}
                  disabled={not service_save_enabled?(@svc)}
                  class="btn btn-lg btn-primary"
                >
                  {gettext("Served")}
                </button>
              </div>
            </form>

            <%!-- Move form --%>
            <MovementForm.move_form
              :if={@sheet_mode == :move and @move_form}
              form={@move_form}
              animal={@move_animal}
              from_code={@move_from_code}
              from_state={@move_from_state}
              to_code={@move_to_code}
              to_state={@move_to_state}
              error={@move_error}
            />

            <p
              :if={@sheet_mode == :menu and not @can_record}
              class="px-4 py-6 text-center text-sm text-base-content/60"
            >
              {gettext("View-only — you don't have permission to record breeding.")}
            </p>

            <button
              :if={@sheet_mode == :menu}
              phx-click="close_actions"
              class="w-full py-3 text-sm text-base-content/60 border-t border-base-200"
            >
              {gettext("Close")}
            </button>
          </div>
        </div>
      </div>
    </Layouts.mobile_app>
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
       today: FarmClock.today(scope),
       per_page: @per_page,
       filter_drawer_open: false,
       action_sheet_for: nil,
       sheet_mode: :menu,
       sheet_animal: nil,
       sheet_sow_tag: nil,
       svc: nil,
       sort: "idle",
       dir: "desc"
     )
     |> assign(MovementForm.init())
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

    {sort, dir} = parse_sort_param(params["sort"])

    {:noreply,
     socket
     |> assign(filters: filters, page: 1, sort: sort, dir: dir)
     |> load_rows()}
  end

  defp status_param(s) when s in ~w(open dry active served_outside_window), do: s
  defp status_param(_), do: "all"

  # Combined `sort=<field>-<dir>` URL param (e.g. "tag-desc"). Single
  # form binding, falls back to (idle, desc) on anything unrecognised.
  @sort_options ~w(idle-asc idle-desc tag-asc tag-desc parity-asc parity-desc pen-asc status-asc)

  defp parse_sort_param(s) when is_binary(s) do
    if s in @sort_options do
      [field, dir] = String.split(s, "-", parts: 2)
      {field, dir}
    else
      {"idle", "desc"}
    end
  end

  defp parse_sort_param(_), do: {"idle", "desc"}

  defp sort_to_param("idle", "desc"), do: nil
  defp sort_to_param(field, dir), do: "#{field}-#{dir}"

  # Combined-direction options for the mobile filter-drawer dropdown.
  # Order matches the desktop sortable columns plus a sensible default.
  defp sort_options do
    [
      {"idle-asc", gettext("Most recent activity")},
      {"idle-desc", gettext("Oldest activity")},
      {"tag-asc", gettext("Tag A→Z")},
      {"tag-desc", gettext("Tag Z→A")},
      {"parity-asc", gettext("Parity (low to high)")},
      {"parity-desc", gettext("Parity (high to low)")},
      {"pen-asc", gettext("Pen")},
      {"status-asc", gettext("Status")}
    ]
  end

  # ── Events ─────────────────────────────────────────────────────────

  @impl true
  def handle_event("search", %{"q" => q}, socket),
    do: {:noreply, push_patch_filters(socket, %{"q" => q})}

  def handle_event("filter", params, socket) do
    {:noreply,
     push_patch_filters(socket, %{
       "status" => params["status"] || "all",
       "pen_search" => params["pen_search"] || "",
       "min_parity" => params["min_parity"] || "",
       "max_parity" => params["max_parity"] || "",
       "sort" => params["sort"] || ""
     })}
  end

  def handle_event("reset_filters", _, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/m/#{socket.assigns.current_scope.farm.slug}/breeding/serviceable"
     )}
  end

  def handle_event("open_filters", _, socket),
    do: {:noreply, assign(socket, :filter_drawer_open, true)}

  def handle_event("close_filters", _, socket),
    do: {:noreply, assign(socket, :filter_drawer_open, false)}

  def handle_event("ignore_click", _, socket), do: {:noreply, socket}

  def handle_event("load_more", _, socket), do: {:noreply, append_rows(socket)}

  def handle_event("open_actions", %{"sow-id" => id}, socket) do
    if socket.assigns.can_record do
      scope = socket.assigns.current_scope
      sow = Animals.get_animal!(scope, String.to_integer(id))

      {:noreply,
       socket
       |> reset_sheet_state()
       |> assign(
         action_sheet_for: sow.id,
         sheet_mode: :menu,
         sheet_animal: sow,
         sheet_sow_tag: sow.ear_tag
       )}
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("close_actions", _, socket), do: {:noreply, reset_sheet(socket)}

  def handle_event("action_back", _, socket) do
    {:noreply,
     socket
     |> reset_sheet_state()
     |> assign(sheet_mode: :menu)}
  end

  # Service

  def handle_event("action_service", _, socket) do
    if socket.assigns.can_record do
      scope = socket.assigns.current_scope
      sow = socket.assigns.sheet_animal
      today = FarmClock.today(scope)

      # Pre-fill from the existing open service when the sow is mid-
      # heat (already served). The resolver will collapse this entry
      # into a mounting on the existing service.
      prior = Breeding.latest_open_service_for_sow(scope, sow.id)

      {boar_tag, boar_state, boar_id} =
        case prior && prior.boar do
          %{id: id, ear_tag: tag} -> {tag, :resolved, id}
          _ -> {"", :empty, nil}
        end

      svc = %{
        sow_id: sow.id,
        sow_tag: sow.ear_tag,
        sow_status: sow.status,
        service_type: (prior && prior.service_type) || "ai",
        served_at: to_string(today),
        boar_tag: boar_tag,
        boar_state: boar_state,
        boar_id: boar_id,
        pen_code: pen_code_for(sow),
        pen_state: pen_state_for(sow),
        pen_id: sow.current_pen_id,
        semen: prior && prior.semen,
        error_message: nil
      }

      {:noreply, assign(socket, sheet_mode: :service, svc: svc)}
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("validate_service", params, socket) do
    {:noreply,
     socket
     |> update_svc_basics(params)
     |> resolve_boar(params["boar_tag"])
     |> resolve_pen(params["pen_code"])}
  end

  def handle_event("save_service", params, socket) do
    if socket.assigns.can_record do
      socket =
        socket
        |> update_svc_basics(params)
        |> resolve_boar(params["boar_tag"])
        |> resolve_pen(params["pen_code"])

      do_save_service(socket)
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  # Movement

  def handle_event("action_move", _, socket) do
    if Policy.can?(socket.assigns.current_scope, :record_movement) do
      {:noreply,
       socket
       |> assign(sheet_mode: :move)
       |> MovementForm.open(socket.assigns.sheet_animal)}
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("move_validate", params, socket) do
    {:noreply, MovementForm.validate(socket, params)}
  end

  def handle_event("move_save", params, socket) do
    if Policy.can?(socket.assigns.current_scope, :record_movement) do
      sow_id = socket.assigns.move_animal && socket.assigns.move_animal.id

      case MovementForm.save(socket, params) do
        {:ok, socket} ->
          {:noreply,
           socket
           |> reset_sheet()
           |> load_rows()
           |> put_flash(:info, gettext("Movement recorded."))
           |> push_event("flash-row", %{id: "serviceable-#{sow_id}"})}

        {:error, socket} ->
          {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp push_patch_filters(socket, overrides) do
    f = socket.assigns.filters

    base = %{
      "q" => f.q,
      "status" => f.status,
      "pen_search" => f.pen_search,
      "min_parity" => f.min_parity,
      "max_parity" => f.max_parity,
      "sort" => sort_to_param(socket.assigns.sort, socket.assigns.dir) || ""
    }

    merged = base |> Map.merge(overrides) |> prune_filter_query()
    slug = socket.assigns.current_scope.farm.slug

    path =
      case merged do
        m when map_size(m) == 0 -> ~p"/m/#{slug}/breeding/serviceable"
        m -> ~p"/m/#{slug}/breeding/serviceable?#{m}"
      end

    push_patch(socket, to: path)
  end

  defp prune_filter_query(q) do
    q
    |> Enum.reject(fn
      {_k, ""} -> true
      {_k, nil} -> true
      {"status", "all"} -> true
      {"sort", "idle-desc"} -> true
      _ -> false
    end)
    |> Map.new()
  end

  defp active_filter_count(assigns) do
    f = assigns.filters

    [
      f.status != "all",
      f.pen_search != "",
      f.min_parity != "",
      f.max_parity != "",
      not (assigns.sort == "idle" and assigns.dir == "desc")
    ]
    |> Enum.count(& &1)
  end

  defp load_rows(socket) do
    scope = socket.assigns.current_scope

    opts = list_opts(socket, 0)
    rows = Breeding.list_serviceable(scope, opts)
    total = Breeding.count_serviceable(scope, opts)

    socket
    |> assign(total: total, page: 1, has_more: length(rows) < total)
    |> stream(:serviceable, rows, reset: true)
  end

  defp append_rows(socket) do
    scope = socket.assigns.current_scope
    next_page = socket.assigns.page + 1
    offset = (next_page - 1) * @per_page

    opts = list_opts(socket, offset)
    rows = Breeding.list_serviceable(scope, opts)
    loaded = next_page * @per_page

    socket =
      Enum.reduce(rows, socket, fn row, acc -> stream_insert(acc, :serviceable, row) end)

    assign(socket, page: next_page, has_more: loaded < socket.assigns.total)
  end

  defp list_opts(socket, offset) do
    f = socket.assigns.filters

    [
      search: f.q,
      status: f.status,
      pen_search: blank_to_nil(f.pen_search),
      min_parity: blank_to_nil(f.min_parity),
      max_parity: blank_to_nil(f.max_parity),
      sort: socket.assigns.sort,
      dir: socket.assigns.dir,
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

  defp idle_display(nil), do: "—"
  defp idle_display(d), do: "#{d}d"

  defp idle_color(nil), do: "text-base-content/40"
  defp idle_color(d) when d >= 21, do: "text-error"
  defp idle_color(d) when d >= 10, do: "text-warning"
  defp idle_color(_), do: "text-success"

  defp status_color("open"), do: "text-success"
  defp status_color("dry"), do: "text-info"
  defp status_color("active"), do: "text-base-content"
  defp status_color("served"), do: "text-warning"
  defp status_color(_), do: "text-base-content/60"

  # ── Service form helpers ───────────────────────────────────────────

  defp update_svc_basics(socket, params) do
    svc = socket.assigns.svc
    if is_nil(svc), do: socket, else: do_update_svc_basics(socket, svc, params)
  end

  defp do_update_svc_basics(socket, svc, params) do
    service_type = Map.get(params, "service_type", svc.service_type)

    svc = %{
      svc
      | service_type: service_type,
        served_at: Map.get(params, "served_at", svc.served_at),
        semen: Shared.presence(Map.get(params, "semen", svc.semen)),
        error_message: nil
    }

    assign(socket, svc: svc)
  end

  defp resolve_boar(socket, nil), do: resolve_boar(socket, "")

  defp resolve_boar(socket, tag) when is_binary(tag) do
    svc = socket.assigns.svc
    if is_nil(svc), do: socket, else: do_resolve_boar(socket, svc, String.trim(tag))
  end

  defp do_resolve_boar(socket, %{service_type: "ai"} = svc, _tag) do
    assign(socket, svc: %{svc | boar_tag: "", boar_state: :empty, boar_id: nil})
  end

  defp do_resolve_boar(socket, svc, "") do
    assign(socket, svc: %{svc | boar_tag: "", boar_state: :empty, boar_id: nil})
  end

  defp do_resolve_boar(socket, svc, tag) do
    case Animals.find_by_ear_tag(socket.assigns.current_scope, tag) do
      %{stage: "boar", id: id} ->
        assign(socket, svc: %{svc | boar_tag: tag, boar_state: :resolved, boar_id: id})

      _ ->
        assign(socket, svc: %{svc | boar_tag: tag, boar_state: :not_found, boar_id: nil})
    end
  end

  defp resolve_pen(socket, nil), do: resolve_pen(socket, "")

  defp resolve_pen(socket, code) when is_binary(code) do
    svc = socket.assigns.svc
    if is_nil(svc), do: socket, else: do_resolve_pen(socket, svc, String.trim(code))
  end

  defp do_resolve_pen(socket, svc, "") do
    assign(socket, svc: %{svc | pen_code: "", pen_state: :empty, pen_id: nil})
  end

  defp do_resolve_pen(socket, svc, code) do
    case Locations.find_pen_by_code(socket.assigns.current_scope, code) do
      nil ->
        assign(socket, svc: %{svc | pen_code: code, pen_state: :not_found, pen_id: nil})

      pen ->
        assign(socket, svc: %{svc | pen_code: code, pen_state: :resolved, pen_id: pen.id})
    end
  end

  defp do_save_service(socket) do
    svc = socket.assigns.svc

    cond do
      svc.service_type == "natural" and is_nil(svc.boar_id) ->
        {:noreply,
         assign(socket,
           svc: %{svc | error_message: gettext("Boar tag is required for natural service.")}
         )}

      svc.served_at in [nil, ""] ->
        {:noreply,
         assign(socket, svc: %{svc | error_message: gettext("Served-at date is required.")})}

      true ->
        attrs =
          %{
            "sow_id" => svc.sow_id,
            "service_type" => svc.service_type,
            "served_at" => svc.served_at
          }
          |> maybe_put("boar_id", svc.boar_id)
          |> maybe_put("pen_id", svc.pen_id)
          |> maybe_put("semen", svc.semen)

        case Breeding.record_service_with_backfill(socket.assigns.current_scope, attrs) do
          {:ok, %{sow: sow}} ->
            {:noreply,
             socket
             |> reset_sheet()
             |> load_rows()
             |> put_flash(:info, gettext("Service recorded for %{tag}.", tag: sow.ear_tag))
             |> push_event("flash-row", %{id: "serviceable-#{sow.id}"})}

          {:error, %Ecto.Changeset{} = cs} ->
            {:noreply, assign(socket, svc: %{svc | error_message: Shared.format_cs_error(cs)})}

          {:error, reason} ->
            {:noreply, assign(socket, svc: %{svc | error_message: humanize(reason)})}
        end
    end
  end

  defp reset_sheet(socket) do
    socket
    |> reset_sheet_state()
    |> assign(
      action_sheet_for: nil,
      sheet_mode: :menu,
      sheet_animal: nil,
      sheet_sow_tag: nil
    )
  end

  defp reset_sheet_state(socket) do
    socket
    |> assign(svc: nil)
    |> MovementForm.reset()
  end

  defp service_save_enabled?(%{service_type: "natural", boar_id: nil}), do: false
  defp service_save_enabled?(%{served_at: served}) when served in [nil, ""], do: false
  defp service_save_enabled?(_), do: true

  defp pen_code_for(%{current_pen: %{code: code, house: %{code: hcode}}}), do: "#{hcode}-#{code}"
  defp pen_code_for(_), do: ""

  defp pen_state_for(%{current_pen_id: nil}), do: :empty
  defp pen_state_for(%{current_pen: %{code: _}}), do: :resolved
  defp pen_state_for(_), do: :empty

  defp boar_state_text(:resolved), do: gettext("✓")
  defp boar_state_text(:not_found), do: gettext("⚠ No boar with that tag")
  defp boar_state_text(_), do: gettext("Type the boar's ear tag")

  defp pen_state_text(:resolved), do: gettext("✓")
  defp pen_state_text(:not_found), do: gettext("⚠ No active pen with that code")
  defp pen_state_text(_), do: gettext("Optional — moves the sow to this pen")

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp humanize(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> String.replace("_", " ")

  defp humanize(reason), do: inspect(reason)
end
