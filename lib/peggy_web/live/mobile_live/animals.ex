defmodule PeggyWeb.MobileLive.Animals do
  @moduledoc """
  Mobile animal browser. Card-per-animal list with a register sheet
  that toggles between Individual (sow / boar) and Batch (weaner /
  grower / finisher). Batches register into a single pen on mobile;
  multi-pen distribution still goes through the desktop UI.
  """
  use PeggyWeb, :live_view

  alias Peggy.{Animals, Breeding, FarmClock, Locations, Policy}
  alias Peggy.Animals.Animal

  @per_page 25
  @batch_stages ~w(weaner grower finisher)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_app flash={@flash} current_scope={@current_scope} active={:animals}>
      <div>
        <%!-- Sticky top bar --%>
        <header class="sticky top-0 z-10 bg-base-100 border-b border-base-200 px-3 py-2">
          <form phx-change="search" phx-submit="search" class="flex gap-2 items-center">
            <input
              type="search"
              name="q"
              value={@filters.tag_search}
              placeholder={gettext("Ear tag…")}
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
                :if={active_filter_count(@filters) > 0}
                class="absolute -top-1 -right-1 badge badge-sm badge-primary"
              >
                {active_filter_count(@filters)}
              </span>
            </button>
            <.link
              navigate={~p"/m/#{@current_scope.farm.slug}/animals/promote"}
              class="btn btn-ghost btn-square btn-lg"
              aria-label={gettext("Promote batches")}
            >
              <.icon name="hero-academic-cap" class="size-6 text-success" />
            </.link>
            <button
              :if={@can_manage}
              type="button"
              phx-click="register_open"
              class="btn btn-primary btn-square btn-lg"
              aria-label={gettext("Register animal")}
            >
              <.icon name="hero-plus" class="size-6" />
            </button>
          </form>
        </header>

        <%!-- Cards --%>
        <ul id="animals-cards" phx-update="stream" class="px-3 py-2 space-y-2">
          <li
            :for={{dom_id, a} <- @streams.animals}
            id={dom_id}
            phx-click={JS.navigate(~p"/m/#{@current_scope.farm.slug}/animals/#{a.id}")}
            class="p-4 rounded-xl border border-base-300 bg-base-100 shadow-sm
                   active:bg-base-200 cursor-pointer touch-manipulation"
          >
            <div class="flex items-baseline justify-between gap-2">
              <span class="font-mono font-bold text-2xl flex items-center gap-1">
                {a.ear_tag || "##{a.id}"}
                <span :if={a.needs_review} title={gettext("Needs review")}>
                  <.icon name="hero-exclamation-triangle-micro" class="size-5 text-warning" />
                </span>
                <.cull_flag animal={a} />
              </span>
              <.status_badge status={a.status} class="badge-sm" />
            </div>

            <div class="flex items-center gap-2 text-sm text-base-content/70">
              <span>
                {String.capitalize(a.stage)}<span
                  :if={detail = stage_suffix(a, @parity_map, @avg_wean_age, @today)}
                  class="text-base-content/60"
                >{detail}</span>
              </span>
              -
              <div
                :if={line = footer_line(@current_scope, a, @event_map, @today, @avg_wean_age)}
                class="text-xs"
              >
                <span class="text-base-content/50">{elem(line, 0)}</span>
                <span class="font-mono font-semibold">{elem(line, 1)}</span>
              </div>
              <span class="ml-auto inline-flex items-center gap-1">
                <.icon name="hero-map-pin-micro" class="size-4 text-blue-600" />
                <span class="font-mono">{pen_label(a)}</span>
              </span>
            </div>
          </li>
        </ul>

        <p :if={@total == 0} class="px-4 py-8 text-center text-sm text-base-content/60">
          {gettext("No animals match the filters.")}
        </p>

        <.infinite_scroll has_more={@has_more} total={@total} id="animals-mobile-sentinel" />

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
                <span class="text-xs uppercase text-base-content/60">{gettext("Stage")}</span>
                <select name="stage" class="select select-bordered select-lg w-full mt-1">
                  <option value="" selected={@filters.stage == ""}>{gettext("All")}</option>
                  <option
                    :for={s <- Animal.stages()}
                    value={s}
                    selected={@filters.stage == s}
                  >
                    {String.capitalize(s)}
                  </option>
                </select>
              </label>

              <label class="block">
                <span class="text-xs uppercase text-base-content/60">{gettext("Status")}</span>
                <select name="status" class="select select-bordered select-lg w-full mt-1">
                  <option
                    :for={{label, value} <- status_options(@filters.stage)}
                    value={value}
                    selected={@filters.status == value}
                  >
                    {label}
                  </option>
                </select>
              </label>

              <label class="block">
                <span class="text-xs uppercase text-base-content/60">{gettext("Tag / ID")}</span>
                <input
                  type="text"
                  name="tag_search"
                  value={@filters.tag_search}
                  placeholder={gettext("e.g. 12345 or #42")}
                  phx-debounce="300"
                  autocomplete="off"
                  class="input input-bordered input-lg w-full font-mono mt-1"
                />
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

              <div :if={@filters.stage in @batch_stages} class="grid grid-cols-2 gap-3">
                <label class="block">
                  <span class="text-xs uppercase text-base-content/60">{gettext("Min age (d)")}</span>
                  <input
                    type="number"
                    name="min_age"
                    value={@filters.min_age}
                    min="0"
                    inputmode="numeric"
                    class="input input-bordered input-lg w-full mt-1"
                  />
                </label>
                <label class="block">
                  <span class="text-xs uppercase text-base-content/60">{gettext("Max age (d)")}</span>
                  <input
                    type="number"
                    name="max_age"
                    value={@filters.max_age}
                    min="0"
                    inputmode="numeric"
                    class="input input-bordered input-lg w-full mt-1"
                  />
                </label>
              </div>

              <div :if={@filters.stage == "sow"} class="grid grid-cols-2 gap-3">
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

              <label class="flex items-center gap-3 mt-2">
                <input
                  type="checkbox"
                  name="needs_review"
                  value="1"
                  checked={@filters.needs_review}
                  class="checkbox checkbox-warning"
                />
                <span class="text-sm">{gettext("Needs review only")}</span>
              </label>
            </form>
            <footer
              :if={active_filter_count(@filters) > 0}
              class="px-4 py-3 border-t border-base-200"
            >
              <button phx-click="reset_filters" class="btn btn-ghost w-full">
                {gettext("Reset filters")}
              </button>
            </footer>
          </aside>
        </div>

        <%!-- Register sheet --%>
        <div
          :if={@register_form}
          class="fixed inset-0 z-40 bg-black/40 flex items-end"
          phx-click="register_close"
        >
          <.form
            :let={f}
            for={@register_form}
            phx-change="register_validate"
            phx-submit="register_save"
            phx-click="ignore_click"
            class="w-full bg-base-100 rounded-t-2xl pb-[env(safe-area-inset-bottom)]
                   max-h-[90vh] overflow-y-auto"
          >
            <div class="flex justify-center pt-2 pb-1">
              <div class="w-10 h-1 rounded-full bg-base-300"></div>
            </div>
            <div class="px-4 py-2 border-b border-base-200 text-center">
              <div class="font-semibold">{gettext("Register animal")}</div>
            </div>

            <div class="px-4 py-4 space-y-3">
              <input type="hidden" name="animal[status]" value="active" />

              <%!-- Individual / Batch toggle --%>
              <div class="grid grid-cols-2 gap-px bg-base-200 rounded-lg overflow-hidden text-sm">
                <label class={[
                  "py-3 text-center cursor-pointer",
                  @register_tracking == "individual" &&
                    "bg-primary text-primary-content font-semibold",
                  @register_tracking != "individual" && "bg-base-100"
                ]}>
                  <input
                    type="radio"
                    name="animal[tracking_type]"
                    value="individual"
                    checked={@register_tracking == "individual"}
                    class="hidden"
                  />
                  {gettext("Individual")}
                </label>
                <label class={[
                  "py-3 text-center cursor-pointer",
                  @register_tracking == "batch" && "bg-primary text-primary-content font-semibold",
                  @register_tracking != "batch" && "bg-base-100"
                ]}>
                  <input
                    type="radio"
                    name="animal[tracking_type]"
                    value="batch"
                    checked={@register_tracking == "batch"}
                    class="hidden"
                  />
                  {gettext("Batch")}
                </label>
              </div>

              <label class="block">
                <span class="text-xs uppercase text-base-content/60">
                  {if @register_tracking == "batch",
                    do: gettext("Batch number"),
                    else: gettext("Ear tag")}
                </span>
                <input
                  type="text"
                  name="animal[ear_tag]"
                  value={Phoenix.HTML.Form.input_value(f, :ear_tag)}
                  required
                  autocomplete="off"
                  class="input input-bordered input-lg w-full mt-1 font-mono text-base"
                />
              </label>

              <label class="block">
                <span class="text-xs uppercase text-base-content/60">{gettext("Stage")}</span>
                <select name="animal[stage]" class="select select-bordered select-lg w-full mt-1">
                  <option
                    :for={s <- Animal.stages_for(@register_tracking)}
                    value={s}
                    selected={Phoenix.HTML.Form.input_value(f, :stage) == s}
                  >
                    {String.capitalize(s)}
                  </option>
                </select>
              </label>

              <div class="grid grid-cols-2 gap-3">
                <label :if={@register_tracking == "batch"} class="block">
                  <span class="text-xs uppercase text-base-content/60">{gettext("Quantity")}</span>
                  <input
                    type="number"
                    name="animal[quantity]"
                    value={Phoenix.HTML.Form.input_value(f, :quantity)}
                    min="1"
                    inputmode="numeric"
                    class="input input-bordered input-lg w-full mt-1 font-mono"
                  />
                </label>
                <label class="block">
                  <span class="text-xs uppercase text-base-content/60">{gettext("DOB")}</span>
                  <input
                    type="date"
                    name="animal[dob]"
                    value={Phoenix.HTML.Form.input_value(f, :dob)}
                    class="input input-bordered input-lg w-full mt-1"
                  />
                </label>
                <label :if={@register_tracking == "individual"} class="block">
                  <span class="text-xs uppercase text-base-content/60">{gettext("Breed")}</span>
                  <input
                    type="text"
                    name="animal[breed]"
                    value={Phoenix.HTML.Form.input_value(f, :breed)}
                    class="input input-bordered input-lg w-full mt-1"
                  />
                </label>
              </div>

              <label :if={@register_tracking == "batch"} class="block">
                <span class="text-xs uppercase text-base-content/60">{gettext("Breed")}</span>
                <input
                  type="text"
                  name="animal[breed]"
                  value={Phoenix.HTML.Form.input_value(f, :breed)}
                  class="input input-bordered input-lg w-full mt-1"
                />
              </label>

              <label class="block">
                <span class="text-xs uppercase text-base-content/60">
                  {gettext("Pen (HOUSE-PEN)")}
                </span>
                <input
                  type="text"
                  name="pen_code"
                  value={@register_pen_code}
                  phx-debounce="300"
                  autocomplete="off"
                  spellcheck="false"
                  placeholder="EB-12"
                  class={[
                    "input input-bordered input-lg w-full mt-1 font-mono",
                    @register_pen_state == :resolved && "border-success focus:border-success",
                    @register_pen_state == :not_found && "border-error focus:border-error"
                  ]}
                />
                <span class={[
                  "text-xs mt-1 block",
                  @register_pen_state == :resolved && "text-success",
                  @register_pen_state == :not_found && "text-error",
                  @register_pen_state == :empty && "text-base-content/50"
                ]}>
                  {pen_state_text(@register_pen_state)}
                </span>
              </label>

              <p :if={@register_error} class="text-sm text-error">{@register_error}</p>

              <div class="grid grid-cols-2 gap-3 pt-2">
                <button type="button" phx-click="register_close" class="btn btn-lg btn-ghost">
                  {gettext("Cancel")}
                </button>
                <button
                  type="submit"
                  phx-disable-with={gettext("Saving…")}
                  class="btn btn-lg btn-primary"
                >
                  {gettext("Register")}
                </button>
              </div>
            </div>
          </.form>
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
       today: FarmClock.today(scope),
       avg_wean_age: Breeding.avg_weaning_age_days(scope),
       per_page: @per_page,
       batch_stages: @batch_stages,
       filter_drawer_open: false,
       parity_map: %{},
       event_map: %{},
       can_manage: Policy.can?(scope, :manage_animals),
       register_form: nil,
       register_tracking: "individual",
       register_pen_code: "",
       register_pen_state: :empty,
       register_pen_id: nil,
       register_error: nil
     )
     |> stream(:animals, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = %{
      stage: params["stage"] || "",
      status: status_param(params["status"], params["stage"]),
      pen_search: params["pen_search"] || "",
      tag_search: params["tag_search"] || "",
      min_age: params["min_age"] || "",
      max_age: params["max_age"] || "",
      min_parity: params["min_parity"] || "",
      max_parity: params["max_parity"] || "",
      needs_review: params["needs_review"] in ["1", "true"]
    }

    {:noreply,
     socket
     |> assign(filters: filters, page: 1)
     |> load_rows()}
  end

  # ── Events ─────────────────────────────────────────────────────────

  @impl true
  def handle_event("search", %{"q" => q}, socket),
    do: {:noreply, push_patch_filters(socket, %{"tag_search" => q})}

  def handle_event("filter", params, socket) do
    new_stage = params["stage"] || ""
    raw_status = params["status"] || socket.assigns.filters.status
    status = if valid_status_for_stage?(raw_status, new_stage), do: raw_status, else: "present"

    {:noreply,
     push_patch_filters(socket, %{
       "stage" => new_stage,
       "status" => status,
       "pen_search" => params["pen_search"] || "",
       "tag_search" => params["tag_search"] || "",
       "min_age" => params["min_age"] || "",
       "max_age" => params["max_age"] || "",
       "min_parity" => params["min_parity"] || "",
       "max_parity" => params["max_parity"] || "",
       "needs_review" => if(params["needs_review"] in ["1", "true", "on"], do: "1", else: "")
     })}
  end

  def handle_event("reset_filters", _, socket) do
    {:noreply, push_patch(socket, to: ~p"/m/#{socket.assigns.current_scope.farm.slug}/animals")}
  end

  def handle_event("open_filters", _, socket),
    do: {:noreply, assign(socket, :filter_drawer_open, true)}

  def handle_event("close_filters", _, socket),
    do: {:noreply, assign(socket, :filter_drawer_open, false)}

  def handle_event("ignore_click", _, socket), do: {:noreply, socket}

  def handle_event("load_more", _, socket) do
    {:noreply, append_rows(socket)}
  end

  # ── Register ──

  def handle_event("register_open", _, socket) do
    if socket.assigns.can_manage do
      today = socket.assigns.today

      cs =
        Animals.change_animal(%Animal{
          tracking_type: "individual",
          stage: "sow",
          status: "active",
          dob: today,
          quantity: 1
        })

      {:noreply,
       assign(socket,
         register_form: to_form(cs, as: :animal),
         register_tracking: "individual",
         register_pen_code: "",
         register_pen_state: :empty,
         register_pen_id: nil,
         register_error: nil
       )}
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("register_close", _, socket), do: {:noreply, reset_register(socket)}

  def handle_event("register_validate", %{"animal" => params} = all, socket) do
    new_tracking = Map.get(params, "tracking_type", socket.assigns.register_tracking)

    # When toggling between individual and batch, the existing stage may
    # not apply (e.g. sow → weaner). Reset to the first allowed stage.
    params =
      if new_tracking != socket.assigns.register_tracking do
        Map.put(params, "stage", Animal.stages_for(new_tracking) |> List.first())
      else
        params
      end

    cs =
      Animals.change_animal(%Animal{}, params)
      |> Map.put(:action, :validate)

    socket
    |> assign(
      register_form: to_form(cs, as: :animal),
      register_tracking: new_tracking,
      register_error: nil
    )
    |> resolve_register_pen(all["pen_code"])
    |> then(&{:noreply, &1})
  end

  def handle_event("register_save", %{"animal" => params} = all, socket) do
    if socket.assigns.can_manage do
      socket = resolve_register_pen(socket, all["pen_code"])
      tracking = Map.get(params, "tracking_type", socket.assigns.register_tracking)

      attrs =
        params
        |> Map.put("current_pen_id", socket.assigns.register_pen_id)
        |> Map.put("status", "active")
        |> Map.put("tracking_type", tracking)

      case Animals.create_animal(socket.assigns.current_scope, attrs) do
        {:ok, animal} ->
          {:noreply,
           socket
           |> reset_register()
           |> load_rows()
           |> push_patch(
             to: ~p"/m/#{socket.assigns.current_scope.farm.slug}/animals/#{animal.id}"
           )
           |> put_flash(:info, gettext("Animal registered."))}

        {:error, %Ecto.Changeset{} = cs} ->
          {:noreply, assign(socket, register_form: to_form(cs, as: :animal))}

        {:error, other} ->
          {:noreply, assign(socket, register_error: inspect(other))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp push_patch_filters(socket, overrides) do
    f = socket.assigns.filters

    base = %{
      "stage" => f.stage,
      "status" => f.status,
      "pen_search" => f.pen_search,
      "tag_search" => f.tag_search,
      "min_age" => f.min_age,
      "max_age" => f.max_age,
      "min_parity" => f.min_parity,
      "max_parity" => f.max_parity,
      "needs_review" => if(f.needs_review, do: "1", else: "")
    }

    merged =
      base
      |> Map.merge(overrides)
      |> Enum.reject(fn
        {_k, ""} -> true
        {_k, nil} -> true
        _ -> false
      end)
      |> Map.new()
      # status is always sticky (default "present" represents an explicit pick)
      |> Map.put_new("status", overrides["status"] || f.status)

    slug = socket.assigns.current_scope.farm.slug

    path =
      case merged do
        m when map_size(m) == 0 -> ~p"/m/#{slug}/animals"
        m -> ~p"/m/#{slug}/animals?#{m}"
      end

    push_patch(socket, to: path)
  end

  defp active_filter_count(f) do
    [
      f.stage != "",
      f.status not in ["present", "", nil],
      f.pen_search != "",
      f.tag_search != "",
      f.min_age != "",
      f.max_age != "",
      f.min_parity != "",
      f.max_parity != "",
      f.needs_review
    ]
    |> Enum.count(& &1)
  end

  defp load_rows(socket) do
    scope = socket.assigns.current_scope
    rows = Animals.list_animals(scope, opts(socket))
    total = Animals.count_animals(scope, opts_count(socket))

    socket
    |> assign(
      total: total,
      page: 1,
      has_more: length(rows) < total,
      parity_map: parity_map(scope, rows),
      event_map: event_map(scope, rows)
    )
    |> stream(:animals, rows, reset: true)
  end

  defp append_rows(socket) do
    scope = socket.assigns.current_scope
    next_page = socket.assigns.page + 1
    rows = Animals.list_animals(scope, opts(socket, next_page))
    loaded = next_page * @per_page

    socket =
      Enum.reduce(rows, socket, fn row, acc -> stream_insert(acc, :animals, row) end)

    assign(socket,
      page: next_page,
      has_more: loaded < socket.assigns.total,
      parity_map: Map.merge(socket.assigns.parity_map, parity_map(scope, rows)),
      event_map: Map.merge(socket.assigns.event_map, event_map(scope, rows))
    )
  end

  defp opts(socket, page \\ 1) do
    f = socket.assigns.filters

    [
      stage: blank_to_nil(f.stage),
      status: blank_to_nil(f.status),
      needs_review: f.needs_review,
      pen_search: blank_to_nil(f.pen_search),
      tag_search: blank_to_nil(f.tag_search),
      min_age_days: parse_int(f.min_age),
      max_age_days: parse_int(f.max_age),
      min_parity: parse_int(f.min_parity),
      max_parity: parse_int(f.max_parity),
      limit: @per_page,
      offset: (page - 1) * @per_page
    ]
  end

  defp opts_count(socket) do
    socket
    |> opts()
    |> Keyword.delete(:limit)
    |> Keyword.delete(:offset)
  end

  defp parity_map(scope, rows) do
    sow_ids =
      rows
      |> Enum.filter(&(&1.stage == "sow" and &1.tracking_type == "individual"))
      |> Enum.map(& &1.id)

    Breeding.parities_for(scope, sow_ids)
  end

  defp event_map(scope, rows) do
    sow_ids =
      rows
      |> Enum.filter(&(&1.stage == "sow" and &1.tracking_type == "individual"))
      |> Enum.map(& &1.id)

    Breeding.last_event_dates_for(scope, sow_ids)
  end

  # Bottom line of the card. Tries to surface the next actionable date
  # (e.g. expected farrowing for a served sow); falls back to "Days in
  # status" for sows where no breeding event applies, and to total head
  # count for batches.
  defp footer_line(scope, %{stage: "sow", status: "served", id: id}, event_map, today, _avg) do
    case event_map do
      %{^id => %{served_at: %Date{} = served_at}} ->
        due = Date.add(served_at, Breeding.gestation_days(scope))
        days = Date.diff(due, today)
        {gettext("Farrow due"), due_text(days)}

      _ ->
        nil
    end
  end

  defp footer_line(_scope, %{stage: "sow", status: "lactating", id: id}, event_map, today, avg) do
    case event_map do
      %{^id => %{farrowed_at: %Date{} = farrowed_at}} when is_integer(avg) ->
        due = Date.add(farrowed_at, avg)
        days = Date.diff(due, today)
        {gettext("Wean due"), due_text(days)}

      %{^id => %{farrowed_at: %Date{} = farrowed_at}} ->
        {gettext("Farrowed"), "#{Date.diff(today, farrowed_at)}d ago"}

      _ ->
        nil
    end
  end

  defp footer_line(_scope, %{stage: "sow", status: status, id: id}, event_map, today, _avg)
       when status in ~w(open dry) do
    # Pick whichever cycle-ending event is most recent: weaning,
    # abortion, or (rare) a stale farrowing. Without this, a sow
    # whose latest event was an abortion would silently show no
    # footer line (or a stale weaning from a prior cycle).
    case Map.get(event_map, id) do
      nil ->
        nil

      %{} = events ->
        candidates =
          [
            {:weaned, gettext("Weaned"), events[:weaned_at]},
            {:aborted, gettext("Aborted"), events[:aborted_at]},
            {:farrowed, gettext("Farrowed"), events[:farrowed_at]}
          ]
          |> Enum.reject(fn {_, _, d} -> is_nil(d) end)

        case candidates do
          [] ->
            nil

          list ->
            {_, label, date} = Enum.max_by(list, fn {_, _, d} -> d end, Date)
            {label, "#{Date.diff(today, date)}d ago"}
        end
    end
  end

  defp footer_line(_scope, %{tracking_type: "batch"} = a, _event_map, _today, _avg) do
    case batch_total_head(a) do
      0 -> nil
      n -> {gettext("Head"), Integer.to_string(n)}
    end
  end

  defp footer_line(_scope, %{stage: "sow"} = a, _event_map, today, _avg) do
    case days_in_status(a, today) do
      nil -> nil
      d -> {gettext("Days in status"), "#{d}d"}
    end
  end

  defp footer_line(_, _, _, _, _), do: nil

  defp due_text(d) when d > 0, do: "in #{d}d"
  defp due_text(0), do: gettext("today")
  defp due_text(d), do: "#{-d}d overdue"

  defp batch_total_head(%{placements: [_ | _] = placements}),
    do: Enum.reduce(placements, 0, &(&1.quantity + &2))

  defp batch_total_head(_), do: 0

  defp stage_suffix(%{stage: "sow", id: id}, parity_map, _avg, _today) do
    case Map.get(parity_map, id) do
      nil -> ""
      n -> " · P#{n}"
    end
  end

  defp stage_suffix(%{stage: stage} = a, _parity, avg_wean_age, today)
       when stage in @batch_stages do
    case batch_age_days(a, avg_wean_age, today) do
      nil -> ""
      d -> " · #{d}d"
    end
  end

  defp stage_suffix(_, _, _, _), do: ""

  defp batch_age_days(%{farrowing: %{weaning: %{weaned_at: weaned_at}}}, avg, today)
       when not is_nil(weaned_at) and is_integer(avg) do
    Date.diff(today, weaned_at) + avg
  end

  defp batch_age_days(%{dob: %Date{} = dob}, _avg, today) do
    Date.diff(today, dob)
  end

  defp batch_age_days(_, _, _), do: nil

  defp pen_label(%{tracking_type: "batch", placements: [_ | _] = placements}) do
    Enum.map_join(placements, " · ", fn p ->
      "#{p.pen.house.code}-#{p.pen.code}×#{p.quantity}"
    end)
  end

  defp pen_label(%{current_pen: %{code: code, house: %{code: hcode}}}), do: "#{hcode}-#{code}"
  defp pen_label(%{current_pen: %{code: code}}), do: code
  defp pen_label(_), do: "—"

  defp days_in_status(
         %{stage: "sow", status: status, status_changed_at: %DateTime{} = ts},
         today
       )
       when is_binary(status) do
    if status in Animal.present_statuses() do
      Date.diff(today, DateTime.to_date(ts))
    else
      nil
    end
  end

  defp days_in_status(_, _), do: nil

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} when n >= 0 -> n
      _ -> nil
    end
  end

  defp parse_int(n) when is_integer(n), do: n
  defp parse_int(_), do: nil

  defp status_options(stage) do
    base = [{gettext("Present (any)"), "present"}]

    sow_groupings =
      if stage == "sow" or stage == "" do
        [
          {gettext("Serviceable"), "serviceable"},
          {gettext("Breeding herd"), "breeding_herd"}
        ]
      else
        []
      end

    tail = [
      {gettext("Departed (any)"), "departed"},
      {gettext("All"), ""}
    ]

    individual_statuses =
      stage
      |> Animal.statuses_for_stage()
      |> Enum.map(&{Animal.status_label(&1), &1})

    base ++ sow_groupings ++ tail ++ individual_statuses
  end

  defp status_param(nil, _stage), do: "present"
  defp status_param("", _stage), do: ""
  defp status_param(s, stage), do: if(valid_status_for_stage?(s, stage), do: s, else: "present")

  defp valid_status_for_stage?(status, stage) do
    status in [nil, "", "present", "departed", "serviceable", "breeding_herd", "saleable"] or
      status in Animal.statuses_for_stage(stage)
  end

  defp reset_register(socket) do
    assign(socket,
      register_form: nil,
      register_tracking: "individual",
      register_pen_code: "",
      register_pen_state: :empty,
      register_pen_id: nil,
      register_error: nil
    )
  end

  defp resolve_register_pen(socket, nil), do: socket

  defp resolve_register_pen(socket, ""),
    do: assign(socket, register_pen_code: "", register_pen_state: :empty, register_pen_id: nil)

  defp resolve_register_pen(socket, code) when is_binary(code) do
    code = String.trim(code)

    case Locations.find_pen_by_code(socket.assigns.current_scope, code) do
      nil ->
        assign(socket,
          register_pen_code: code,
          register_pen_state: :not_found,
          register_pen_id: nil
        )

      pen ->
        assign(socket,
          register_pen_code: code,
          register_pen_state: :resolved,
          register_pen_id: pen.id
        )
    end
  end

  defp pen_state_text(:resolved), do: "✓"
  defp pen_state_text(:not_found), do: "⚠ No active pen with that code"
  defp pen_state_text(_), do: "Type house-pen, e.g. EB-12"
end
