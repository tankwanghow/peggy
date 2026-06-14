defmodule PeggyWeb.MobileLive.Breeding.Gestating do
  @moduledoc """
  Mobile-first Gestating tab.

  Designed for barn-floor use on a phone:
    - card-per-sow with a colour-coded "days until farrow" headline
    - sticky search bar with collapsible filter drawer (due window,
      service type, pen, parity)
    - bottom action sheet that swaps in place between Farrow / Close
      service forms; destructive Delete service is intentionally
      desktop-only.
  """
  use PeggyWeb, :live_view

  alias Peggy.{Animals, Breeding, FarmClock, Locations, Policy}
  alias Peggy.Breeding.{Farrowing, Service}
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
              :if={@filters.q not in [nil, ""]}
              type="button"
              phx-click="clear_search"
              aria-label={gettext("Clear search")}
              class="btn btn-ghost btn-circle btn-sm"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
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

        <%!-- Tab switch (Lactating / Gestating) — small dual link strip --%>
        <nav class="px-3 pt-2 flex gap-2 text-xs">
          <.link
            navigate={~p"/m/#{@current_scope.farm.slug}/breeding/serviceable"}
            class="px-3 py-1 rounded-full border border-base-300 text-base-content/70"
          >
            {gettext("Serviceable")}
          </.link>
          <.link
            navigate={~p"/m/#{@current_scope.farm.slug}/breeding/gestating"}
            class="px-3 py-1 rounded-full bg-primary text-primary-content font-semibold"
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

        <p :if={@total > 0} class="px-4 pt-1 text-xs text-base-content/50">
          {gettext("%{n} results", n: @total)}
        </p>

        <%!-- Cards --%>
        <ul id="gestating-cards" phx-update="stream" class="px-3 py-2 space-y-1">
          <li
            :for={{dom_id, e} <- @streams.gestating}
            id={dom_id}
            phx-click="open_actions"
            phx-value-service-id={e.service.id}
            class="px-4 pt-2 rounded-xl border border-base-300 bg-base-100 shadow-sm
                   active:bg-base-200 cursor-pointer touch-manipulation"
          >
            <div class="flex items-baseline justify-between">
              <span class="font-mono font-bold text-xl">{e.service.sow.ear_tag}</span>
              <span><.cull_flag animal={e.service.sow} /></span>
              <span><.icon name="hero-map-pin-micro" class="size-4 text-blue-600" /></span>
              <span class="font-mono">{sow_pen_label(e.service.sow)}</span>
              <span class="text-sm text-base-content/50">
                {gettext("Parity")}
                <span class="font-mono font-bold text-info">{e.parity}</span>
              </span>
            </div>

            <div class="flex items-center gap-2 text-sm text-base-content/70 justify-between">
              <div class="">
                <span class="text-base-content/50">
                  {gettext("Type")}
                  <span class="uppercase font-semibold">{e.service.service_type}</span>
                  <span><Shared.recently_updated_badge at={e.service.updated_at} /></span>
                </span>
                <div>
                  <div class={[
                    "font-mono text-xl",
                    days_left_color(days_left(e, @today))
                  ]}>
                    {days_left_display(days_left(e, @today))}
                    <span class="text-base-content/50 text-xs">
                      {days_left_label(days_left(e, @today))}
                    </span>
                  </div>
                </div>
              </div>

              <dl class="text-right text-xs leading-snug grid grid-cols-[auto_auto] gap-x-2 items-baseline">
                <dt class="text-base-content/50">{gettext("Served")}</dt>
                <dd class="font-mono text-base-content/70">{e.service.served_at}</dd>
                <dt :if={(e.service.mounting_count || 1) > 1} class="text-base-content/50">
                  {gettext("Mounted")}
                </dt>
                <dd
                  :if={(e.service.mounting_count || 1) > 1}
                  class="text-xs font-semibold text-info"
                >
                  {e.service.mounting_count} ({e.service.last_serviced_at})
                </dd>
                <dt class="text-base-content/50">{gettext("Expected")}</dt>
                <dd class="font-mono font-semibold">{e.expected_farrow_date}</dd>
                <dt :if={e.service.boar} class="text-base-content/50">{gettext("Boar")}</dt>
                <dd :if={e.service.boar} class="font-mono">{e.service.boar.ear_tag}</dd>
              </dl>
            </div>
          </li>
        </ul>

        <p :if={@total == 0} class="px-4 py-8 text-center text-sm text-base-content/60">
          {gettext("No gestating sows match the filters.")}
        </p>

        <.infinite_scroll
          has_more={@has_more}
          total={@total}
          id="gestating-mobile-sentinel"
        />

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
                  :if={@sheet_service}
                  navigate={~p"/m/#{@current_scope.farm.slug}/animals/#{@sheet_service.sow_id}"}
                  class="font-mono font-bold text-lg text-primary underline underline-offset-2 decoration-dotted active:decoration-solid"
                >
                  {@sheet_sow_tag}
                </.link>
                <div
                  :if={is_nil(@sheet_service)}
                  class="font-mono font-bold text-lg"
                >
                  {@sheet_sow_tag}
                </div>
                <div :if={@sheet_service} class="text-xs text-base-content/60">
                  {gettext("Expected")} {expected_for(@current_scope, @sheet_service)} · {days_left_label(
                    days_left_for(@current_scope, @sheet_service, @today)
                  )}
                  {days_left_display(days_left_for(@current_scope, @sheet_service, @today))}
                </div>
              </div>
            </div>

            <%!-- Action menu --%>
            <div
              :if={@sheet_mode == :menu and @can_record}
              class="grid grid-cols-2 gap-px bg-base-200"
            >
              <button
                phx-click="action_farrow"
                class="bg-base-100 py-5 flex flex-col items-center gap-1 active:bg-success/10"
              >
                <.icon name="hero-sparkles" class="size-7 text-success" />
                <span class="text-xs">{gettext("Farrow")}</span>
              </button>
              <button
                phx-click="action_re_service"
                class="bg-base-100 py-5 flex flex-col items-center gap-1 active:bg-pink-500/10"
              >
                <.icon name="hero-heart" class="size-7 text-pink-500" />
                <span class="text-xs">{gettext("Re-service")}</span>
              </button>
              <button
                phx-click="action_move"
                class="bg-base-100 py-5 flex flex-col items-center gap-1 active:bg-info/10"
              >
                <.icon name="hero-truck" class="size-7 text-info" />
                <span class="text-xs">{gettext("Move")}</span>
              </button>
              <button
                phx-click="action_close"
                class="bg-base-100 py-5 flex flex-col items-center gap-1 active:bg-error/10"
              >
                <.icon name="hero-x-circle" class="size-7 text-error" />
                <span class="text-xs">{gettext("Close service")}</span>
              </button>
            </div>

            <p
              :if={@sheet_mode == :menu and not @can_record}
              class="px-4 py-6 text-center text-sm text-base-content/60"
            >
              {gettext("View-only — you don't have permission to record breeding.")}
            </p>

            <%!-- Farrow form --%>
            <.form
              :let={f}
              :if={@sheet_mode == :farrow and @farrow_form}
              for={@farrow_form}
              phx-change="validate_farrow"
              phx-submit="save_farrow"
              class="px-4 py-3 space-y-4"
            >
              <label class="block">
                <span class="text-xs uppercase text-base-content/60">{gettext("Farrowed at")}</span>
                <input
                  type="date"
                  name="farrowing[farrowed_at]"
                  value={Phoenix.HTML.Form.input_value(f, :farrowed_at)}
                  class="input input-bordered input-lg w-full mt-1"
                />
              </label>

              <div class="grid grid-cols-3 gap-2">
                <label class="block">
                  <span class="text-xs uppercase text-base-content/60">
                    {gettext("Born alive")}
                  </span>
                  <input
                    type="number"
                    name="farrowing[born_alive]"
                    value={Phoenix.HTML.Form.input_value(f, :born_alive)}
                    min="0"
                    inputmode="numeric"
                    class="input input-bordered input-lg w-full mt-1 text-2xl font-mono text-success"
                  />
                </label>
                <label class="block">
                  <span class="text-xs uppercase text-base-content/60">
                    {gettext("Stillborn")}
                  </span>
                  <input
                    type="number"
                    name="farrowing[stillborn]"
                    value={Phoenix.HTML.Form.input_value(f, :stillborn)}
                    min="0"
                    inputmode="numeric"
                    class="input input-bordered input-lg w-full mt-1 text-2xl font-mono text-error"
                  />
                </label>
                <label class="block">
                  <span class="text-xs uppercase text-base-content/60">
                    {gettext("Mummified")}
                  </span>
                  <input
                    type="number"
                    name="farrowing[mummified]"
                    value={Phoenix.HTML.Form.input_value(f, :mummified)}
                    min="0"
                    inputmode="numeric"
                    class="input input-bordered input-lg w-full mt-1 text-2xl font-mono text-warning"
                  />
                </label>
              </div>

              <label class="block">
                <span class="text-xs uppercase text-base-content/60">
                  {gettext("Notes (optional)")}
                </span>
                <textarea
                  name="farrowing[notes]"
                  rows="2"
                  class="textarea textarea-bordered w-full mt-1"
                >{Phoenix.HTML.Form.input_value(f, :notes)}</textarea>
              </label>

              <p :if={@farrow_error} class="text-sm text-error">{@farrow_error}</p>

              <div class="grid grid-cols-2 gap-3 pt-2">
                <button type="button" phx-click="action_back" class="btn btn-lg btn-ghost">
                  {gettext("Cancel")}
                </button>
                <button
                  type="submit"
                  phx-disable-with={gettext("Saving…")}
                  class="btn btn-lg btn-primary"
                >
                  {gettext("Farrowed")}
                </button>
              </div>
            </.form>

            <%!-- Close service form --%>
            <.form
              :let={f}
              :if={@sheet_mode == :close and @close_form}
              for={@close_form}
              phx-change="validate_close"
              phx-submit="save_close"
              class="px-4 py-3 space-y-4"
            >
              <label class="block">
                <span class="text-xs uppercase text-base-content/60">{gettext("Result")}</span>
                <select
                  name="service[result]"
                  class="select select-bordered select-lg w-full mt-1"
                >
                  <option
                    value="abortion"
                    selected={Phoenix.HTML.Form.input_value(f, :result) == "abortion"}
                  >
                    {gettext("Abortion")}
                  </option>
                  <option
                    value="failed_pregnancy"
                    selected={Phoenix.HTML.Form.input_value(f, :result) == "failed_pregnancy"}
                  >
                    {gettext("Failed pregnancy")}
                  </option>
                </select>
              </label>

              <label class="block">
                <span class="text-xs uppercase text-base-content/60">{gettext("Date")}</span>
                <input
                  type="date"
                  name="service[result_at]"
                  value={Phoenix.HTML.Form.input_value(f, :result_at)}
                  class="input input-bordered input-lg w-full mt-1"
                />
              </label>

              <label class="block">
                <span class="text-xs uppercase text-base-content/60">
                  {gettext("Notes (optional)")}
                </span>
                <textarea
                  name="service[result_notes]"
                  rows="2"
                  class="textarea textarea-bordered w-full mt-1"
                >{Phoenix.HTML.Form.input_value(f, :result_notes)}</textarea>
              </label>

              <p :if={@close_error} class="text-sm text-error">{@close_error}</p>

              <div class="grid grid-cols-2 gap-3 pt-2">
                <button type="button" phx-click="action_back" class="btn btn-lg btn-ghost">
                  {gettext("Cancel")}
                </button>
                <button
                  type="submit"
                  phx-disable-with={gettext("Closing…")}
                  class="btn btn-lg btn-error"
                >
                  {gettext("Serv. Closed")}
                </button>
              </div>
            </.form>

            <%!-- Re-service form --%>
            <form
              :if={@sheet_mode == :re_service}
              phx-change="service_validate"
              phx-submit="service_save"
              class="px-4 py-3 space-y-4"
            >
              <%!-- Locked sow tag travels via hidden input so service_validate
                   keeps the resolution state in sync on each phx-change. --%>
              <input type="hidden" name="sow_tag" value={@service_sow_tag} />

              <label class="block">
                <span class="text-xs uppercase text-base-content/60">{gettext("Service type")}</span>
                <select
                  name="service_type"
                  class="select select-bordered select-lg w-full mt-1"
                >
                  <option value="ai" selected={@service_type == "ai"}>{gettext("AI")}</option>
                  <option value="natural" selected={@service_type == "natural"}>
                    {gettext("Natural")}
                  </option>
                </select>
              </label>

              <div :if={@service_type == "natural"}>
                <.autocomplete
                  id="service-boar"
                  label={gettext("Boar ear tag")}
                  name="boar_id"
                  value={@service_boar_id}
                  items={@service_boar_items}
                  selected_label={@service_boar_label}
                  drop_up
                  touch
                  empty_text={gettext("No boar with that tag")}
                />
              </div>

              <label class="block">
                <span class="text-xs uppercase text-base-content/60">{gettext("Served at")}</span>
                <input
                  type="date"
                  name="served_at"
                  value={@service_served_at}
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
                  value={@service_semen}
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
                  value={@service_pen_code}
                  phx-debounce="300"
                  autocomplete="off"
                  placeholder="EB-12"
                  class={[
                    "input input-bordered input-lg w-full mt-1 font-mono",
                    @service_pen_state == :resolved && "border-success focus:border-success",
                    @service_pen_state == :not_found && "border-error focus:border-error"
                  ]}
                />
                <span class={[
                  "text-xs mt-1 block",
                  @service_pen_state == :resolved && "text-success",
                  @service_pen_state == :not_found && "text-error",
                  @service_pen_state == :empty && "text-base-content/50"
                ]}>
                  {gestating_pen_state_text(@service_pen_state)}
                </span>
              </label>

              <p :if={@service_error} class="text-sm text-error">{@service_error}</p>

              <div class="grid grid-cols-2 gap-3 pt-2">
                <button type="button" phx-click="action_back" class="btn btn-lg btn-ghost">
                  {gettext("Cancel")}
                </button>
                <button
                  type="submit"
                  phx-disable-with={gettext("Saving…")}
                  disabled={not service_save_enabled?(assigns)}
                  class="btn btn-lg btn-primary"
                >
                  {gettext("Re-serviced")}
                </button>
              </div>
            </form>

            <%!-- Move form --%>
            <MovementForm.move_form
              :if={@sheet_mode == :move and @move_form}
              form={@move_form}
              animal={@move_animal}
              pen_items={@move_pen_items}
              from_label={@move_from_label}
              from_id={@move_from_id}
              to_label={@move_to_label}
              to_id={@move_to_id}
              error={@move_error}
            />

            <button
              :if={@sheet_mode == :menu}
              phx-click="close_actions"
              class="w-full py-3 text-sm text-base-content/60 border-t border-base-200"
            >
              {gettext("Close")}
            </button>
          </div>
        </div>

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
                <span class="text-xs uppercase text-base-content/60">{gettext("Due window")}</span>
                <select name="window" class="select select-bordered select-lg w-full mt-1">
                  <option value="all" selected={@filters.window == "all"}>{gettext("All")}</option>
                  <option value="7" selected={@filters.window == "7"}>{gettext("≤ 7 days")}</option>
                  <option value="14" selected={@filters.window == "14"}>
                    {gettext("≤ 14 days")}
                  </option>
                  <option value="overdue" selected={@filters.window == "overdue"}>
                    {gettext("Overdue")}
                  </option>
                </select>
              </label>

              <label class="block">
                <span class="text-xs uppercase text-base-content/60">{gettext("Service type")}</span>
                <select name="service_type" class="select select-bordered select-lg w-full mt-1">
                  <option value="all" selected={@filters.service_type == "all"}>
                    {gettext("All")}
                  </option>
                  <option value="ai" selected={@filters.service_type == "ai"}>{gettext("AI")}</option>
                  <option value="natural" selected={@filters.service_type == "natural"}>
                    {gettext("Natural")}
                  </option>
                </select>
              </label>

              <label class="block">
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
       sheet_service: nil,
       sheet_sow_tag: nil,
       farrow_form: nil,
       farrow_error: nil,
       close_form: nil,
       close_error: nil,
       service_sow_tag: "",
       service_sow_state: :empty,
       service_sow_status: nil,
       service_sow_id: nil,
       service_boar_items: [],
       service_boar_label: nil,
       service_boar_id: nil,
       service_type: "ai",
       service_served_at: to_string(FarmClock.today(scope)),
       service_pen_code: "",
       service_pen_state: :empty,
       service_pen_id: nil,
       service_semen: nil,
       service_error: nil,
       sort: "served",
       dir: "asc"
     )
     |> assign(MovementForm.init())
     |> stream_configure(:gestating, dom_id: &"service-#{&1.service.id}")
     |> stream(:gestating, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = %{
      q: params["q"] || "",
      window: Shared.param_window(params["window"]),
      service_type: Shared.param_service_type(params["service_type"]),
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

  # Combined `sort=<field>-<dir>` URL param (e.g. "tag-desc"). Single
  # form binding; falls back to (served, asc) on anything unrecognised.
  @sort_options ~w(served-asc served-desc tag-asc tag-desc parity-asc parity-desc pen-asc)

  defp parse_sort_param(s) when is_binary(s) do
    if s in @sort_options do
      [field, dir] = String.split(s, "-", parts: 2)
      {field, dir}
    else
      {"served", "asc"}
    end
  end

  defp parse_sort_param(_), do: {"served", "asc"}

  defp sort_to_param("served", "asc"), do: nil
  defp sort_to_param(field, dir), do: "#{field}-#{dir}"

  # Combined-direction options for the mobile filter-drawer dropdown.
  defp sort_options do
    [
      {"served-asc", gettext("Most overdue first")},
      {"served-desc", gettext("Most days left first")},
      {"tag-asc", gettext("Tag A→Z")},
      {"tag-desc", gettext("Tag Z→A")},
      {"parity-asc", gettext("Parity (low to high)")},
      {"parity-desc", gettext("Parity (high to low)")},
      {"pen-asc", gettext("Pen")}
    ]
  end

  # ── Events ─────────────────────────────────────────────────────────

  @impl true
  def handle_event("search", %{"q" => q}, socket),
    do: {:noreply, push_patch_filters(socket, %{"q" => q})}

  def handle_event("clear_search", _params, socket),
    do: {:noreply, push_patch_filters(socket, %{"q" => ""})}

  def handle_event("filter", params, socket) do
    {:noreply,
     push_patch_filters(socket, %{
       "window" => params["window"] || "all",
       "service_type" => params["service_type"] || "all",
       "pen_search" => params["pen_search"] || "",
       "min_parity" => params["min_parity"] || "",
       "max_parity" => params["max_parity"] || "",
       "sort" => params["sort"] || ""
     })}
  end

  def handle_event("reset_filters", _, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/m/#{socket.assigns.current_scope.farm.slug}/breeding/gestating"
     )}
  end

  def handle_event("open_filters", _, socket),
    do: {:noreply, assign(socket, :filter_drawer_open, true)}

  def handle_event("close_filters", _, socket),
    do: {:noreply, assign(socket, :filter_drawer_open, false)}

  def handle_event("ignore_click", _, socket), do: {:noreply, socket}

  def handle_event("open_actions", %{"service-id" => id}, socket) do
    scope = socket.assigns.current_scope

    service =
      Breeding.get_service!(scope, String.to_integer(id))
      |> Peggy.Repo.preload([:boar, :sow])

    {:noreply,
     socket
     |> reset_sheet_state()
     |> assign(
       action_sheet_for: service.id,
       sheet_mode: :menu,
       sheet_service: service,
       sheet_sow_tag: service.sow.ear_tag
     )}
  end

  def handle_event("close_actions", _, socket), do: {:noreply, reset_sheet(socket)}

  def handle_event("action_back", _, socket) do
    {:noreply,
     socket
     |> reset_sheet_state()
     |> assign(sheet_mode: :menu)}
  end

  # Farrow

  def handle_event("action_farrow", _, socket) do
    today = socket.assigns.today

    cs =
      Breeding.change_farrowing(%Farrowing{
        farrowed_at: today,
        born_alive: 0,
        stillborn: 0,
        mummified: 0
      })

    {:noreply,
     assign(socket,
       sheet_mode: :farrow,
       farrow_form: to_form(cs, as: :farrowing),
       farrow_error: nil
     )}
  end

  def handle_event("validate_farrow", %{"farrowing" => params}, socket) do
    cs =
      Breeding.change_farrowing(%Farrowing{}, params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, farrow_form: to_form(cs, as: :farrowing), farrow_error: nil)}
  end

  def handle_event("save_farrow", %{"farrowing" => params}, socket) do
    if socket.assigns.can_record do
      service = socket.assigns.sheet_service

      case Breeding.record_farrowing(socket.assigns.current_scope, service, params) do
        {:ok, _farrowing} ->
          {:noreply,
           socket
           |> reset_sheet()
           |> load_rows()
           |> put_flash(:info, gettext("Farrowing recorded."))}

        {:error, :service_already_closed} ->
          {:noreply,
           socket
           |> reset_sheet()
           |> load_rows()
           |> put_flash(:error, gettext("Service is already closed."))}

        {:error, :sow_not_served} ->
          {:noreply,
           assign(socket,
             farrow_error: gettext("Sow status must be served to record farrowing.")
           )}

        {:error, :gestation_out_of_range} ->
          {:noreply,
           assign(socket,
             farrow_error:
               gettext("Farrowed date must be within 3 days of the 114-day gestation.")
           )}

        {:error, %Ecto.Changeset{} = cs} ->
          {:noreply, assign(socket, farrow_form: to_form(cs, as: :farrowing))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  # Close service

  def handle_event("action_close", _, socket) do
    today = socket.assigns.today
    service = socket.assigns.sheet_service

    cs =
      Service.close_changeset(service, %{"result" => "abortion", "result_at" => today})
      |> Map.put(:action, nil)

    {:noreply,
     assign(socket,
       sheet_mode: :close,
       close_form: to_form(cs, as: :service),
       close_error: nil
     )}
  end

  def handle_event("validate_close", %{"service" => params}, socket) do
    cs =
      Service.close_changeset(socket.assigns.sheet_service, params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, close_form: to_form(cs, as: :service), close_error: nil)}
  end

  def handle_event("save_close", %{"service" => params}, socket) do
    if socket.assigns.can_record do
      service = socket.assigns.sheet_service
      result = Map.get(params, "result")

      case Breeding.close_service(socket.assigns.current_scope, service, result, params) do
        {:ok, _} ->
          {:noreply,
           socket
           |> reset_sheet()
           |> load_rows()
           |> put_flash(:info, gettext("Service closed."))}

        {:error, :already_closed} ->
          {:noreply,
           socket
           |> reset_sheet()
           |> load_rows()
           |> put_flash(:error, gettext("Service is already closed."))}

        {:error, %Ecto.Changeset{} = cs} ->
          {:noreply, assign(socket, close_form: to_form(cs, as: :service))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("load_more", _, socket) do
    {:noreply, append_rows(socket)}
  end

  # ── Record service ──

  # Re-service from a gestating sow's action menu: closes the action
  # sheet and opens the service sheet with that sow's ear tag pre-resolved.
  # Saving auto-closes the open service with `result = re_service` (handled
  # in `Breeding.record_service/2`).
  def handle_event("action_re_service", _, socket) do
    if socket.assigns.can_record do
      today = socket.assigns.today
      sow_tag = socket.assigns.sheet_sow_tag

      {:noreply,
       socket
       |> reset_sheet_state()
       |> assign(
         sheet_mode: :re_service,
         service_sow_tag: "",
         service_sow_state: :empty,
         service_sow_status: nil,
         service_sow_id: nil,
         service_boar_items: PeggyWeb.Pickers.boar_items(socket.assigns.current_scope),
         service_boar_label: nil,
         service_boar_id: nil,
         service_type: "ai",
         service_served_at: to_string(today),
         service_pen_code: "",
         service_pen_state: :empty,
         service_pen_id: nil,
         service_semen: nil,
         service_error: nil
       )
       |> resolve_service_sow(sow_tag)}
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  # Movement

  def handle_event("action_move", _, socket) do
    if Policy.can?(socket.assigns.current_scope, :record_movement) do
      sow =
        Animals.get_animal!(
          socket.assigns.current_scope,
          socket.assigns.sheet_service.sow_id
        )

      {:noreply,
       socket
       |> assign(sheet_mode: :move)
       |> MovementForm.open(sow)}
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("move_validate", params, socket) do
    {:noreply, MovementForm.validate(socket, params)}
  end

  def handle_event("move_save", params, socket) do
    if Policy.can?(socket.assigns.current_scope, :record_movement) do
      service_id = socket.assigns.sheet_service && socket.assigns.sheet_service.id

      case MovementForm.save(socket, params) do
        {:ok, socket} ->
          {:noreply,
           socket
           |> reset_sheet()
           |> load_rows()
           |> put_flash(:info, gettext("Movement recorded."))
           |> push_event("flash-row", %{id: "service-#{service_id}"})}

        {:error, socket} ->
          {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("service_validate", params, socket) do
    socket
    |> assign(
      service_type: Map.get(params, "service_type", socket.assigns.service_type),
      service_served_at: Map.get(params, "served_at", socket.assigns.service_served_at),
      service_semen: Shared.presence(Map.get(params, "semen", socket.assigns.service_semen)),
      service_boar_id: blank_to_nil(params["boar_id"]),
      service_error: nil
    )
    |> resolve_service_sow(params["sow_tag"])
    |> resolve_service_pen(params["pen_code"])
    |> then(&{:noreply, &1})
  end

  def handle_event("service_save", params, socket) do
    if socket.assigns.can_record do
      socket =
        socket
        |> resolve_service_sow(params["sow_tag"])
        |> resolve_service_pen(params["pen_code"])

      boar_id = blank_to_nil(params["boar_id"])

      cond do
        socket.assigns.service_sow_state != :existing ->
          {:noreply,
           assign(socket,
             service_error: gettext("Pick a serviceable sow before saving.")
           )}

        socket.assigns.service_type == "natural" and is_nil(boar_id) ->
          {:noreply,
           assign(socket,
             service_error: gettext("Boar tag is required for natural service.")
           )}

        true ->
          attrs =
            %{
              "sow_id" => socket.assigns.service_sow_id,
              "service_type" => socket.assigns.service_type,
              "served_at" => params["served_at"]
            }
            |> maybe_put("boar_id", boar_id)
            |> maybe_put("pen_id", socket.assigns.service_pen_id)
            |> maybe_put("semen", Shared.presence(params["semen"]))

          case Breeding.record_service_with_backfill(socket.assigns.current_scope, attrs) do
            {:ok, %{service: service}} ->
              {:noreply,
               socket
               |> reset_sheet()
               |> load_rows()
               |> put_flash(:info, gettext("Service recorded."))
               |> push_event("flash-row", %{id: "service-#{service.id}"})}

            {:error, %Ecto.Changeset{} = cs} ->
              {:noreply, assign(socket, service_error: Shared.format_cs_error(cs))}

            {:error, reason} ->
              {:noreply, assign(socket, service_error: humanize(reason))}
          end
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp push_patch_filters(socket, overrides) do
    base = current_filter_query(socket)
    merged = Map.merge(base, overrides) |> prune_filter_query()
    slug = socket.assigns.current_scope.farm.slug

    path =
      case merged do
        m when map_size(m) == 0 -> ~p"/m/#{slug}/breeding/gestating"
        m -> ~p"/m/#{slug}/breeding/gestating?#{m}"
      end

    push_patch(socket, to: path)
  end

  defp current_filter_query(%{assigns: %{filters: f} = assigns}) do
    %{
      "q" => f.q,
      "window" => f.window,
      "service_type" => f.service_type,
      "pen_search" => f.pen_search,
      "min_parity" => f.min_parity,
      "max_parity" => f.max_parity,
      "sort" => sort_to_param(assigns.sort, assigns.dir) || ""
    }
  end

  defp prune_filter_query(q) do
    q
    |> Enum.reject(fn
      {_k, ""} -> true
      {_k, nil} -> true
      {"window", "all"} -> true
      {"service_type", "all"} -> true
      {"sort", "served-asc"} -> true
      _ -> false
    end)
    |> Map.new()
  end

  defp active_filter_count(assigns) do
    f = assigns.filters

    [
      f.window != "all",
      f.service_type != "all",
      f.pen_search != "",
      f.min_parity != "",
      f.max_parity != "",
      not (assigns.sort == "served" and assigns.dir == "asc")
    ]
    |> Enum.count(& &1)
  end

  defp load_rows(socket) do
    scope = socket.assigns.current_scope
    opts = list_opts(socket, 0)

    rows = Breeding.list_gestating_sows(scope, opts) |> attach_parity(scope)
    total = Breeding.count_gestating_sows(scope, opts)

    socket
    |> assign(total: total, page: 1, has_more: length(rows) < total)
    |> stream(:gestating, rows, reset: true)
  end

  defp append_rows(socket) do
    scope = socket.assigns.current_scope
    next_page = socket.assigns.page + 1
    opts = list_opts(socket, (next_page - 1) * @per_page)

    rows = Breeding.list_gestating_sows(scope, opts) |> attach_parity(scope)
    loaded = next_page * @per_page

    socket =
      Enum.reduce(rows, socket, fn row, acc -> stream_insert(acc, :gestating, row) end)

    assign(socket, page: next_page, has_more: loaded < socket.assigns.total)
  end

  defp list_opts(socket, offset) do
    f = socket.assigns.filters

    [
      search: f.q,
      due_window: f.window,
      service_type: f.service_type,
      pen_search: blank_to_nil(f.pen_search),
      min_parity: blank_to_nil(f.min_parity),
      max_parity: blank_to_nil(f.max_parity),
      sort: socket.assigns.sort,
      dir: socket.assigns.dir,
      limit: @per_page,
      offset: offset
    ]
  end

  defp attach_parity(rows, scope) do
    sow_ids = Enum.map(rows, & &1.service.sow_id)
    parities = Breeding.parities_for(scope, sow_ids)
    Enum.map(rows, &Map.put(&1, :parity, Map.get(parities, &1.service.sow_id, 0)))
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  defp reset_sheet(socket) do
    socket
    |> reset_sheet_state()
    |> assign(
      action_sheet_for: nil,
      sheet_mode: :menu,
      sheet_service: nil,
      sheet_sow_tag: nil
    )
  end

  defp reset_sheet_state(socket) do
    socket
    |> assign(
      farrow_form: nil,
      farrow_error: nil,
      close_form: nil,
      close_error: nil
    )
    |> reset_service()
    |> MovementForm.reset()
  end

  defp days_left(%{expected_farrow_date: efd}, today), do: Date.diff(efd, today)

  defp days_left_for(scope, service, today) do
    Date.diff(Date.add(service.served_at, Breeding.gestation_days(scope)), today)
  end

  defp expected_for(scope, service),
    do: Date.add(service.served_at, Breeding.gestation_days(scope))

  # Headline number is signed: positive = days remaining, negative = overdue.
  defp days_left_display(d) when d >= 0, do: "#{d}d"
  defp days_left_display(d), do: "#{d}d"

  defp days_left_label(d) when d <= 0, do: gettext("Overdue")
  defp days_left_label(d) when d <= 7, do: gettext("Due in")
  defp days_left_label(_), do: gettext("Due in")

  defp days_left_color(d) when d <= 0, do: "text-error"
  defp days_left_color(d) when d <= 7, do: "text-warning"
  defp days_left_color(d) when d <= 14, do: "text-info"
  defp days_left_color(_), do: "text-success"

  defp sow_pen_label(%{current_pen: %{code: code, house: %{code: hcode}}}),
    do: "#{hcode}-#{code}"

  defp sow_pen_label(%{current_pen: %{code: code}}), do: code
  defp sow_pen_label(_), do: "—"

  # ── Service sheet helpers ──

  @serviceable_statuses ~w(active open dry served)

  defp reset_service(socket) do
    assign(socket,
      service_sow_tag: "",
      service_sow_state: :empty,
      service_sow_status: nil,
      service_sow_id: nil,
      service_boar_items: [],
      service_boar_label: nil,
      service_boar_id: nil,
      service_type: "ai",
      service_served_at: to_string(socket.assigns.today),
      service_pen_code: "",
      service_pen_state: :empty,
      service_pen_id: nil,
      service_error: nil
    )
  end

  defp resolve_service_sow(socket, nil), do: resolve_service_sow(socket, "")

  defp resolve_service_sow(socket, tag) when is_binary(tag) do
    tag = String.trim(tag)

    cond do
      tag == "" ->
        assign(socket,
          service_sow_tag: "",
          service_sow_state: :empty,
          service_sow_status: nil,
          service_sow_id: nil
        )

      true ->
        case Animals.find_by_ear_tag(socket.assigns.current_scope, tag) do
          nil ->
            assign(socket,
              service_sow_tag: tag,
              service_sow_state: :not_found,
              service_sow_status: nil,
              service_sow_id: nil
            )

          %{status: status} = sow when status in @serviceable_statuses ->
            assign(socket,
              service_sow_tag: tag,
              service_sow_state: :existing,
              service_sow_status: status,
              service_sow_id: sow.id
            )

          %{status: status} ->
            assign(socket,
              service_sow_tag: tag,
              service_sow_state: :not_serviceable,
              service_sow_status: status,
              service_sow_id: nil
            )
        end
    end
  end

  defp resolve_service_pen(socket, nil), do: resolve_service_pen(socket, "")

  defp resolve_service_pen(socket, code) when is_binary(code) do
    code = String.trim(code)

    cond do
      code == "" ->
        assign(socket,
          service_pen_code: "",
          service_pen_state: :empty,
          service_pen_id: nil
        )

      true ->
        case Locations.find_pen_by_code(socket.assigns.current_scope, code) do
          nil ->
            assign(socket,
              service_pen_code: code,
              service_pen_state: :not_found,
              service_pen_id: nil
            )

          pen ->
            assign(socket,
              service_pen_code: code,
              service_pen_state: :resolved,
              service_pen_id: pen.id
            )
        end
    end
  end

  defp service_save_enabled?(%{
         service_sow_state: :existing,
         service_type: type,
         service_boar_id: bid
       }) do
    type != "natural" or not is_nil(bid)
  end

  defp service_save_enabled?(_), do: false

  defp gestating_pen_state_text(:resolved), do: "✓"
  defp gestating_pen_state_text(:not_found), do: "⚠ No active pen with that code"
  defp gestating_pen_state_text(_), do: "Optional — moves the sow to this pen"

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp humanize(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> String.replace("_", " ")

  defp humanize(reason), do: inspect(reason)
end
