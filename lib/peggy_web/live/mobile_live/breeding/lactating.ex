defmodule PeggyWeb.MobileLive.Breeding.Lactating do
  @moduledoc """
  Mobile-first Lactating tab.

  Designed for barn-floor use on a phone:
    - card-per-sow instead of a horizontally-scrolling table
    - large touch targets, glance-readable type
    - sticky search bar with collapsible filter drawer
    - bottom action sheet that swaps between menu and Death / Foster /
      Wean forms in place
  """
  use PeggyWeb, :live_view

  alias Peggy.{Animals, Breeding, FarmClock, Policy}
  alias Peggy.Breeding.LitterEvent
  alias PeggyWeb.FarmLive.Breeding.Shared
  alias PeggyWeb.MobileLive.Breeding.MovementForm
  alias PeggyWeb.Pickers

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

        <%!-- Tab switch (Gestating / Lactating) --%>
        <nav class="px-3 pt-2 flex gap-1 text-center">
          <.link
            navigate={~p"/m/#{@current_scope.farm.slug}/breeding/serviceable"}
            class="px-3 py-1 rounded border border-base-300 text-base-content/70"
          >
            {"💓 " <> gettext("Serviceable")}
          </.link>
          <.link
            navigate={~p"/m/#{@current_scope.farm.slug}/breeding/gestating"}
            class="px-3 py-1 rounded border border-base-300 text-base-content/70"
          >
            {"🤰 " <> gettext("Gestating")}
          </.link>
          <.link
            navigate={~p"/m/#{@current_scope.farm.slug}/breeding/lactating"}
            class="px-3 py-1 rounded-full bg-primary text-primary-content font-semibold"
          >
            {"🤱 " <> gettext("Lactating")}
          </.link>
        </nav>

        <p :if={@total > 0} class="px-4 pt-1 text-xs text-base-content/50">
          {gettext("%{n} results", n: @total)}
        </p>

        <%!-- Cards --%>
        <ul id="lactating-cards" phx-update="stream" class="px-3 py-2 space-y-1">
          <li
            :for={{dom_id, e} <- @streams.lactating}
            id={dom_id}
            phx-click="open_actions"
            phx-value-farrowing-id={e.farrowing.id}
            class="px-3 py-1 rounded-xl border border-base-300 bg-base-100 shadow-sm
                   active:bg-base-200 cursor-pointer touch-manipulation"
          >
            <div class="flex items-baseline justify-between gap-3">
              <span class="font-mono font-bold text-xl">
                {e.farrowing.sow.ear_tag}
                <.cull_flag animal={e.farrowing.sow} />
                <Shared.recently_updated_badge at={e.farrowing.updated_at} />
              </span>
              <span class="whitespace-nowrap">
                <span class="text-xl font-mono font-bold text-success">{e.surviving}</span>
                <span class="text-[10px] uppercase tracking-wide text-base-content/50 ml-1">
                  {gettext("Surviving")}
                </span>
              </span>
            </div>

            <div class="flex items-center gap-2 text-sm text-base-content/70">
              <.icon name="hero-map-pin-micro" class="size-4 text-blue-600" />
              <span class="font-mono">{pen_label(e.farrowing.pen)}</span>
              <span class="ml-auto text-base-content/50">
                {gettext("Farrowed")}
                <span class="font-semibold ml-1">{e.farrowing.farrowed_at}</span>
              </span>
            </div>

            <div class="flex items-end justify-between gap-3">
              <div class="text-sm space-y-0.5">
                <div class="text-base-content/50">
                  {gettext("Parity")}
                  <span class="font-mono font-bold text-info ml-1">{e.parity}</span>
                </div>
                <div class="text-base-content/50">
                  {gettext("Litter Age")}
                  <span class={[
                    "font-mono font-bold ml-1",
                    litter_age_color(@current_scope, Date.diff(@today, e.farrowing.farrowed_at))
                  ]}>
                    {Date.diff(@today, e.farrowing.farrowed_at)}d
                  </span>
                </div>
              </div>
              <dl class="text-right text-xs leading-snug grid grid-cols-[auto_auto] gap-x-2 items-baseline">
                <dt class="text-base-content/50">{gettext("Born alive")}</dt>
                <dd class="font-mono font-semibold text-success">{e.farrowing.born_alive}</dd>
                <dt class="text-base-content/50">{gettext("Stillborn")}</dt>
                <dd class={[
                  "font-mono font-semibold",
                  (e.farrowing.stillborn || 0) > 0 && "text-error",
                  (e.farrowing.stillborn || 0) == 0 && "text-base-content/40"
                ]}>
                  {e.farrowing.stillborn || 0}
                </dd>
                <dt class="text-base-content/50">{gettext("Mummified")}</dt>
                <dd class={[
                  "font-mono font-semibold",
                  (e.farrowing.mummified || 0) > 0 && "text-warning",
                  (e.farrowing.mummified || 0) == 0 && "text-base-content/40"
                ]}>
                  {e.farrowing.mummified || 0}
                </dd>
              </dl>
            </div>
          </li>
        </ul>

        <p :if={@total == 0} class="px-4 py-8 text-center text-sm text-base-content/60">
          {gettext("No lactating sows match the filters.")}
        </p>

        <.infinite_scroll
          has_more={@has_more}
          total={@total}
          id="lactating-mobile-sentinel"
        />

        <%!-- Action sheet --%>
        <div
          :if={@action_sheet_for}
          class="fixed inset-0 z-40 bg-black/40 flex items-end"
          phx-click="close_actions"
        >
          <div
            class="w-full bg-base-100 rounded-t-2xl pb-[env(safe-area-inset-bottom)] max-h-[90vh] overflow-y-auto"
            phx-click="ignore_click"
          >
            <div class="flex justify-center pt-2 pb-1">
              <div class="w-10 h-1 rounded-full bg-base-300"></div>
            </div>

            <%!-- Sheet header (always visible) --%>
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
                  :if={@sheet_farrowing}
                  navigate={~p"/m/#{@current_scope.farm.slug}/animals/#{@sheet_farrowing.sow_id}"}
                  class="font-mono font-bold text-lg text-primary underline underline-offset-2 decoration-dotted active:decoration-solid"
                >
                  {@sheet_sow_tag}
                </.link>
                <div
                  :if={is_nil(@sheet_farrowing)}
                  class="font-mono font-bold text-lg"
                >
                  {@sheet_sow_tag}
                </div>
                <div class="text-xs text-base-content/60">
                  {gettext("Surviving %{n}", n: @sheet_surviving)}
                </div>
              </div>
            </div>

            <%!-- Action menu --%>
            <div
              :if={@sheet_mode == :menu and @can_record}
              class="grid grid-cols-2 gap-px bg-base-200"
            >
              <button
                phx-click="action_wean"
                class="bg-base-100 py-5 flex flex-col items-center gap-1 active:bg-success/10"
              >
                <span class="text-2xl">👶</span>
                <span class="text-xs">{gettext("Wean")}</span>
              </button>
              <button
                phx-click="action_foster"
                class="bg-base-100 py-5 flex flex-col items-center gap-1 active:bg-info/10"
              >
                <span class="text-2xl">🤗</span>
                <span class="text-xs">{gettext("Foster")}</span>
              </button>
              <button
                phx-click="action_move"
                class="bg-base-100 py-5 flex flex-col items-center gap-1 active:bg-info/10"
              >
                <span class="text-2xl">🚚</span>
                <span class="text-xs">{gettext("Sow Move")}</span>
              </button>
              <button
                phx-click="action_death"
                class="bg-base-100 py-5 flex flex-col items-center gap-1 active:bg-error/10"
              >
                <span class="text-2xl">🪦</span>
                <span class="text-xs">{gettext("Litter Death")}</span>
              </button>
            </div>

            <p
              :if={@sheet_mode == :menu and not @can_record}
              class="px-4 py-6 text-center text-sm text-base-content/60"
            >
              {gettext("View-only — you don't have permission to record breeding.")}
            </p>

            <button
              :if={@sheet_mode == :menu}
              phx-click="show_ledger"
              class="w-full px-4 py-3 flex items-center justify-between text-sm
                     border-t border-base-200 active:bg-base-200"
            >
              <span class="flex items-center gap-2">
                <.icon name="hero-book-open" class="size-5 text-primary" />
                {gettext("View litter ledger")}
              </span>
              <.icon name="hero-chevron-right-micro" class="size-4 text-base-content/40" />
            </button>

            <%!-- Wean form --%>
            <.form
              :let={f}
              :if={@sheet_mode == :wean and @wean_form}
              for={@wean_form}
              phx-change="validate_wean"
              phx-submit="save_wean"
              class="px-4 py-3 space-y-4"
            >
              <label class="block">
                <span class="text-xs uppercase text-base-content/60">{gettext("Weaned at")}</span>
                <input
                  type="date"
                  name="weaning[weaned_at]"
                  value={Phoenix.HTML.Form.input_value(f, :weaned_at)}
                  class="input input-bordered input-lg w-full mt-1"
                />
              </label>

              <label class="block">
                <span class="text-xs uppercase text-base-content/60">
                  {gettext("Weaned count (max %{n})", n: @sheet_surviving)}
                </span>
                <input
                  type="number"
                  name="weaning[weaned_count]"
                  value={Phoenix.HTML.Form.input_value(f, :weaned_count)}
                  min="0"
                  max={@sheet_surviving}
                  inputmode="numeric"
                  class="input input-bordered input-lg w-full mt-1 text-2xl font-mono"
                />
              </label>

              <label class="block">
                <span class="text-xs uppercase text-base-content/60">
                  {gettext("Weaner batch id")}
                </span>
                <input
                  type="text"
                  name="weaning[batch_tag]"
                  value={Phoenix.HTML.Form.input_value(f, :batch_tag)}
                  placeholder="e.g. W20260504"
                  autocomplete="off"
                  class="input input-bordered input-lg w-full mt-1 font-mono"
                />
                <span class="text-xs text-base-content/60 mt-1 block">
                  {gettext("Reuse an existing id to pool; new id starts a fresh batch.")}
                </span>
              </label>

              <.autocomplete
                id={"mobile-wean-dest-pen-#{Phoenix.HTML.Form.input_value(f, :weaned_at)}"}
                label={gettext("Sow destination pen")}
                name="weaning[destination_pen_id]"
                value={Phoenix.HTML.Form.input_value(f, :destination_pen_id)}
                items={@pen_items}
                selected_label={@wean_dest_pen_label}
                placeholder="16B-101"
                drop_up
                touch
                empty_text={gettext("No active pen with that code")}
              />

              <p :if={@wean_error} class="text-sm text-error">{@wean_error}</p>

              <div class="grid grid-cols-2 gap-3 pt-2">
                <button
                  type="button"
                  phx-click="action_back"
                  class="btn btn-lg btn-ghost"
                >
                  {gettext("Cancel")}
                </button>
                <button
                  type="submit"
                  phx-disable-with={gettext("Saving…")}
                  class="btn btn-lg btn-primary"
                >
                  {gettext("Weaned")}
                </button>
              </div>
            </.form>

            <%!-- Death form --%>
            <.form
              :let={f}
              :if={@sheet_mode == :death and @death_form}
              for={@death_form}
              phx-change="validate_death"
              phx-submit="save_death"
              class="px-4 py-3 space-y-4"
            >
              <label class="block">
                <span class="text-xs uppercase text-base-content/60">{gettext("Occurred at")}</span>
                <input
                  type="date"
                  name="litter_event[occurred_at]"
                  value={Phoenix.HTML.Form.input_value(f, :occurred_at)}
                  class="input input-bordered input-lg w-full mt-1"
                />
              </label>

              <label class="block">
                <span class="text-xs uppercase text-base-content/60">
                  {gettext("Quantity (max %{n})", n: @sheet_surviving)}
                </span>
                <input
                  type="number"
                  name="litter_event[quantity]"
                  value={Phoenix.HTML.Form.input_value(f, :quantity)}
                  min="1"
                  max={@sheet_surviving}
                  inputmode="numeric"
                  class="input input-bordered input-lg w-full mt-1 text-2xl font-mono"
                />
              </label>

              <label class="block">
                <span class="text-xs uppercase text-base-content/60">
                  {gettext("Notes (optional)")}
                </span>
                <textarea
                  name="litter_event[notes]"
                  rows="2"
                  class="textarea textarea-bordered w-full mt-1"
                >{Phoenix.HTML.Form.input_value(f, :notes)}</textarea>
              </label>

              <p :if={@death_error} class="text-sm text-error">{@death_error}</p>

              <div class="grid grid-cols-2 gap-3 pt-2">
                <button type="button" phx-click="action_back" class="btn btn-lg btn-ghost">
                  {gettext("Cancel")}
                </button>
                <button
                  type="submit"
                  phx-disable-with={gettext("Saving…")}
                  class="btn btn-lg btn-error"
                >
                  {gettext("Rec. Death")}
                </button>
              </div>
            </.form>

            <%!-- Foster form --%>
            <.form
              :let={f}
              :if={@sheet_mode == :foster and @foster_form}
              for={@foster_form}
              phx-change="validate_foster"
              phx-submit="save_foster"
              class="px-4 py-3 space-y-4"
            >
              <label class="block">
                <span class="text-xs uppercase text-base-content/60">
                  {gettext("Foster onto sow (ear tag)")}
                </span>
                <input
                  type="text"
                  name="dest_tag"
                  value={@foster_dest_tag}
                  phx-debounce="300"
                  autocomplete="off"
                  spellcheck="false"
                  placeholder={gettext("e.g. 5184KR")}
                  class={[
                    "input input-bordered input-lg w-full mt-1 font-mono",
                    @foster_dest_state == :resolved && "border-success focus:border-success",
                    @foster_dest_state in [:not_found, :no_open_farrowing, :same_sow] &&
                      "border-error focus:border-error"
                  ]}
                />
                <span class={[
                  "text-xs mt-1 block",
                  @foster_dest_state == :resolved && "text-success",
                  @foster_dest_state in [:not_found, :no_open_farrowing, :same_sow] && "text-error",
                  @foster_dest_state == :empty && "text-base-content/50"
                ]}>
                  {foster_state_text(@foster_dest_state, @foster_dest_farrowing)}
                </span>
              </label>

              <label class="block">
                <span class="text-xs uppercase text-base-content/60">{gettext("Occurred at")}</span>
                <input
                  type="date"
                  name="litter_event[occurred_at]"
                  value={Phoenix.HTML.Form.input_value(f, :occurred_at)}
                  class="input input-bordered input-lg w-full mt-1"
                />
              </label>

              <label class="block">
                <span class="text-xs uppercase text-base-content/60">
                  {gettext("Quantity (max %{n})", n: @sheet_surviving)}
                </span>
                <input
                  type="number"
                  name="litter_event[quantity]"
                  value={Phoenix.HTML.Form.input_value(f, :quantity)}
                  min="1"
                  max={@sheet_surviving}
                  inputmode="numeric"
                  class="input input-bordered input-lg w-full mt-1 text-2xl font-mono"
                />
              </label>

              <input type="hidden" name="litter_event[kind]" value="foster_out" />

              <label class="block">
                <span class="text-xs uppercase text-base-content/60">
                  {gettext("Notes (optional)")}
                </span>
                <textarea
                  name="litter_event[notes]"
                  rows="2"
                  class="textarea textarea-bordered w-full mt-1"
                >{Phoenix.HTML.Form.input_value(f, :notes)}</textarea>
              </label>

              <p :if={@foster_error} class="text-sm text-error">{@foster_error}</p>

              <div class="grid grid-cols-2 gap-3 pt-2">
                <button type="button" phx-click="action_back" class="btn btn-lg btn-ghost">
                  {gettext("Cancel")}
                </button>
                <button
                  type="submit"
                  phx-disable-with={gettext("Saving…")}
                  disabled={@foster_dest_state != :resolved}
                  class="btn btn-lg btn-primary"
                >
                  {gettext("Rec. Foster")}
                </button>
              </div>
            </.form>

            <%!-- Litter ledger (read-only with delete) --%>
            <div :if={@sheet_mode == :ledger} class="px-4 py-3">
              <div class="text-xs text-base-content/60 mb-2">
                {gettext("Born alive %{n}", n: @sheet_farrowing && @sheet_farrowing.born_alive)}
              </div>

              <p
                :if={@ledger_events == []}
                class="py-6 text-center text-sm text-base-content/60"
              >
                {gettext("No litter events yet.")}
              </p>

              <ul :if={@ledger_events != []} class="space-y-2">
                <li
                  :for={ev <- @ledger_events}
                  class="rounded-lg border border-base-300 bg-base-100 p-3"
                >
                  <div class="flex items-baseline justify-between gap-2">
                    <span class="font-semibold">{humanize_kind(ev.kind)}</span>
                    <span class="font-mono text-lg leading-none">×{ev.quantity}</span>
                  </div>
                  <div class="mt-1 text-xs text-base-content/70 flex flex-wrap gap-x-3">
                    <span>{ev.occurred_at}</span>
                    <span :if={ev.counterpart_tag} class="font-mono">
                      ↔ {ev.counterpart_tag}
                    </span>
                  </div>
                  <p :if={ev.notes && ev.notes != ""} class="mt-2 text-xs text-base-content/60">
                    {ev.notes}
                  </p>
                  <div :if={@can_record} class="mt-2 flex justify-end">
                    <button
                      phx-click="delete_litter_event"
                      phx-value-event-id={ev.id}
                      data-confirm={
                        gettext(
                          "Delete this litter event? Paired fostering events are removed together."
                        )
                      }
                      class="btn btn-ghost btn-sm text-error"
                    >
                      <.icon name="hero-trash" class="size-4" />
                      {gettext("Delete")}
                    </button>
                  </div>
                </li>
              </ul>
            </div>

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
            <form
              phx-change="filter"
              phx-submit="filter"
              class="p-4 space-y-4 flex-1"
            >
              <label class="block">
                <span class="text-xs uppercase text-base-content/60">
                  {gettext("Litter age")}
                </span>
                <select name="age" class="select select-bordered select-lg w-full mt-1">
                  <option value="all" selected={@filters.age == "all"}>{gettext("All")}</option>
                  <option value="week1" selected={@filters.age == "week1"}>
                    {gettext("Week 1")}
                  </option>
                  <option value="week2" selected={@filters.age == "week2"}>
                    {gettext("Week 2")}
                  </option>
                  <option value="week3" selected={@filters.age == "week3"}>
                    {gettext("Week 3")}
                  </option>
                  <option value="wean_due" selected={@filters.age == "wean_due"}>
                    {gettext("Wean due")}
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
                  <span class="text-xs uppercase text-base-content/60">
                    {gettext("Min parity")}
                  </span>
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
                  <span class="text-xs uppercase text-base-content/60">
                    {gettext("Max parity")}
                  </span>
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
              <button
                phx-click="reset_filters"
                class="btn btn-ghost w-full"
              >
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
       sheet_farrowing: nil,
       sheet_sow_tag: nil,
       sheet_surviving: nil,
       pen_items: Pickers.pen_items(scope),
       pens_by_id: pens_by_id(scope),
       wean_form: nil,
       wean_error: nil,
       wean_dest_pen_label: nil,
       death_form: nil,
       death_error: nil,
       foster_form: nil,
       foster_dest_tag: "",
       foster_dest_state: :empty,
       foster_dest_farrowing: nil,
       foster_error: nil,
       ledger_events: [],
       sort: "farrowed",
       dir: "asc"
     )
     |> assign(MovementForm.init())
     |> stream_configure(:lactating, dom_id: &"farrowing-#{&1.farrowing.id}")
     |> stream(:lactating, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = %{
      q: params["q"] || "",
      age: Shared.param_age(params["age"]),
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
  # form binding; falls back to (farrowed, asc) on anything unknown.
  @sort_options ~w(farrowed-asc farrowed-desc tag-asc tag-desc parity-asc parity-desc pen-asc)

  defp parse_sort_param(s) when is_binary(s) do
    if s in @sort_options do
      [field, dir] = String.split(s, "-", parts: 2)
      {field, dir}
    else
      {"farrowed", "asc"}
    end
  end

  defp parse_sort_param(_), do: {"farrowed", "asc"}

  defp sort_to_param("farrowed", "asc"), do: nil
  defp sort_to_param(field, dir), do: "#{field}-#{dir}"

  defp sort_options do
    [
      {"farrowed-asc", gettext("Oldest litter first")},
      {"farrowed-desc", gettext("Newest litter first")},
      {"tag-asc", gettext("Tag A→Z")},
      {"tag-desc", gettext("Tag Z→A")},
      {"parity-asc", gettext("Parity (low to high)")},
      {"parity-desc", gettext("Parity (high to low)")},
      {"pen-asc", gettext("Pen")}
    ]
  end

  # ── Events ─────────────────────────────────────────────────────────

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, push_patch_filters(socket, %{"q" => q})}
  end

  def handle_event("clear_search", _params, socket),
    do: {:noreply, push_patch_filters(socket, %{"q" => ""})}

  def handle_event("filter", params, socket) do
    {:noreply,
     push_patch_filters(socket, %{
       "age" => params["age"] || "all",
       "pen_search" => params["pen_search"] || "",
       "min_parity" => params["min_parity"] || "",
       "max_parity" => params["max_parity"] || "",
       "sort" => params["sort"] || ""
     })}
  end

  def handle_event("reset_filters", _, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/m/#{socket.assigns.current_scope.farm.slug}/breeding/lactating"
     )}
  end

  def handle_event("open_filters", _, socket),
    do: {:noreply, assign(socket, :filter_drawer_open, true)}

  def handle_event("close_filters", _, socket),
    do: {:noreply, assign(socket, :filter_drawer_open, false)}

  def handle_event("ignore_click", _, socket), do: {:noreply, socket}

  def handle_event("open_actions", %{"farrowing-id" => id}, socket) do
    scope = socket.assigns.current_scope
    farrowing = Breeding.get_farrowing!(scope, String.to_integer(id))
    surviving = Breeding.surviving_piglet_count(farrowing)

    {:noreply,
     socket
     |> reset_sheet_state()
     |> assign(
       action_sheet_for: farrowing.id,
       sheet_mode: :menu,
       sheet_farrowing: farrowing,
       sheet_sow_tag: farrowing.sow.ear_tag,
       sheet_surviving: surviving
     )}
  end

  def handle_event("close_actions", _, socket), do: {:noreply, reset_sheet(socket)}

  def handle_event("action_back", _, socket) do
    {:noreply,
     socket
     |> reset_sheet_state()
     |> assign(sheet_mode: :menu)}
  end

  def handle_event("action_wean", _, socket) do
    today = socket.assigns.today
    surviving = socket.assigns.sheet_surviving

    {:noreply,
     assign(socket,
       sheet_mode: :wean,
       wean_form: weaning_form(today, weaned_count: surviving),
       wean_error: nil,
       wean_dest_pen_label: nil
     )}
  end

  # Movement

  def handle_event("action_move", _, socket) do
    if Policy.can?(socket.assigns.current_scope, :record_movement) do
      sow =
        Animals.get_animal!(
          socket.assigns.current_scope,
          socket.assigns.sheet_farrowing.sow_id
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
      farrowing_id = socket.assigns.sheet_farrowing && socket.assigns.sheet_farrowing.id

      case MovementForm.save(socket, params) do
        {:ok, socket} ->
          {:noreply,
           socket
           |> reset_sheet()
           |> load_rows()
           |> put_flash(:info, gettext("Movement recorded."))
           |> push_event("flash-row", %{id: "farrowing-#{farrowing_id}"})}

        {:error, socket} ->
          {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("validate_wean", %{"weaning" => params}, socket) do
    params = refresh_weaning_batch_tag(socket.assigns.wean_form, params)

    {:noreply,
     assign(socket,
       wean_form: weaning_form(params["weaned_at"], Map.drop(params, ["weaned_at"])),
       wean_dest_pen_label: pen_label(socket.assigns.pens_by_id, params["destination_pen_id"]),
       wean_error: nil
     )}
  end

  def handle_event("save_wean", %{"weaning" => params}, socket) do
    if socket.assigns.can_record do
      farrowing = socket.assigns.sheet_farrowing
      params = refresh_weaning_batch_tag(socket.assigns.wean_form, params)

      case Breeding.record_weaning(socket.assigns.current_scope, farrowing, params) do
        {:ok, _weaning, _batch} ->
          {:noreply,
           socket
           |> reset_sheet()
           |> load_rows()
           |> put_flash(:info, gettext("Weaning recorded."))}

        {:error, :already_weaned} ->
          {:noreply,
           socket
           |> reset_sheet()
           |> load_rows()
           |> put_flash(:error, gettext("Already weaned."))}

        {:error, :batch_tag_required} ->
          {:noreply,
           assign(socket,
             wean_error:
               gettext("Enter a weaner batch id to pool into (or a new id for a fresh batch).")
           )}

        {:error, %Ecto.Changeset{} = cs} ->
          {:noreply, assign(socket, wean_form: to_form(cs, as: :weaning))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  # ── Death ──

  def handle_event("action_death", _, socket) do
    today = socket.assigns.today

    cs =
      LitterEvent.changeset(%LitterEvent{}, %{
        "kind" => "death",
        "occurred_at" => today,
        "quantity" => 1
      })
      |> Map.put(:action, nil)

    {:noreply,
     assign(socket,
       sheet_mode: :death,
       death_form: to_form(cs, as: :litter_event),
       death_error: nil
     )}
  end

  def handle_event("validate_death", %{"litter_event" => params}, socket) do
    cs =
      LitterEvent.changeset(%LitterEvent{}, params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, death_form: to_form(cs, as: :litter_event), death_error: nil)}
  end

  def handle_event("save_death", %{"litter_event" => params}, socket) do
    if socket.assigns.can_record do
      farrowing = socket.assigns.sheet_farrowing

      case Breeding.record_pre_wean_death(socket.assigns.current_scope, farrowing, params) do
        {:ok, _event} ->
          {:noreply,
           socket
           |> reset_sheet()
           |> load_rows()
           |> put_flash(:info, gettext("Pre-wean death recorded."))
           |> push_event("flash-row", %{id: "farrowing-#{farrowing.id}"})}

        {:error, :invalid_quantity} ->
          {:noreply, assign(socket, death_error: gettext("Quantity must be at least 1."))}

        {:error, :insufficient_surviving} ->
          {:noreply, assign(socket, death_error: gettext("Quantity exceeds surviving piglets."))}

        {:error, %Ecto.Changeset{} = cs} ->
          {:noreply, assign(socket, death_form: to_form(cs, as: :litter_event))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  # ── Foster ──

  def handle_event("action_foster", _, socket) do
    today = socket.assigns.today

    cs =
      LitterEvent.changeset(%LitterEvent{}, %{
        "kind" => "foster_out",
        "occurred_at" => today,
        "quantity" => 1
      })
      |> Map.put(:action, nil)

    {:noreply,
     assign(socket,
       sheet_mode: :foster,
       foster_form: to_form(cs, as: :litter_event),
       foster_dest_tag: "",
       foster_dest_state: :empty,
       foster_dest_farrowing: nil,
       foster_error: nil
     )}
  end

  def handle_event("validate_foster", %{"litter_event" => params} = all, socket) do
    cs =
      LitterEvent.changeset(%LitterEvent{}, params)
      |> Map.put(:action, :validate)

    socket =
      assign(socket, foster_form: to_form(cs, as: :litter_event), foster_error: nil)

    dest_tag = (all["dest_tag"] || "") |> String.trim()
    {:noreply, resolve_foster_dest(socket, dest_tag)}
  end

  def handle_event("save_foster", %{"litter_event" => params}, socket) do
    if socket.assigns.can_record do
      source = socket.assigns.sheet_farrowing
      dest = socket.assigns.foster_dest_farrowing

      cond do
        is_nil(dest) ->
          {:noreply,
           assign(socket,
             foster_error: gettext("Pick a destination sow before saving.")
           )}

        true ->
          case Breeding.record_fostering(socket.assigns.current_scope, source, dest, params) do
            {:ok, _pair} ->
              {:noreply,
               socket
               |> reset_sheet()
               |> load_rows()
               |> put_flash(:info, gettext("Fostering recorded."))
               |> push_event("flash-row", %{id: "farrowing-#{source.id}"})}

            {:error, :same_farrowing} ->
              {:noreply,
               assign(socket,
                 foster_error: gettext("Source and destination must differ.")
               )}

            {:error, :invalid_quantity} ->
              {:noreply, assign(socket, foster_error: gettext("Quantity must be at least 1."))}

            {:error, :insufficient_surviving} ->
              {:noreply,
               assign(socket, foster_error: gettext("Quantity exceeds surviving piglets."))}

            {:error, {_step, %Ecto.Changeset{} = cs}} ->
              {:noreply, assign(socket, foster_form: to_form(cs, as: :litter_event))}
          end
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  # ── Ledger ──

  def handle_event("show_ledger", _, socket) do
    farrowing = socket.assigns.sheet_farrowing
    events = load_ledger_events(socket.assigns.current_scope, farrowing)

    {:noreply,
     socket
     |> reset_sheet_state()
     |> assign(sheet_mode: :ledger, ledger_events: events)}
  end

  def handle_event("delete_litter_event", %{"event-id" => id}, socket) do
    if socket.assigns.can_record do
      scope = socket.assigns.current_scope
      event = Peggy.Repo.get!(LitterEvent, String.to_integer(id))

      case Breeding.delete_litter_event(scope, event) do
        {:ok, :deleted} ->
          farrowing = socket.assigns.sheet_farrowing
          events = load_ledger_events(scope, farrowing)
          surviving = Breeding.surviving_piglet_count(farrowing)

          {:noreply,
           socket
           |> assign(ledger_events: events, sheet_surviving: surviving)
           |> load_rows()
           |> put_flash(:info, gettext("Litter event deleted."))}

        {:error, :weaning_closed} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("Weaning already recorded; cannot amend litter events.")
           )}

        {:error, :insufficient_surviving} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("Cannot remove: destination litter would go below zero.")
           )}

        {:error, :counterpart_missing} ->
          {:noreply, put_flash(socket, :error, gettext("Paired fostering event not found."))}

        {:error, :already_deleted} ->
          {:noreply, put_flash(socket, :error, gettext("Already deleted."))}

        {:error, :not_found} ->
          {:noreply, put_flash(socket, :error, gettext("Event not found."))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("load_more", _, socket) do
    {:noreply, append_rows(socket)}
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp push_patch_filters(socket, overrides) do
    base = current_filter_query(socket)
    merged = Map.merge(base, overrides) |> prune_filter_query()
    slug = socket.assigns.current_scope.farm.slug

    path =
      case merged do
        m when map_size(m) == 0 -> ~p"/m/#{slug}/breeding/lactating"
        m -> ~p"/m/#{slug}/breeding/lactating?#{m}"
      end

    push_patch(socket, to: path)
  end

  defp current_filter_query(%{assigns: %{filters: f} = assigns}) do
    %{
      "q" => f.q,
      "age" => f.age,
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
      {"age", "all"} -> true
      {"sort", "farrowed-asc"} -> true
      _ -> false
    end)
    |> Map.new()
  end

  defp active_filter_count(assigns) do
    f = assigns.filters

    [
      f.age != "all" and f.age != "" and not is_nil(f.age),
      f.pen_search != "",
      f.min_parity != "",
      f.max_parity != "",
      not (assigns.sort == "farrowed" and assigns.dir == "asc")
    ]
    |> Enum.count(& &1)
  end

  defp load_rows(socket) do
    scope = socket.assigns.current_scope
    opts = list_opts(socket, 0)

    rows =
      Breeding.list_lactating_sows(scope, opts)
      |> Enum.map(fn far ->
        %{farrowing: far, surviving: Breeding.surviving_piglet_count(far)}
      end)
      |> attach_parity(scope)

    total = Breeding.count_lactating_sows(scope, opts)

    socket
    |> assign(total: total, page: 1, has_more: length(rows) < total)
    |> stream(:lactating, rows, reset: true)
  end

  defp append_rows(socket) do
    scope = socket.assigns.current_scope
    next_page = socket.assigns.page + 1
    opts = list_opts(socket, (next_page - 1) * @per_page)

    rows =
      Breeding.list_lactating_sows(scope, opts)
      |> Enum.map(fn far ->
        %{farrowing: far, surviving: Breeding.surviving_piglet_count(far)}
      end)
      |> attach_parity(scope)

    loaded = next_page * @per_page

    socket =
      Enum.reduce(rows, socket, fn row, acc -> stream_insert(acc, :lactating, row) end)

    assign(socket, page: next_page, has_more: loaded < socket.assigns.total)
  end

  defp list_opts(socket, offset) do
    f = socket.assigns.filters

    [
      search: f.q,
      age_bucket: f.age,
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
    sow_ids = Enum.map(rows, & &1.farrowing.sow_id)
    parities = Breeding.parities_for(scope, sow_ids)
    Enum.map(rows, &Map.put(&1, :parity, Map.get(parities, &1.farrowing.sow_id, 0)))
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  # Closes the sheet entirely.
  defp reset_sheet(socket) do
    socket
    |> reset_sheet_state()
    |> assign(
      action_sheet_for: nil,
      sheet_mode: :menu,
      sheet_farrowing: nil,
      sheet_sow_tag: nil,
      sheet_surviving: nil
    )
  end

  defp weaning_form(weaned_at, fields) do
    params =
      fields
      |> Enum.map(fn
        {k, v} when is_atom(k) -> {Atom.to_string(k), v}
        {k, v} -> {k, v}
      end)
      |> Map.new()
      |> Map.put("weaned_at", weaned_at)
      |> Map.put_new("batch_tag", Breeding.default_wean_batch_tag(weaned_at))
      |> Map.put_new("destination_pen_id", "")

    to_form(params, as: :weaning)
  end

  defp pens_by_id(scope) do
    scope
    |> Pickers.pen_items()
    |> Map.new(fn %{id: id, label: label} -> {to_string(id), label} end)
  end

  defp pen_label(_pens_by_id, nil), do: nil
  defp pen_label(_pens_by_id, ""), do: nil

  defp pen_label(pens_by_id, id) do
    Map.get(pens_by_id, to_string(id))
  end

  defp refresh_weaning_batch_tag(form, params) do
    Map.put(
      params,
      "batch_tag",
      Breeding.refresh_auto_batch_tag(
        params["batch_tag"] || Phoenix.HTML.Form.input_value(form, :batch_tag),
        Phoenix.HTML.Form.input_value(form, :weaned_at),
        params["weaned_at"]
      )
    )
  end

  # Clears form state without closing the sheet — used when switching
  # between :menu / :wean / :death / :foster modes.
  defp reset_sheet_state(socket) do
    socket
    |> assign(
      wean_form: nil,
      wean_error: nil,
      wean_dest_pen_label: nil,
      death_form: nil,
      death_error: nil,
      foster_form: nil,
      foster_dest_tag: "",
      foster_dest_state: :empty,
      foster_dest_farrowing: nil,
      foster_error: nil,
      ledger_events: []
    )
    |> MovementForm.reset()
  end

  # Look up the destination sow for a fostering event by ear tag,
  # then find its open (un-weaned) farrowing. Drives a state badge in
  # the form so the operator gets feedback before submit.
  defp resolve_foster_dest(socket, "" = _tag) do
    assign(socket,
      foster_dest_tag: "",
      foster_dest_state: :empty,
      foster_dest_farrowing: nil
    )
  end

  defp resolve_foster_dest(socket, tag) do
    scope = socket.assigns.current_scope
    source = socket.assigns.sheet_farrowing

    case Animals.find_by_ear_tag(scope, tag) do
      nil ->
        assign(socket,
          foster_dest_tag: tag,
          foster_dest_state: :not_found,
          foster_dest_farrowing: nil
        )

      sow ->
        case Breeding.latest_open_farrowing_for_sow(scope, sow.id) do
          nil ->
            assign(socket,
              foster_dest_tag: tag,
              foster_dest_state: :no_open_farrowing,
              foster_dest_farrowing: nil
            )

          %{id: id} when id == source.id ->
            assign(socket,
              foster_dest_tag: tag,
              foster_dest_state: :same_sow,
              foster_dest_farrowing: nil
            )

          farrowing ->
            assign(socket,
              foster_dest_tag: tag,
              foster_dest_state: :resolved,
              foster_dest_farrowing: farrowing
            )
        end
    end
  end

  defp pen_label(%{code: code, house: %{code: hcode}}), do: "#{hcode}-#{code}"
  defp pen_label(%{code: code}), do: code
  defp pen_label(_), do: "—"

  # Days under the farm's `wean_due_days` are normal; the window
  # between wean-due and +4 days is amber; further is overdue.
  defp litter_age_color(scope, days) do
    wean_due = Breeding.wean_due_days(scope)

    cond do
      days >= wean_due + 4 -> "text-error"
      days >= wean_due -> "text-warning"
      true -> "text-success"
    end
  end

  defp load_ledger_events(scope, farrowing) do
    events = Breeding.list_litter_events(scope, farrowing)

    counterpart_ids =
      events
      |> Enum.map(& &1.counterpart_farrowing_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    tag_map =
      case counterpart_ids do
        [] ->
          %{}

        ids ->
          Breeding.list_farrowings_by_ids(scope, ids)
          |> Map.new(fn f -> {f.id, f.sow && f.sow.ear_tag} end)
      end

    Enum.map(events, fn ev ->
      Map.put(ev, :counterpart_tag, Map.get(tag_map, ev.counterpart_farrowing_id))
    end)
  end

  defp humanize_kind("death"), do: gettext("Death")
  defp humanize_kind("foster_in"), do: gettext("Foster in")
  defp humanize_kind("foster_out"), do: gettext("Foster out")
  defp humanize_kind(other), do: other

  defp foster_state_text(:resolved, %{sow: %{ear_tag: tag}, born_alive: ba}),
    do: "✓ #{tag} · born alive #{ba}"

  defp foster_state_text(:resolved, _), do: "✓"
  defp foster_state_text(:not_found, _), do: "⚠ No sow with that tag"
  defp foster_state_text(:no_open_farrowing, _), do: "⚠ Sow has no open farrowing"
  defp foster_state_text(:same_sow, _), do: "⚠ Same sow as source — pick a different one"
  defp foster_state_text(_, _), do: "Type the destination sow's ear tag"
end
