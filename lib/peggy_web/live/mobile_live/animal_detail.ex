defmodule PeggyWeb.MobileLive.AnimalDetail do
  @moduledoc """
  Mobile animal detail. Identity card, recent history, and bottom-
  sheet forms for **edit**, **record movement**, and **promote stage**
  (batches only). The latest history event can be **undone** inline,
  mirroring the desktop detail.
  """
  use PeggyWeb, :live_view

  alias Peggy.{AnimalActivity, Animals, Breeding, FarmClock, Locations, Policy}
  alias Peggy.Animals.{Animal, Movement}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_app flash={@flash} current_scope={@current_scope} active={:animals}>
      <div>
        <%!-- Sticky identity + actions bar (compact 2-row) --%>
        <header class="sticky top-0 z-10 bg-base-100 border-b border-base-200 px-3 py-2 space-y-1">
          <div class="flex items-center gap-2">
            <button
              id="mobile-animal-detail-back"
              phx-hook=".HistoryBack"
              type="button"
              data-fallback-href={~p"/m/#{@current_scope.farm.slug}/animals"}
              class="btn btn-ghost btn-square btn-lg shrink-0"
              aria-label={gettext("Back")}
            >
              <.icon name="hero-chevron-left" class="size-6" />
            </button>
            <script :type={Phoenix.LiveView.ColocatedHook} name=".HistoryBack">
              export default {
                mounted() {
                  this.handler = () => {
                    if (window.history.length > 1) {
                      window.history.back()
                    } else if (this.el.dataset.fallbackHref) {
                      window.location.href = this.el.dataset.fallbackHref
                    }
                  }
                  this.el.addEventListener("click", this.handler)
                },
                destroyed() {
                  this.el.removeEventListener("click", this.handler)
                }
              }
            </script>
            <span class="text-2xl font-mono font-bold truncate min-w-0">
              {@animal.ear_tag || "##{@animal.id}"}
            </span>
            <.cull_flag animal={@animal} />
            <.status_badge status={@animal.status} class="badge-sm shrink-0" />
            <span :if={@animal.needs_review} title={gettext("Needs review")} class="shrink-0">
              <.icon name="hero-exclamation-triangle-micro" class="size-4 text-warning" />
            </span>
          </div>

          <%!-- Compact details (left) + actions (right) --%>
          <div class="flex items-center gap-1">
            <div class="pl-1 text-sm text-base-content/70 flex flex-wrap items-center gap-x-1 min-w-0">
              <span>{String.capitalize(@animal.stage)}</span>
              <span :if={@animal.tracking_type == "batch"}>· ×{@animal.quantity}</span>
              <span :if={@animal.breed}>· {@animal.breed}</span>
              <span :if={pen_label(@animal)}>
                · <span class="font-mono">{pen_label(@animal)}</span>
              </span>
              <span :if={@animal.stage == "sow"}>
                · {gettext("Parity")}
                <span class="font-semibold text-info">{@parity}</span>
                <span :if={(@animal.legacy_parity || 0) > 0} class="text-xs text-base-content/50">
                  ({@animal.legacy_parity} {gettext("legacy")})
                </span>
              </span>
            </div>
            <div class="flex-1"></div>
            <button
              :if={@can_move and Animal.present_status?(@animal.status)}
              type="button"
              phx-click="move_open"
              class="btn btn-ghost btn-square btn-lg shrink-0"
              aria-label={gettext("Record movement")}
            >
              <.icon name="hero-truck" class="size-6 text-info" />
            </button>
            <button
              :if={
                @can_manage and @animal.tracking_type == "individual" and
                  Animal.present_status?(@animal.status) and not @animal.marked_cull
              }
              type="button"
              phx-click="mark_for_cull"
              data-confirm={
                gettext("Flag this animal for culling? Its status and records are unaffected.")
              }
              class="btn btn-ghost btn-square btn-lg shrink-0"
              aria-label={gettext("Mark for cull")}
            >
              <.icon name="hero-flag" class="size-6 text-warning" />
            </button>
            <button
              :if={@can_manage and @animal.tracking_type == "individual" and @animal.marked_cull}
              type="button"
              phx-click="unmark_cull"
              class="btn btn-ghost btn-square btn-lg shrink-0"
              aria-label={gettext("Unmark cull")}
            >
              <.icon name="hero-flag-solid" class="size-6 text-warning" />
            </button>
            <button
              :if={
                @can_manage and @animal.tracking_type == "batch" and
                  Animal.present_status?(@animal.status) and promote_targets(@animal) != []
              }
              type="button"
              phx-click="promote_open"
              class="btn btn-ghost btn-square btn-lg shrink-0"
              aria-label={gettext("Promote stage")}
            >
              <.icon name="hero-academic-cap" class="size-6 text-success" />
            </button>
            <button
              :if={@can_manage and Animal.present_status?(@animal.status)}
              type="button"
              phx-click="edit_open"
              class="btn btn-ghost btn-square btn-lg shrink-0"
              aria-label={gettext("Edit")}
            >
              <.icon name="hero-pencil-square" class="size-6 text-primary" />
            </button>
          </div>
        </header>

        <section class="px-3 py-3 space-y-3">
          <%!-- Secondary details (scroll under the sticky bar) --%>
          <div
            :if={@animal.dob || @animal.rfid || @animal.sire || @animal.dam}
            class="rounded-xl border border-base-300 bg-base-100 p-4"
          >
            <dl class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-sm">
              <dt :if={@animal.dob} class="text-base-content/50">{gettext("DOB")}</dt>
              <dd :if={@animal.dob} class="font-mono">
                {@animal.dob} <span class="text-base-content/50">({age_days(@animal, @today)}d)</span>
              </dd>

              <dt :if={@animal.rfid} class="text-base-content/50">{gettext("RFID")}</dt>
              <dd :if={@animal.rfid} class="font-mono break-all">{@animal.rfid}</dd>

              <dt :if={@animal.sire} class="text-base-content/50">{gettext("Sire")}</dt>
              <dd :if={@animal.sire}>
                <.link
                  navigate={~p"/m/#{@current_scope.farm.slug}/animals/#{@animal.sire.id}"}
                  class="font-mono text-primary underline underline-offset-2 decoration-dotted"
                >
                  {@animal.sire.ear_tag}
                </.link>
              </dd>

              <dt :if={@animal.dam} class="text-base-content/50">{gettext("Dam")}</dt>
              <dd :if={@animal.dam}>
                <.link
                  navigate={~p"/m/#{@current_scope.farm.slug}/animals/#{@animal.dam.id}"}
                  class="font-mono text-primary underline underline-offset-2 decoration-dotted"
                >
                  {@animal.dam.ear_tag}
                </.link>
              </dd>
            </dl>
          </div>

          <%!-- Needs-review banner --%>
          <div
            :if={@animal.needs_review}
            class="rounded-xl border border-warning/40 bg-warning/10 p-3 flex items-start gap-2 text-sm"
          >
            <.icon name="hero-exclamation-triangle-micro" class="size-5 text-warning mt-0.5" />
            <div class="flex-1">
              <p class="font-medium">{gettext("This record needs review.")}</p>
              <p class="text-base-content/70 text-xs mt-0.5">
                {gettext("Verify the details, then confirm.")}
              </p>
              <button
                :if={@can_manage}
                type="button"
                phx-click="mark_reviewed"
                class="btn btn-sm btn-warning mt-2"
              >
                <.icon name="hero-check-circle" class="size-4" />
                {gettext("Mark reviewed")}
              </button>
            </div>
          </div>

          <%!-- Notes --%>
          <div
            :if={@animal.notes && @animal.notes != ""}
            class="rounded-xl border border-base-300 bg-base-100 p-3 text-sm"
          >
            <div class="text-xs uppercase tracking-wide text-base-content/50 mb-1">
              {gettext("Notes")}
            </div>
            <p class="whitespace-pre-line">{@animal.notes}</p>
          </div>

          <%!-- Placements (batch only) --%>
          <div
            :if={@animal.tracking_type == "batch" and @placements != []}
            class="rounded-xl border border-base-300 bg-base-100 p-3 text-sm"
          >
            <div class="text-xs uppercase tracking-wide text-base-content/50 mb-1">
              {gettext("Placements")}
            </div>
            <ul class="space-y-1">
              <li :for={p <- @placements} class="flex items-center justify-between font-mono">
                <span>{p.pen.house.code}-{p.pen.code}</span>
                <span class="text-base-content/70">×{p.quantity}</span>
              </li>
            </ul>
          </div>

          <%!-- Offspring (sows) --%>
          <div
            :if={@animal.stage == "sow" and @offspring != []}
            class="rounded-xl border border-base-300 bg-base-100 px-2 pt-1 text-sm"
          >
            <div class="text-xs uppercase tracking-wide text-base-content/50 mb-1">
              {gettext("Offspring")} ({length(@offspring)})
            </div>
            <ul class="divide-y divide-base-200">
              <li
                :for={kid <- Enum.take(@offspring, 8)}
                class="flex items-center justify-between py-1"
              >
                <.link
                  navigate={~p"/m/#{@current_scope.farm.slug}/animals/#{kid.id}"}
                  class="font-mono text-primary"
                >
                  {kid.ear_tag || "##{kid.id}"}
                </.link>
                <span class="text-xs text-base-content/60">
                  {String.capitalize(kid.stage)}
                </span>
              </li>
              <li :if={length(@offspring) > 8} class="py-1 text-xs text-base-content/50">
                {gettext("+%{n} more on desktop", n: length(@offspring) - 8)}
              </li>
            </ul>
          </div>
        </section>

        <%!-- History timeline --%>
        <section class="px-3 pb-3">
          <h2 class="text-xs uppercase tracking-wide text-base-content/50 px-1 mb-2">
            {gettext("Recent activity")}
          </h2>
          <ul :if={@history != []} class="space-y-2">
            <li
              :for={row <- Enum.take(@history, 20)}
              class="rounded-xl border border-base-300 bg-base-100 px-2 py-2 text-sm"
            >
              <div class="flex items-baseline justify-between gap-2">
                <span class={[
                  "text-xs uppercase font-semibold",
                  history_kind_color(row.kind)
                ]}>
                  {history_kind_label(row.kind)}
                </span>
                <span class="font-mono text-xs text-base-content/60">{row.date}</span>
              </div>
              <div class="flex items-baseline justify-between gap-1">
                <p class="mt-1 text-sm leading-snug">
                  {history_summary(row, @current_scope)}
                </p>
                <button
                  :if={@can_move and history_undoable?(row, @latest_event)}
                  type="button"
                  phx-click="undo_last_event"
                  class="btn btn-sm btn-ghost text-error"
                  data-confirm={undo_confirm_text(@latest_event)}
                >
                  <.icon name="hero-arrow-uturn-left" class="size-4" />
                  {gettext("Undo")}
                </button>
              </div>
            </li>
            <li
              :if={length(@history) > 20}
              class="text-center text-xs text-base-content/50 py-2"
            >
              {gettext("+%{n} more on desktop", n: length(@history) - 20)}
            </li>
          </ul>
          <p :if={@history == []} class="text-sm text-base-content/60 px-1 py-4">
            {gettext("No activity recorded yet.")}
          </p>
        </section>

        <%!-- Escape to desktop --%>
        <section class="px-3 pb-6">
          <.link
            href={
              ~p"/view-mode?#{[mode: "desktop", to: "/farms/#{@current_scope.farm.slug}/animals/#{@animal.id}"]}"
            }
            class="btn btn-block btn-outline"
          >
            <.icon name="hero-computer-desktop" class="size-5" />
            {gettext("Open desktop view")}
          </.link>
        </section>

        <%!-- Edit sheet --%>
        <div
          :if={@edit_form}
          class="fixed inset-0 z-40 bg-black/40 flex items-end"
          phx-click="edit_close"
        >
          <.form
            :let={f}
            for={@edit_form}
            phx-change="edit_validate"
            phx-submit="edit_save"
            phx-click="ignore_click"
            class="w-full bg-base-100 rounded-t-2xl pb-[env(safe-area-inset-bottom)]
                   max-h-[90vh] overflow-y-auto"
          >
            <div class="flex justify-center pt-2 pb-1">
              <div class="w-10 h-1 rounded-full bg-base-300"></div>
            </div>
            <div class="px-4 py-2 border-b border-base-200 text-center">
              <div class="font-semibold">{gettext("Edit animal")}</div>
              <div class="text-xs text-base-content/60 font-mono">
                {@animal.ear_tag || "##{@animal.id}"}
              </div>
            </div>

            <div class="px-4 py-4 space-y-3">
              <label class="block">
                <span class="text-xs uppercase text-base-content/60">{gettext("Ear tag")}</span>
                <input
                  type="text"
                  name="animal[ear_tag]"
                  value={Phoenix.HTML.Form.input_value(f, :ear_tag)}
                  class="input input-bordered input-lg w-full mt-1 font-mono text-base"
                />
              </label>

              <div class="grid grid-cols-2 gap-3">
                <label class="block">
                  <span class="text-xs uppercase text-base-content/60">{gettext("DOB")}</span>
                  <input
                    type="date"
                    name="animal[dob]"
                    value={Phoenix.HTML.Form.input_value(f, :dob)}
                    class="input input-bordered input-lg w-full mt-1"
                  />
                </label>
                <label class="block">
                  <span class="text-xs uppercase text-base-content/60">{gettext("Breed")}</span>
                  <input
                    type="text"
                    name="animal[breed]"
                    value={Phoenix.HTML.Form.input_value(f, :breed)}
                    class="input input-bordered input-lg w-full mt-1"
                  />
                </label>
              </div>

              <label :if={@animal.tracking_type == "individual"} class="block">
                <span class="text-xs uppercase text-base-content/60">
                  {gettext("Pen (HOUSE-PEN)")}
                </span>
                <input
                  type="text"
                  name="pen_code"
                  value={@edit_pen_code}
                  phx-debounce="300"
                  autocomplete="off"
                  spellcheck="false"
                  placeholder="EB-12"
                  class={[
                    "input input-bordered input-lg w-full mt-1 font-mono",
                    @edit_pen_state == :resolved && "border-success focus:border-success",
                    @edit_pen_state == :not_found && "border-error focus:border-error"
                  ]}
                />
                <span class={[
                  "text-xs mt-1 block",
                  @edit_pen_state == :resolved && "text-success",
                  @edit_pen_state == :not_found && "text-error",
                  @edit_pen_state == :empty && "text-base-content/50"
                ]}>
                  {pen_state_text(@edit_pen_state)}
                </span>
              </label>

              <label class="block">
                <span class="text-xs uppercase text-base-content/60">{gettext("Notes")}</span>
                <textarea
                  name="animal[notes]"
                  rows="2"
                  class="textarea textarea-bordered w-full mt-1"
                >{Phoenix.HTML.Form.input_value(f, :notes)}</textarea>
              </label>

              <p :if={@edit_error} class="text-sm text-error">{@edit_error}</p>

              <div class="grid grid-cols-2 gap-3 pt-2">
                <button type="button" phx-click="edit_close" class="btn btn-lg btn-ghost">
                  {gettext("Cancel")}
                </button>
                <button
                  type="submit"
                  phx-disable-with={gettext("Saving…")}
                  class="btn btn-lg btn-primary"
                >
                  {gettext("Save")}
                </button>
              </div>
            </div>
          </.form>
        </div>

        <%!-- Movement sheet --%>
        <div
          :if={@move_form}
          class="fixed inset-0 z-40 bg-black/40 flex items-end"
          phx-click="move_close"
        >
          <.form
            :let={f}
            for={@move_form}
            phx-change="move_validate"
            phx-submit="move_save"
            phx-click="ignore_click"
            class="w-full bg-base-100 rounded-t-2xl pb-[env(safe-area-inset-bottom)]
                   max-h-[90vh] overflow-y-auto"
          >
            <div class="flex justify-center pt-2 pb-1">
              <div class="w-10 h-1 rounded-full bg-base-300"></div>
            </div>
            <div class="px-4 py-2 border-b border-base-200 text-center">
              <div class="font-semibold">{gettext("Record movement")}</div>
              <div class="text-xs text-base-content/60 font-mono">
                {@animal.ear_tag || "##{@animal.id}"}
              </div>
            </div>

            <div class="px-4 py-4 space-y-3">
              <label class="block">
                <span class="text-xs uppercase text-base-content/60">{gettext("Reason")}</span>
                <select
                  name="movement[reason]"
                  class="select select-bordered select-lg w-full mt-1"
                >
                  <option
                    :for={{label, value} <- reason_options(@animal)}
                    value={value}
                    selected={Phoenix.HTML.Form.input_value(f, :reason) == value}
                  >
                    {label}
                  </option>
                </select>
              </label>

              <label
                :if={
                  @animal.tracking_type == "batch" and
                    Phoenix.HTML.Form.input_value(f, :reason) not in ["placement", "adjustment_gain"]
                }
                class="block"
              >
                <span class="text-xs uppercase text-base-content/60">{gettext("From pen")}</span>
                <input
                  type="text"
                  name="from_code"
                  value={@move_from_code}
                  phx-debounce="300"
                  placeholder="EB-12"
                  class={[
                    "input input-bordered input-lg w-full mt-1 font-mono",
                    @move_from_state == :resolved && "border-success focus:border-success",
                    @move_from_state == :not_found && "border-error focus:border-error"
                  ]}
                />
                <span class={[
                  "text-xs mt-1 block",
                  @move_from_state == :resolved && "text-success",
                  @move_from_state == :not_found && "text-error",
                  @move_from_state == :empty && "text-base-content/50"
                ]}>
                  {pen_state_text(@move_from_state)}
                </span>
              </label>

              <label
                :if={
                  Phoenix.HTML.Form.input_value(f, :reason) in [
                    "placement",
                    "pen_transfer",
                    "adjustment_gain"
                  ]
                }
                class="block"
              >
                <span class="text-xs uppercase text-base-content/60">{gettext("To pen")}</span>
                <input
                  type="text"
                  name="to_code"
                  value={@move_to_code}
                  phx-debounce="300"
                  placeholder="EB-12"
                  class={[
                    "input input-bordered input-lg w-full mt-1 font-mono",
                    @move_to_state == :resolved && "border-success focus:border-success",
                    @move_to_state == :not_found && "border-error focus:border-error"
                  ]}
                />
                <span class={[
                  "text-xs mt-1 block",
                  @move_to_state == :resolved && "text-success",
                  @move_to_state == :not_found && "text-error",
                  @move_to_state == :empty && "text-base-content/50"
                ]}>
                  {pen_state_text(@move_to_state)}
                </span>
              </label>

              <div class="grid grid-cols-2 gap-3">
                <label :if={@animal.tracking_type == "batch"} class="block">
                  <span class="text-xs uppercase text-base-content/60">{gettext("Quantity")}</span>
                  <input
                    type="number"
                    name="movement[quantity]"
                    value={Phoenix.HTML.Form.input_value(f, :quantity)}
                    min="1"
                    inputmode="numeric"
                    class="input input-bordered input-lg w-full mt-1 font-mono"
                  />
                </label>
                <label class="block">
                  <span class="text-xs uppercase text-base-content/60">{gettext("When")}</span>
                  <input
                    type="date"
                    name="movement[moved_at]"
                    value={Phoenix.HTML.Form.input_value(f, :moved_at)}
                    class="input input-bordered input-lg w-full mt-1"
                  />
                </label>
              </div>

              <label class="block">
                <span class="text-xs uppercase text-base-content/60">{gettext("Notes")}</span>
                <input
                  type="text"
                  name="movement[notes]"
                  value={Phoenix.HTML.Form.input_value(f, :notes)}
                  class="input input-bordered input-lg w-full mt-1"
                />
              </label>

              <p :if={@move_error} class="text-sm text-error">{@move_error}</p>

              <div class="grid grid-cols-2 gap-3 pt-2">
                <button type="button" phx-click="move_close" class="btn btn-lg btn-ghost">
                  {gettext("Cancel")}
                </button>
                <button
                  type="submit"
                  phx-disable-with={gettext("Recording…")}
                  class="btn btn-lg btn-primary"
                >
                  {gettext("Record")}
                </button>
              </div>
            </div>
          </.form>
        </div>

        <%!-- Promote sheet --%>
        <div
          :if={@promote_open}
          class="fixed inset-0 z-40 bg-black/40 flex items-end"
          phx-click="promote_close"
        >
          <form
            phx-change="promote_validate"
            phx-submit="promote_save"
            phx-click="ignore_click"
            class="w-full bg-base-100 rounded-t-2xl pb-[env(safe-area-inset-bottom)]"
          >
            <div class="flex justify-center pt-2 pb-1">
              <div class="w-10 h-1 rounded-full bg-base-300"></div>
            </div>
            <div class="px-4 py-2 border-b border-base-200 text-center">
              <div class="font-semibold">{gettext("Promote stage")}</div>
              <div class="text-xs text-base-content/60">
                {gettext("Currently")}:
                <span class="font-mono font-semibold">
                  {String.capitalize(@animal.stage)}
                </span>
              </div>
            </div>

            <div class="px-4 py-4 space-y-3">
              <label class="block">
                <span class="text-xs uppercase text-base-content/60">{gettext("New stage")}</span>
                <select
                  name="new_stage"
                  class="select select-bordered select-lg w-full mt-1"
                >
                  <option
                    :for={{label, value} <- promote_targets(@animal)}
                    value={value}
                    selected={@promote_target == value}
                  >
                    {label}
                  </option>
                </select>
              </label>

              <p class="text-xs text-base-content/60">
                {gettext("Batch number, quantity, and placements stay the same.")}
              </p>

              <p :if={@promote_error} class="text-sm text-error">{@promote_error}</p>

              <div class="grid grid-cols-2 gap-3 pt-2">
                <button type="button" phx-click="promote_close" class="btn btn-lg btn-ghost">
                  {gettext("Cancel")}
                </button>
                <button
                  type="submit"
                  phx-disable-with={gettext("Promoting…")}
                  class="btn btn-lg btn-success"
                >
                  {gettext("Promote")}
                </button>
              </div>
            </div>
          </form>
        </div>
      </div>
    </Layouts.mobile_app>
    """
  end

  # ── Mount ──────────────────────────────────────────────────────────

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    animal = Animals.get_animal!(scope, String.to_integer(id))
    placements = Animals.list_placements(scope, animal)
    offspring = Animals.list_offspring(scope, animal)
    movements = Animals.list_movements(scope, animal)
    {services, litter_events} = breeding_data(scope, animal)
    history = build_history(animal, movements, services, litter_events)
    parity = sow_parity(scope, animal)

    {:ok,
     assign(socket,
       page_title: animal.ear_tag || "##{animal.id}",
       animal: animal,
       placements: placements,
       offspring: offspring,
       history: history,
       latest_event: latest_event_for(scope, animal),
       parity: parity,
       today: FarmClock.today(scope),
       can_manage: Policy.can?(scope, :manage_animals),
       can_move: Policy.can?(scope, :record_movement),
       edit_form: nil,
       edit_pen_code: "",
       edit_pen_state: :empty,
       edit_pen_id: nil,
       edit_error: nil,
       move_form: nil,
       move_from_code: "",
       move_from_state: :empty,
       move_from_id: nil,
       move_to_code: "",
       move_to_state: :empty,
       move_to_id: nil,
       move_error: nil,
       promote_open: false,
       promote_target: nil,
       promote_error: nil
     )}
  end

  # ── Events ─────────────────────────────────────────────────────────

  @impl true
  def handle_event("ignore_click", _, socket), do: {:noreply, socket}

  # Edit

  def handle_event("edit_open", _, socket) do
    if socket.assigns.can_manage do
      animal = socket.assigns.animal
      cs = Animals.change_animal(animal, %{})
      pen_code = current_pen_code(animal)
      pen_state = if pen_code == "", do: :empty, else: :resolved

      {:noreply,
       assign(socket,
         edit_form: to_form(cs, as: :animal),
         edit_pen_code: pen_code,
         edit_pen_state: pen_state,
         edit_pen_id: animal.current_pen_id,
         edit_error: nil
       )}
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("edit_close", _, socket), do: {:noreply, reset_edit(socket)}

  def handle_event("edit_validate", %{"animal" => params} = all, socket) do
    cs =
      Animals.change_animal(socket.assigns.animal, params)
      |> Map.put(:action, :validate)

    socket
    |> assign(edit_form: to_form(cs, as: :animal), edit_error: nil)
    |> resolve_edit_pen(all["pen_code"])
    |> then(&{:noreply, &1})
  end

  def handle_event("edit_save", %{"animal" => params} = all, socket) do
    if socket.assigns.can_manage do
      socket = resolve_edit_pen(socket, all["pen_code"])

      attrs =
        if socket.assigns.animal.tracking_type == "individual" do
          Map.put(params, "current_pen_id", socket.assigns.edit_pen_id)
        else
          params
        end

      case Animals.update_animal(socket.assigns.current_scope, socket.assigns.animal, attrs) do
        {:ok, _} ->
          animal = Animals.get_animal!(socket.assigns.current_scope, socket.assigns.animal.id)

          {:noreply,
           socket
           |> reset_edit()
           |> assign(animal: animal)
           |> put_flash(:info, gettext("Animal updated."))}

        {:error, %Ecto.Changeset{} = cs} ->
          {:noreply, assign(socket, edit_form: to_form(cs, as: :animal))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  # Movement

  def handle_event("move_open", _, socket) do
    if socket.assigns.can_move do
      animal = socket.assigns.animal
      today = socket.assigns.today
      from_code = current_pen_code(animal)
      from_state = if from_code == "", do: :empty, else: :resolved

      cs =
        Animals.change_movement(%Movement{
          moved_at: today,
          quantity: animal.quantity,
          reason: default_reason(animal)
        })

      {:noreply,
       assign(socket,
         move_form: to_form(cs, as: :movement),
         move_from_code: from_code,
         move_from_state: from_state,
         move_from_id: animal.current_pen_id,
         move_to_code: "",
         move_to_state: :empty,
         move_to_id: nil,
         move_error: nil
       )}
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("move_close", _, socket), do: {:noreply, reset_move(socket)}

  def handle_event("move_validate", %{"movement" => params} = all, socket) do
    cs =
      Animals.change_movement(%Movement{}, params)
      |> Map.put(:action, :validate)

    socket
    |> assign(move_form: to_form(cs, as: :movement), move_error: nil)
    |> resolve_move_pen(:from, all["from_code"])
    |> resolve_move_pen(:to, all["to_code"])
    |> then(&{:noreply, &1})
  end

  def handle_event("move_save", %{"movement" => params} = all, socket) do
    if socket.assigns.can_move do
      socket =
        socket
        |> resolve_move_pen(:from, all["from_code"])
        |> resolve_move_pen(:to, all["to_code"])

      attrs =
        params
        |> Map.put("from_pen_id", socket.assigns.move_from_id)
        |> Map.put("to_pen_id", socket.assigns.move_to_id)

      case Animals.record_movement(socket.assigns.current_scope, socket.assigns.animal, attrs) do
        {:ok, _} ->
          {:noreply,
           socket
           |> reset_move()
           |> reload_detail()
           |> put_flash(:info, gettext("Movement recorded."))}

        {:error, %Ecto.Changeset{} = cs} ->
          {:noreply, assign(socket, move_form: to_form(cs, as: :movement))}

        {:error, reason} ->
          {:noreply, assign(socket, move_error: humanize_move_error(reason))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  # Undo latest event

  def handle_event("undo_last_event", _, socket) do
    if socket.assigns.can_move do
      scope = socket.assigns.current_scope
      animal = socket.assigns.animal

      case AnimalActivity.undo_latest(scope, animal) do
        {:ok, kind, _} ->
          {:noreply,
           socket
           |> reload_detail()
           |> put_flash(:info, undo_success_flash(kind))}

        {:error, :no_events} ->
          {:noreply, put_flash(socket, :error, gettext("Nothing to undo."))}

        {:error, kind, reason} ->
          {:noreply, put_flash(socket, :error, undo_error_flash(kind, reason))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  # Mark reviewed

  def handle_event("mark_reviewed", _, socket) do
    if socket.assigns.can_manage do
      case Animals.mark_reviewed(socket.assigns.current_scope, socket.assigns.animal) do
        {:ok, _} ->
          {:noreply,
           socket
           |> reload_detail()
           |> put_flash(:info, gettext("Record confirmed as reviewed."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not mark as reviewed."))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  # Cull flag (orthogonal to status)

  def handle_event("mark_for_cull", _, socket) do
    cull_toggle(socket, &Animals.mark_for_cull/2, gettext("Flagged for culling."))
  end

  def handle_event("unmark_cull", _, socket) do
    cull_toggle(socket, &Animals.unmark_cull/2, gettext("Cull flag removed."))
  end

  # Promote stage

  def handle_event("promote_open", _, socket) do
    if socket.assigns.can_manage do
      default = promote_targets(socket.assigns.animal) |> List.first() |> elem(1)

      {:noreply, assign(socket, promote_open: true, promote_target: default, promote_error: nil)}
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("promote_close", _, socket) do
    {:noreply, assign(socket, promote_open: false, promote_target: nil, promote_error: nil)}
  end

  def handle_event("promote_validate", %{"new_stage" => stage}, socket) do
    {:noreply, assign(socket, promote_target: stage)}
  end

  def handle_event("promote_save", %{"new_stage" => new_stage}, socket) do
    if socket.assigns.can_manage do
      case Animals.promote_batch_stage(
             socket.assigns.current_scope,
             socket.assigns.animal,
             new_stage
           ) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(promote_open: false, promote_target: nil, promote_error: nil)
           |> reload_detail()
           |> put_flash(:info, gettext("Stage updated."))}

        {:error, %Ecto.Changeset{} = cs} ->
          msg =
            cs.errors
            |> Enum.map(fn {f, {m, _}} -> "#{f} #{m}" end)
            |> Enum.join(", ")

          {:noreply, assign(socket, promote_error: msg)}

        {:error, reason} ->
          {:noreply, assign(socket, promote_error: humanize_move_error(reason))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp promote_targets(%Animal{tracking_type: "batch", stage: current}) do
    Animal.stages_for("batch")
    |> Enum.reject(&(&1 == current))
    |> Enum.map(&{String.capitalize(&1), &1})
  end

  defp promote_targets(_), do: []

  defp cull_toggle(socket, fun, success_msg) do
    if socket.assigns.can_manage do
      case fun.(socket.assigns.current_scope, socket.assigns.animal) do
        {:ok, _} ->
          {:noreply, socket |> reload_detail() |> put_flash(:info, success_msg)}

        {:error, :individual_only} ->
          {:noreply,
           put_flash(socket, :error, gettext("Only individual animals can be flagged for cull."))}

        {:error, :not_present} ->
          {:noreply, put_flash(socket, :error, gettext("This animal has already left the farm."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not update the cull flag."))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  defp reload_detail(socket) do
    scope = socket.assigns.current_scope
    animal = Animals.get_animal!(scope, socket.assigns.animal.id)
    placements = Animals.list_placements(scope, animal)
    movements = Animals.list_movements(scope, animal)
    {services, litter_events} = breeding_data(scope, animal)
    history = build_history(animal, movements, services, litter_events)

    assign(socket,
      animal: animal,
      placements: placements,
      history: history,
      latest_event: latest_event_for(scope, animal),
      parity: sow_parity(scope, animal)
    )
  end

  defp latest_event_for(scope, %Animal{} = animal) do
    case AnimalActivity.latest_event(scope, animal) do
      nil -> nil
      {kind, row} -> {kind, row.id}
    end
  end

  defp reset_edit(socket) do
    assign(socket,
      edit_form: nil,
      edit_pen_code: "",
      edit_pen_state: :empty,
      edit_pen_id: nil,
      edit_error: nil
    )
  end

  defp reset_move(socket) do
    assign(socket,
      move_form: nil,
      move_from_code: "",
      move_from_state: :empty,
      move_from_id: nil,
      move_to_code: "",
      move_to_state: :empty,
      move_to_id: nil,
      move_error: nil
    )
  end

  defp resolve_edit_pen(socket, code), do: do_resolve_pen(socket, :edit, code)
  defp resolve_move_pen(socket, side, code), do: do_resolve_pen(socket, {:move, side}, code)

  defp do_resolve_pen(socket, target, nil), do: do_resolve_pen(socket, target, "")

  defp do_resolve_pen(socket, target, code) when is_binary(code) do
    code = String.trim(code)

    {state, pen_id} =
      cond do
        code == "" ->
          {:empty, nil}

        true ->
          case Locations.find_pen_by_code(socket.assigns.current_scope, code) do
            nil -> {:not_found, nil}
            pen -> {:resolved, pen.id}
          end
      end

    case target do
      :edit ->
        assign(socket, edit_pen_code: code, edit_pen_state: state, edit_pen_id: pen_id)

      {:move, :from} ->
        assign(socket, move_from_code: code, move_from_state: state, move_from_id: pen_id)

      {:move, :to} ->
        assign(socket, move_to_code: code, move_to_state: state, move_to_id: pen_id)
    end
  end

  defp current_pen_code(%{current_pen: %{code: code, house: %{code: hcode}}}),
    do: "#{hcode}-#{code}"

  defp current_pen_code(_), do: ""

  defp pen_state_text(:resolved), do: "✓"
  defp pen_state_text(:not_found), do: "⚠ No active pen with that code"
  defp pen_state_text(_), do: "Type house-pen, e.g. EB-12"

  defp default_reason(%Animal{tracking_type: "batch"}), do: "pen_transfer"
  defp default_reason(_), do: "pen_transfer"

  defp reason_options(%Animal{tracking_type: "individual"}) do
    Movement.reasons()
    |> Enum.reject(&(&1 in ["adjustment_loss", "adjustment_gain", "wean"]))
    |> Enum.map(&{humanize_reason(&1), &1})
  end

  defp reason_options(_) do
    Movement.reasons()
    |> Enum.reject(&(&1 == "wean"))
    |> Enum.map(&{humanize_reason(&1), &1})
  end

  defp humanize_reason(r), do: r |> String.replace("_", " ") |> String.capitalize()

  defp humanize_move_error(:litter_not_empty),
    do:
      gettext("This sow still has nursing piglets — wean them or record foster-out/deaths first.")

  defp humanize_move_error(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> String.replace("_", " ")

  defp humanize_move_error(reason), do: inspect(reason)

  defp breeding_data(scope, %Animal{tracking_type: "individual"} = animal) do
    services = Breeding.list_services_for_animal(scope, animal.id)
    litter_events = Breeding.list_litter_events_for_sow(scope, animal.id)
    {services, litter_events}
  end

  defp breeding_data(_scope, _animal), do: {[], []}

  defp sow_parity(scope, %Animal{tracking_type: "individual", stage: "sow", id: id}),
    do: Breeding.parity(scope, id)

  defp sow_parity(_scope, _animal), do: 0

  defp build_history(
         %Animal{tracking_type: "individual"} = animal,
         movements,
         services,
         litter_events
       ) do
    rows =
      Enum.map(movements, &row_from_movement/1) ++
        Enum.flat_map(services, &rows_from_service(&1, animal.id)) ++
        Enum.map(litter_events, &row_from_litter_event/1)

    Enum.sort(rows, fn a, b ->
      case Date.compare(a.date, b.date) do
        :gt -> true
        :lt -> false
        :eq -> {a.priority, a.id} >= {b.priority, b.id}
      end
    end)
  end

  defp build_history(_animal, movements, _services, _litter_events) do
    movements
    |> Enum.map(&row_from_movement/1)
    |> Enum.sort_by(& &1.date, {:desc, Date})
  end

  defp row_from_movement(m) do
    %{id: "m-#{m.id}", date: m.moved_at, priority: 2, kind: :movement, data: m}
  end

  defp rows_from_service(s, animal_id) do
    # A re-serviced service collapses to a single "Service closed" row at
    # served_at — the open and close are the same cycle.
    re_serviced? = s.result == "re_service" && s.result_at

    open =
      unless re_serviced? do
        %{
          id: "s-#{s.id}",
          date: s.served_at,
          priority: 1,
          kind: :service,
          data: %{service: s, animal_id: animal_id}
        }
      end

    close =
      cond do
        re_serviced? ->
          %{
            id: "sc-#{s.id}",
            date: s.served_at,
            priority: 1,
            kind: :service_closed,
            data: %{service: s, animal_id: animal_id}
          }

        s.result && s.result_at ->
          closed_kind = if s.result == "farrowing", do: :farrowing, else: :service_closed

          %{
            id: "sc-#{s.id}",
            date: s.result_at,
            priority: if(closed_kind == :farrowing, do: 3, else: 6),
            kind: closed_kind,
            data: %{service: s, animal_id: animal_id}
          }

        true ->
          nil
      end

    wean =
      case s.farrowing && s.farrowing.weaning do
        nil ->
          nil

        w ->
          %{
            id: "w-#{w.id}",
            date: w.weaned_at,
            priority: 5,
            kind: :weaning,
            data: %{weaning: w, farrowing: s.farrowing}
          }
      end

    [open, close, wean] |> Enum.reject(&is_nil/1)
  end

  defp row_from_litter_event(e) do
    %{id: "le-#{e.id}", date: e.occurred_at, priority: 4, kind: :litter_event, data: e}
  end

  defp history_kind_label(:movement), do: gettext("Movement")
  defp history_kind_label(:service), do: gettext("Served")
  defp history_kind_label(:farrowing), do: gettext("Farrowed")
  defp history_kind_label(:service_closed), do: gettext("Service closed")
  defp history_kind_label(:weaning), do: gettext("Weaned")
  defp history_kind_label(:litter_event), do: gettext("Litter event")

  defp history_kind_color(:farrowing), do: "text-success"
  defp history_kind_color(:weaning), do: "text-success"
  defp history_kind_color(:service), do: "text-info"
  defp history_kind_color(:service_closed), do: "text-error"
  defp history_kind_color(:litter_event), do: "text-warning"
  defp history_kind_color(:movement), do: "text-base-content/70"

  defp history_summary(%{kind: :movement, data: m}, _scope) do
    parts = [
      m.reason && humanize_reason(m.reason),
      m.from_pen && "from #{pen_code(m.from_pen)}",
      m.to_pen && "to #{pen_code(m.to_pen)}",
      m.quantity > 1 && "×#{m.quantity}"
    ]

    parts |> Enum.filter(& &1) |> Enum.join(" · ")
  end

  defp history_summary(%{kind: :service, data: %{service: s}}, _scope) do
    parts = [
      String.upcase(s.service_type),
      s.boar && "boar #{s.boar.ear_tag}",
      s.semen && "semen #{s.semen}"
    ]

    parts |> Enum.filter(& &1) |> Enum.join(" · ")
  end

  defp history_summary(%{kind: :farrowing, data: %{service: %{farrowing: f}}}, _scope)
       when not is_nil(f) do
    "Born alive #{f.born_alive}, stillborn #{f.stillborn || 0}, mummified #{f.mummified || 0}"
  end

  defp history_summary(%{kind: :farrowing}, _scope), do: gettext("Farrowing recorded")

  defp history_summary(
         %{kind: :service_closed, data: %{service: %{result: "re_service"} = s}},
         _scope
       ) do
    "re-serviced at #{s.result_at}"
  end

  defp history_summary(%{kind: :service_closed, data: %{service: s}}, _scope) do
    "Result: #{s.result}"
  end

  defp history_summary(%{kind: :weaning, data: %{weaning: w}}, scope) do
    avg =
      if w.avg_wean_weight_g,
        do: " · avg #{Peggy.Units.format_weight_g(w.avg_wean_weight_g, scope)}",
        else: ""

    "Weaned #{w.weaned_count}" <> avg
  end

  defp history_summary(%{kind: :litter_event, data: e}, _scope) do
    kind = humanize_litter_kind(e.kind)
    "#{kind} ×#{e.quantity}" <> if(e.notes && e.notes != "", do: " — #{e.notes}", else: "")
  end

  defp humanize_litter_kind("death"), do: gettext("Death")
  defp humanize_litter_kind("foster_in"), do: gettext("Foster in")
  defp humanize_litter_kind("foster_out"), do: gettext("Foster out")
  defp humanize_litter_kind(other), do: other

  # ── Undo helpers ───────────────────────────────────────────────────
  # Only the row matching `latest_event` (computed via AnimalActivity)
  # gets an Undo button — mirrors the desktop detail.

  defp history_undoable?(%{kind: :movement, data: %{id: id}}, {:movement, id}), do: true

  defp history_undoable?(%{kind: kind, data: %{service: %{id: id}}}, {:service, id})
       when kind in [:service, :service_closed],
       do: true

  defp history_undoable?(
         %{kind: :farrowing, data: %{service: %{farrowing: %{id: id}}}},
         {:farrowing, id}
       ),
       do: true

  defp history_undoable?(%{kind: :weaning, data: %{weaning: %{id: id}}}, {:weaning, id}),
    do: true

  defp history_undoable?(%{kind: :litter_event, data: %{id: id}}, {:litter_event, id}),
    do: true

  defp history_undoable?(_, _), do: false

  defp undo_confirm_text({:movement, _}),
    do: gettext("Undo this movement? This will reverse all related state changes.")

  defp undo_confirm_text({:service, _}),
    do: gettext("Undo this service? The sow will return to her prior status.")

  defp undo_confirm_text({:farrowing, _}),
    do: gettext("Undo this farrowing? The sow returns to served and the service reopens.")

  defp undo_confirm_text({:weaning, _}),
    do:
      gettext(
        "Undo this weaning? The sow returns to lactating and the weaner-batch quantity is decremented."
      )

  defp undo_confirm_text({:litter_event, _}),
    do: gettext("Undo this litter event?")

  defp undo_confirm_text(_), do: gettext("Undo this event?")

  defp undo_success_flash(:movement), do: gettext("Movement undone.")
  defp undo_success_flash(:service), do: gettext("Service undone.")
  defp undo_success_flash(:mounting), do: gettext("Mounting undone.")
  defp undo_success_flash(:farrowing), do: gettext("Farrowing undone.")
  defp undo_success_flash(:weaning), do: gettext("Weaning undone.")
  defp undo_success_flash(:litter_event), do: gettext("Litter event undone.")

  defp undo_error_flash(:service, :service_has_closed_outcome),
    do: gettext("Can't undo: this service already has a recorded outcome (farrowing/abortion).")

  defp undo_error_flash(:farrowing, :farrowing_has_weaning),
    do: gettext("Can't undo: weaning is already recorded — undo the weaning first.")

  defp undo_error_flash(:farrowing, :farrowing_has_activity),
    do:
      gettext(
        "Can't undo: piglet activity (deaths/fostering) is recorded against this farrowing."
      )

  defp undo_error_flash(:weaning, :weaning_has_activity),
    do: gettext("Can't undo: post-weaning activity is recorded against this batch.")

  defp undo_error_flash(:litter_event, :weaning_closed),
    do: gettext("Can't undo: the litter has already been weaned.")

  defp undo_error_flash(_kind, _reason), do: gettext("Could not undo.")

  defp pen_code(%{code: code, house: %{code: hcode}}), do: "#{hcode}-#{code}"
  defp pen_code(%{code: code}), do: code
  defp pen_code(_), do: "—"

  defp pen_label(%{tracking_type: "batch", placements: [_ | _] = placements}) do
    Enum.map_join(placements, " · ", fn p ->
      "#{p.pen.house.code}-#{p.pen.code}×#{p.quantity}"
    end)
  end

  defp pen_label(%{current_pen: %{code: code, house: %{code: hcode}}}), do: "#{hcode}-#{code}"
  defp pen_label(%{current_pen: %{code: code}}), do: code
  defp pen_label(_), do: nil

  defp age_days(%{dob: %Date{} = dob}, today), do: Date.diff(today, dob)
  defp age_days(_, _), do: 0
end
