defmodule PeggyWeb.FarmLive.Breeding.Lactating do
  @moduledoc """
  Lactating tab of the Breeding section. Owns the weaning form, litter
  death / fostering / ledger modals, and the lactating sows list.
  """
  use PeggyWeb, :live_view

  alias Peggy.{Animals, Breeding, FarmClock, Locations, Policy}
  alias Peggy.Breeding.LitterEvent
  alias PeggyWeb.FarmLive.Breeding.Shared

  @per_page Shared.per_page()

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-6xl">
        <.header>
          {gettext("Lactating")}
          <:subtitle>{gettext("Farrowed sows with piglets on the teat")}</:subtitle>
          <:actions>
            <.iframe_print_button
              id="lactating-print-btn"
              url={print_path(@current_scope.farm.slug, @filters, @sort, @dir)}
            />
          </:actions>
        </.header>

        <section class="mt-4">
          <form
            id="lactating-filters"
            phx-change="filter_lactating"
            phx-submit="filter_lactating"
            class="flex gap-1 flex-nowrap items-end overflow-x-auto [&_.fieldset>label]:flex [&_.fieldset>label]:flex-col [&_.fieldset>label]:items-start"
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
            <label class="form-control w-32">
              <div class="label py-1">
                <span class="label-text text-xs">{gettext("Litter age")}</span>
              </div>
              <select name="age" class="select select-sm select-bordered">
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
                    <.sort_header
                      label={gettext("Farrowed")}
                      col="farrowed"
                      sort={@sort}
                      dir={@dir}
                    />
                  </th>
                  <th class="py-2 text-right">{gettext("Born alive")}</th>
                  <th class="py-2 text-right">{gettext("Surviving")}</th>
                  <th class="py-2 text-right">
                    <.sort_header
                      label={gettext("Parity")}
                      col="parity"
                      sort={@sort}
                      dir={@dir}
                      align="right"
                    />
                  </th>
                  <th class="py-2">
                    <.sort_header label={gettext("Pen")} col="pen" sort={@sort} dir={@dir} />
                  </th>
                  <th class="py-2 text-right">
                    <.sort_header
                      label={gettext("Days")}
                      col="days"
                      sort={@sort}
                      dir={@dir}
                      align="right"
                    />
                  </th>
                  <th :if={@can_record} class="py-2"></th>
                </tr>
              </thead>
              <tbody id="lactating-rows" phx-update="stream">
                <tr
                  :for={{dom_id, entry} <- @streams.lactating}
                  id={dom_id}
                  class="border-t border-base-200"
                >
                  <td class="py-2 font-mono font-semibold">
                    <.link
                      navigate={
                        ~p"/farms/#{@current_scope.farm.slug}/animals/#{entry.farrowing.sow_id}"
                      }
                      class="text-primary underline underline-offset-2 decoration-dotted hover:decoration-solid"
                    >
                      {entry.farrowing.sow.ear_tag}
                    </.link>
                    <.cull_flag animal={entry.farrowing.sow} />
                    <Shared.recently_updated_badge at={entry.farrowing.updated_at} />
                  </td>
                  <td class="py-2">{entry.farrowing.farrowed_at}</td>
                  <td class="py-2 text-right">{entry.farrowing.born_alive}</td>
                  <td class="py-2 text-right">
                    <button
                      phx-click="show_ledger"
                      phx-value-farrowing-id={entry.farrowing.id}
                      class="btn btn-sm btn-outline btn-primary font-mono gap-1"
                      title={gettext("View litter ledger")}
                    >
                      {entry.surviving}
                      <.icon name="hero-book-open" class="size-3" />
                    </button>
                  </td>
                  <td class="py-2 text-right font-mono">{entry.parity}</td>
                  <td class="py-2 font-mono">
                    {entry.farrowing.pen &&
                      "#{entry.farrowing.pen.house.code}-#{entry.farrowing.pen.code}"}
                  </td>
                  <td class="py-2 text-right font-mono">
                    {Date.diff(@today, entry.farrowing.farrowed_at)}
                  </td>
                  <td :if={@can_record} class="py-2 text-right">
                    <button
                      phx-click="new_litter_death"
                      phx-value-farrowing-id={entry.farrowing.id}
                      class="btn btn-ghost btn-sm text-error/70"
                      title={gettext("Record pre-wean death")}
                    >
                      {gettext("Death")}
                    </button>
                    <button
                      phx-click="new_litter_foster"
                      phx-value-farrowing-id={entry.farrowing.id}
                      class="btn btn-ghost btn-sm"
                      title={gettext("Record fostering")}
                    >
                      {gettext("Foster")}
                    </button>
                    <button
                      phx-click="new_weaning"
                      phx-value-farrowing-id={entry.farrowing.id}
                      class="btn btn-ghost btn-sm"
                    >
                      {gettext("Wean")}
                    </button>
                    <button
                      phx-click="delete_farrowing"
                      phx-value-farrowing-id={entry.farrowing.id}
                      data-confirm={
                        gettext(
                          "Delete this farrowing? The sow will be reverted and the service reopened."
                        )
                      }
                      class="btn btn-ghost btn-sm text-error/70"
                      title={gettext("Delete farrowing")}
                    >
                      <.icon name="hero-trash" class="size-4" />
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
            <p :if={@total == 0} class="mt-2 text-sm text-base-content/60">
              {gettext("No lactating sows match the filters.")}
            </p>
          </div>

          <.infinite_scroll
            has_more={@has_more}
            total={@total}
            id="lactating-sentinel"
          />
        </section>

        <%!-- Pre-wean death modal --%>
        <Shared.modal
          :if={@form_mode == :litter_death}
          title={gettext("Record Pre-Wean Death")}
          on_cancel="cancel"
        >
          <div class="mb-3 text-sm">
            <span class="text-base-content/60">{gettext("Sow:")}</span>
            <span class="font-mono font-semibold">{@form_sow_tag}</span>
            <span class="text-base-content/60 ml-2">{gettext("Surviving:")}</span>
            <span class="font-mono">{@form_surviving}</span>
          </div>
          <.form
            for={@form}
            id="litter-death-form"
            phx-submit="save_litter_death"
            phx-change="validate_litter_event"
            class="grid grid-cols-2 gap-x-4 gap-y-1"
          >
            <.input
              field={@form[:occurred_at]}
              type="date"
              label={gettext("Occurred at")}
            />
            <.input
              field={@form[:quantity]}
              type="number"
              label={gettext("Quantity")}
              min="1"
              max={@form_surviving}
            />
            <div class="col-span-2">
              <.input field={@form[:notes]} type="textarea" label={gettext("Notes")} />
            </div>
            <div class="col-span-2 flex gap-2 justify-end">
              <button type="button" phx-click="cancel" class="btn btn-ghost">
                {gettext("Cancel")}
              </button>
              <.button class="btn btn-error" phx-disable-with={gettext("Saving...")}>
                {gettext("Record Death")}
              </.button>
            </div>
          </.form>
        </Shared.modal>

        <%!-- Fostering modal --%>
        <Shared.modal
          :if={@form_mode == :litter_foster}
          title={gettext("Record Fostering")}
          on_cancel="cancel"
        >
          <div class="mb-3 text-sm">
            <span class="text-base-content/60">{gettext("From sow:")}</span>
            <span class="font-mono font-semibold">{@form_sow_tag}</span>
            <span class="text-base-content/60 ml-2">{gettext("Surviving:")}</span>
            <span class="font-mono">{@form_surviving}</span>
          </div>
          <.form
            for={@form}
            id="litter-foster-form"
            phx-submit="save_litter_foster"
            phx-change="validate_litter_event"
            class="grid grid-cols-2 gap-x-4 gap-y-1"
          >
            <div class="col-span-2">
              <.autocomplete
                id="foster-dest-picker"
                label={gettext("Foster onto (lactating sow)")}
                name="litter_event[counterpart_farrowing_id]"
                value={Shared.fv(@form, :counterpart_farrowing_id)}
                items={@ac.foster_dest_items}
                selected_label={@ac.foster_dest_label}
                class="w-full input font-mono"
                placeholder={gettext("Search sows...")}
                empty_text={gettext("No sow suitable")}
              />
            </div>
            <.input
              field={@form[:occurred_at]}
              type="date"
              label={gettext("Occurred at")}
            />
            <.input
              field={@form[:quantity]}
              type="number"
              label={gettext("Quantity")}
              min="1"
              max={@form_surviving}
            />
            <div class="col-span-2">
              <.input field={@form[:notes]} type="textarea" label={gettext("Notes")} />
            </div>
            <div class="col-span-2 flex gap-2 justify-end">
              <button type="button" phx-click="cancel" class="btn btn-ghost">
                {gettext("Cancel")}
              </button>
              <.button class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
                {gettext("Record Fostering")}
              </.button>
            </div>
          </.form>
        </Shared.modal>

        <%!-- Litter ledger modal (read-only) --%>
        <Shared.modal
          :if={@form_mode == :litter_ledger}
          title={gettext("Litter Ledger")}
          on_cancel="cancel"
        >
          <div class="mb-3 text-sm">
            <span class="text-base-content/60">{gettext("Sow:")}</span>
            <span class="font-mono font-semibold">{@form_sow_tag}</span>
            <span class="text-base-content/60 ml-2">{gettext("Born alive:")}</span>
            <span class="font-mono">{@form_born_alive}</span>
            <span class="text-base-content/60 ml-2">{gettext("Surviving:")}</span>
            <span class="font-mono">{@form_surviving}</span>
          </div>
          <div :if={@ledger_events == []} class="text-sm text-base-content/60 py-4 text-center">
            {gettext("No litter events yet.")}
          </div>
          <table :if={@ledger_events != []} class="table table-sm w-full">
            <thead class="text-left text-base-content/60">
              <tr>
                <th class="py-1">{gettext("Date")}</th>
                <th class="py-1">{gettext("Kind")}</th>
                <th class="py-1 text-right">{gettext("Qty")}</th>
                <th class="py-1">{gettext("Counterpart sow")}</th>
                <th class="py-1">{gettext("Notes")}</th>
                <th :if={@can_record} class="py-1 text-right">{gettext("Actions")}</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={ev <- @ledger_events}
                class="border-t border-base-200"
              >
                <td class="py-1">{ev.occurred_at}</td>
                <td class="py-1">{humanize_kind(ev.kind)}</td>
                <td class="py-1 text-right font-mono">{ev.quantity}</td>
                <td class="py-1 font-mono">{ev.counterpart_tag || "—"}</td>
                <td class="py-1 text-base-content/70">{ev.notes}</td>
                <td :if={@can_record} class="py-1 text-right">
                  <button
                    phx-click="delete_litter_event"
                    phx-value-event-id={ev.id}
                    data-confirm={
                      gettext(
                        "Delete this litter event? Paired fostering events are removed together."
                      )
                    }
                    class="btn btn-ghost btn-sm text-error/80"
                    title={gettext("Delete event")}
                  >
                    <.icon name="hero-trash" class="size-4" />
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
          <div class="mt-4 flex justify-end">
            <button type="button" phx-click="cancel" class="btn btn-ghost">
              {gettext("Close")}
            </button>
          </div>
        </Shared.modal>

        <%!-- Weaning form modal --%>
        <Shared.modal
          :if={@form_mode == :weaning}
          title={gettext("Record Weaning")}
          on_cancel="cancel"
        >
          <div :if={@wn && @wn.locked} class="mb-3 text-sm">
            <span class="text-base-content/60">{gettext("Sow:")}</span>
            <span class="font-mono font-semibold">{@form_sow_tag}</span>
            <span class="text-base-content/60 ml-2">{gettext("Born alive:")}</span>
            <span>{@form_born_alive}</span>
            <span class="text-base-content/60 ml-2">{gettext("Surviving:")}</span>
            <span>{@form_surviving}</span>
          </div>
          <.form
            for={@form}
            id="weaning-form"
            phx-submit="save_weaning"
            phx-change="validate_weaning"
            class="grid grid-cols-2 gap-x-4 gap-y-1"
          >
            <%!-- Editable sow tag (top-level entry) --%>
            <div :if={@wn && not @wn.locked} class="col-span-2">
              <label class="form-control w-full">
                <div class="label py-1">
                  <span class="label-text">{gettext("Sow ear tag")}</span>
                </div>
                <input
                  type="text"
                  name="sow_tag"
                  value={@wn.sow_tag}
                  phx-debounce="300"
                  autocomplete="off"
                  placeholder={gettext("Type sow ear tag…")}
                  class={[
                    "input input-bordered font-mono",
                    @wn.sow_state == :resolved && "border-success focus:border-success",
                    @wn.sow_state in [:not_found, :no_open_farrowing] &&
                      "border-error focus:border-error"
                  ]}
                />
                <p class={[
                  "label pt-1 text-xs",
                  @wn.sow_state == :resolved && "text-success",
                  @wn.sow_state in [:not_found, :no_open_farrowing] && "text-error",
                  @wn.sow_state == :empty && "text-base-content/40"
                ]}>
                  {wn_state_text(@wn.sow_state)}
                </p>
              </label>
            </div>

            <%!-- Backfill panel (no open farrowing, or sow unknown) --%>
            <div
              :if={@wn && @wn.sow_state in [:not_found, :no_open_farrowing]}
              class="col-span-2 mb-2 rounded border border-warning/40 bg-warning/5 p-3 text-sm"
            >
              <div class="font-semibold text-warning mb-1">
                {if @wn.sow_state == :not_found,
                  do: gettext("Register new sow + backfill service & farrowing"),
                  else: gettext("Backfill service + farrowing")}
              </div>
              <p class="text-xs text-base-content/70 mb-2">
                {gettext(
                  "This will create an inferred AI service and farrowing (and sow, if unknown) flagged for review."
                )}
              </p>

              <div :if={@wn.sow_state == :not_found} class="grid grid-cols-2 gap-x-4 gap-y-1 mb-2">
                <label class="form-control">
                  <div class="label py-1">
                    <span class="label-text text-xs">{gettext("Breed (optional)")}</span>
                  </div>
                  <input
                    type="text"
                    name="sow_breed"
                    value={@wn.backfill.breed}
                    class="input input-sm input-bordered"
                  />
                </label>
                <label class="form-control">
                  <div class="label py-1">
                    <span class="label-text text-xs">{gettext("Sow DOB")}</span>
                  </div>
                  <input
                    type="date"
                    name="sow_dob"
                    value={@wn.backfill.dob}
                    class="input input-sm input-bordered"
                  />
                </label>
              </div>

              <div class="grid grid-cols-2 gap-x-4 gap-y-1 mb-2">
                <label class="form-control">
                  <div class="label py-1">
                    <span class="label-text text-xs">
                      {gettext("Farrowed at (defaults to weaned − %{n}d)",
                        n: Peggy.Breeding.lactation_days(@current_scope)
                      )}
                    </span>
                  </div>
                  <input
                    type="date"
                    name="farrowed_at"
                    value={@wn.backfill.farrowed_at}
                    class="input input-sm input-bordered"
                  />
                </label>
                <label class="form-control">
                  <div class="label py-1">
                    <span class="label-text text-xs">
                      {gettext("Served at (defaults to farrowed − %{n}d)",
                        n: Peggy.Breeding.gestation_days(@current_scope)
                      )}
                    </span>
                  </div>
                  <input
                    type="date"
                    name="served_at"
                    value={@wn.backfill.served_at}
                    class="input input-sm input-bordered"
                  />
                </label>
              </div>

              <div class="grid grid-cols-2 gap-x-4 gap-y-1">
                <label class="form-control">
                  <div class="label py-1">
                    <span class="label-text text-xs">
                      {gettext("Born alive (for backfilled farrowing)")}
                    </span>
                  </div>
                  <input
                    type="number"
                    name="born_alive"
                    min="0"
                    value={@wn.backfill.born_alive}
                    class="input input-sm input-bordered"
                  />
                </label>
                <label class="form-control">
                  <div class="label py-1">
                    <span class="label-text text-xs">{gettext("Boar ear tag (optional)")}</span>
                  </div>
                  <input
                    type="text"
                    name="boar_tag"
                    value={@wn.backfill.boar_tag}
                    class="input input-sm input-bordered font-mono"
                  />
                </label>
              </div>
            </div>

            <%!-- Resolved farrowing summary --%>
            <div
              :if={@wn && @wn.resolved_farrowing}
              class="col-span-2 mb-2 rounded border border-base-300 bg-base-200/50 p-3 text-sm"
            >
              <div class="font-semibold mb-1">{gettext("Open farrowing to wean")}</div>
              <dl class="grid grid-cols-2 gap-x-4 gap-y-0.5 text-xs">
                <dt class="text-base-content/60">{gettext("Farrowed at")}</dt>
                <dd class="font-mono">{@wn.resolved_farrowing.farrowed_at}</dd>
                <dt class="text-base-content/60">{gettext("Born alive")}</dt>
                <dd class="font-mono">{@wn.resolved_farrowing.born_alive}</dd>
                <dt class="text-base-content/60">{gettext("Surviving")}</dt>
                <dd class="font-mono">{@form_surviving}</dd>
                <dt class="text-base-content/60">{gettext("Pen")}</dt>
                <dd class="font-mono">
                  {@wn.resolved_farrowing.pen &&
                    "#{@wn.resolved_farrowing.pen.house.code}-#{@wn.resolved_farrowing.pen.code}"}
                </dd>
              </dl>
            </div>
            <.input
              field={@form[:weaned_at]}
              type="date"
              label={gettext("Weaned at")}
            />
            <.input
              field={@form[:weaned_count]}
              type="number"
              label={gettext("Weaned count")}
              min="0"
            />
            <.input
              field={@form[:avg_wean_weight_g]}
              type="number"
              label={gettext("Avg wean weight (g)")}
              min="0"
            />
            <div>
              <.autocomplete
                id={"weaning-batch-tag-picker-#{weaning_picker_date_key(@form)}"}
                label={gettext("Weaner batch id")}
                name="weaning[batch_tag]"
                value={Shared.fv(@form, :batch_tag)}
                items={
                  Enum.map(
                    @weaner_batches,
                    &%{id: &1.ear_tag, label: "#{&1.ear_tag} (#{&1.quantity})"}
                  )
                }
                class="w-full input"
                placeholder={gettext("e.g. W20260417")}
                freetext
              />
              <p class="text-xs text-base-content/60 mt-0.5">
                {@batch_tag_hint}
              </p>
            </div>
            <.autocomplete
              id="weaning-dest-pen-picker"
              label={gettext("Sow destination pen")}
              name="weaning[destination_pen_id]"
              value={Shared.fv(@form, :destination_pen_id)}
              items={@ac.pen_items}
              selected_label={@ac.dest_pen_label}
              class="w-full input font-mono"
              placeholder={gettext("Where the sow goes (dry housing)...")}
            />
            <div class="col-span-2">
              <.input field={@form[:notes]} type="textarea" label={gettext("Notes")} />
            </div>
            <div class="col-span-2 flex gap-2 justify-end">
              <button type="button" phx-click="cancel" class="btn btn-ghost">
                {gettext("Cancel")}
              </button>
              <.button
                class="btn btn-primary"
                phx-disable-with={gettext("Saving...")}
                disabled={not weaning_save_enabled?(@wn)}
              >
                {weaning_save_label(@wn)}
              </.button>
            </div>
          </.form>
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
       form_mode: nil,
       form: nil,
       form_target: nil,
       form_sow_tag: nil,
       form_born_alive: nil,
       form_surviving: nil,
       ledger_events: [],
       ac: Shared.default_ac(scope),
       pens: Locations.list_all_pens(scope),
       weaner_batches: [],
       batch_tag_hint: "",
       wn: nil,
       per_page: @per_page,
       today: FarmClock.today(scope),
       sort: "farrowed",
       dir: "asc"
     )
     |> stream_configure(:lactating, dom_id: &"farrowing-#{&1.farrowing.id}")
     |> stream(:lactating, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = %{
      q: params["q"] || "",
      age: Shared.param_age(params["age"]),
      pen_id: params["pen_id"] || "",
      pen_search: params["pen_search"] || "",
      min_parity: params["min_parity"] || "",
      max_parity: params["max_parity"] || ""
    }

    {:noreply,
     socket
     |> assign(
       filters: filters,
       page: 1,
       sort: lactating_sort_param(params["sort"]),
       dir: dir_param(params["dir"])
     )
     |> load_rows()
     |> maybe_open_from_params(params)}
  end

  @lactating_sort_columns ~w(tag pen parity farrowed days)
  defp lactating_sort_param(s) when s in @lactating_sort_columns, do: s
  defp lactating_sort_param(_), do: "farrowed"

  defp dir_param("desc"), do: "desc"
  defp dir_param(_), do: "asc"

  defp maybe_open_from_params(socket, %{"new" => "weaning"}) do
    if socket.assigns.can_record do
      {:noreply, s} = handle_event("new_top_weaning", %{}, socket)
      s
    else
      socket
    end
  end

  defp maybe_open_from_params(socket, _), do: socket

  # ── Events ─────────────────────────────────────────────────────────

  @impl true
  def handle_event("new_weaning", %{"farrowing-id" => id}, socket) do
    scope = socket.assigns.current_scope
    farrowing = Breeding.get_farrowing!(scope, String.to_integer(id))
    surviving = Breeding.surviving_piglet_count(farrowing)

    weaner_batches = Breeding.list_active_weaner_batches(scope)

    form =
      weaning_form(scope, %{
        weaned_at: FarmClock.today(scope),
        weaned_count: surviving
      })

    wn = %{
      locked: true,
      sow_tag: farrowing.sow.ear_tag,
      sow_state: :resolved,
      resolved_farrowing: farrowing,
      backfill: default_wn_backfill(scope, nil)
    }

    {:noreply,
     assign(socket,
       form_mode: :weaning,
       form: form,
       form_target: farrowing,
       form_sow_tag: farrowing.sow.ear_tag,
       form_born_alive: farrowing.born_alive,
       form_surviving: surviving,
       ac: Shared.default_ac(scope),
       weaner_batches: weaner_batches,
       batch_tag_hint: batch_tag_hint(scope, Shared.fv(form, :batch_tag)),
       wn: wn
     )}
  end

  def handle_event("new_top_weaning", _, socket) do
    scope = socket.assigns.current_scope
    today = FarmClock.today(scope)
    form = weaning_form(scope, %{weaned_at: today})

    wn = %{
      locked: false,
      sow_tag: "",
      sow_state: :empty,
      resolved_farrowing: nil,
      backfill: default_wn_backfill(scope, today)
    }

    {:noreply,
     assign(socket,
       form_mode: :weaning,
       form: form,
       form_target: nil,
       form_sow_tag: nil,
       form_born_alive: nil,
       form_surviving: nil,
       ac: Shared.default_ac(scope),
       weaner_batches: Breeding.list_active_weaner_batches(scope),
       batch_tag_hint: batch_tag_hint(scope, Shared.fv(form, :batch_tag)),
       wn: wn
     )}
  end

  def handle_event("validate_weaning", %{"weaning" => params} = all, socket) do
    params = refresh_weaning_batch_tag(socket.assigns.form, params)
    sow_tag = all["sow_tag"]

    socket =
      socket
      |> assign(:form, weaning_form(socket.assigns.current_scope, params))
      |> assign(
        :batch_tag_hint,
        batch_tag_hint(socket.assigns.current_scope, params["batch_tag"])
      )
      |> merge_wn_backfill_params(all, params)

    socket =
      if (socket.assigns.wn && not socket.assigns.wn.locked) and not is_nil(sow_tag) do
        resolve_wn_sow(socket, sow_tag)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("save_weaning", %{"weaning" => params} = all, socket) do
    if socket.assigns.can_record do
      wn = socket.assigns.wn
      params = refresh_weaning_batch_tag(socket.assigns.form, params)

      socket =
        socket
        |> then(fn s ->
          if wn && not wn.locked && not is_nil(all["sow_tag"]),
            do: resolve_wn_sow(s, all["sow_tag"]),
            else: s
        end)
        |> merge_wn_backfill_params(all, params)

      wn = socket.assigns.wn

      cond do
        is_nil(wn) ->
          {:noreply, put_flash(socket, :error, gettext("Form state lost; please retry."))}

        wn.locked ->
          do_save_weaning(socket, socket.assigns.form_target, params)

        wn.sow_state == :resolved ->
          do_save_weaning(socket, wn.resolved_farrowing, params)

        wn.sow_state == :not_found ->
          do_save_weaning_backfill(socket, :new_sow, params)

        wn.sow_state == :no_open_farrowing ->
          do_save_weaning_backfill(socket, :existing_sow, params)

        true ->
          {:noreply, put_flash(socket, :error, gettext("Type a sow ear tag before saving."))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("new_litter_death", %{"farrowing-id" => id}, socket) do
    scope = socket.assigns.current_scope
    farrowing = Breeding.get_farrowing!(scope, String.to_integer(id))
    surviving = Breeding.surviving_piglet_count(farrowing)

    cs =
      LitterEvent.changeset(%LitterEvent{}, %{
        "kind" => "death",
        "occurred_at" => FarmClock.today(scope),
        "quantity" => 1
      })
      |> Map.put(:action, nil)

    {:noreply,
     assign(socket,
       form_mode: :litter_death,
       form: to_form(cs, as: :litter_event),
       form_target: farrowing,
       form_sow_tag: farrowing.sow.ear_tag,
       form_born_alive: farrowing.born_alive,
       form_surviving: surviving
     )}
  end

  def handle_event("new_litter_foster", %{"farrowing-id" => id}, socket) do
    scope = socket.assigns.current_scope
    source = Breeding.get_farrowing!(scope, String.to_integer(id))
    surviving = Breeding.surviving_piglet_count(source)

    cs =
      LitterEvent.changeset(%LitterEvent{}, %{
        "kind" => "foster_out",
        "occurred_at" => FarmClock.today(scope),
        "quantity" => 1
      })
      |> Map.put(:action, nil)

    ac =
      Map.merge(Shared.default_ac(scope), %{
        foster_dest_items: foster_dest_items(scope, source.id)
      })

    {:noreply,
     assign(socket,
       form_mode: :litter_foster,
       form: to_form(cs, as: :litter_event),
       form_target: source,
       form_sow_tag: source.sow.ear_tag,
       form_born_alive: source.born_alive,
       form_surviving: surviving,
       ac: ac
     )}
  end

  def handle_event("validate_litter_event", %{"litter_event" => params}, socket) do
    cs =
      LitterEvent.changeset(%LitterEvent{}, params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(cs, as: :litter_event))}
  end

  def handle_event("save_litter_death", %{"litter_event" => params}, socket) do
    if socket.assigns.can_record do
      farrowing = socket.assigns.form_target

      case Breeding.record_pre_wean_death(socket.assigns.current_scope, farrowing, params) do
        {:ok, _event} ->
          {:noreply,
           socket
           |> close_form()
           |> load_rows()
           |> put_flash(:info, gettext("Pre-wean death recorded."))
           |> push_event("flash-row", %{id: "farrowing-#{farrowing.id}"})}

        {:error, :invalid_quantity} ->
          {:noreply, put_flash(socket, :error, gettext("Quantity must be at least 1."))}

        {:error, :insufficient_surviving} ->
          {:noreply, put_flash(socket, :error, gettext("Quantity exceeds surviving piglets."))}

        {:error, %Ecto.Changeset{} = cs} ->
          {:noreply, assign(socket, :form, to_form(cs, as: :litter_event))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("save_litter_foster", %{"litter_event" => params}, socket) do
    if socket.assigns.can_record do
      scope = socket.assigns.current_scope
      source = socket.assigns.form_target
      dest_id = params["counterpart_farrowing_id"]

      case Shared.parse_int(dest_id) do
        nil ->
          cs =
            LitterEvent.changeset(%LitterEvent{}, params)
            |> Ecto.Changeset.add_error(
              :counterpart_farrowing_id,
              gettext("pick a destination sow")
            )
            |> Map.put(:action, :validate)

          {:noreply, assign(socket, :form, to_form(cs, as: :litter_event))}

        dest_farrowing_id ->
          dest = Breeding.get_farrowing!(scope, dest_farrowing_id)

          case Breeding.record_fostering(scope, source, dest, params) do
            {:ok, _pair} ->
              {:noreply,
               socket
               |> close_form()
               |> load_rows()
               |> put_flash(:info, gettext("Fostering recorded."))
               |> push_event("flash-row", %{id: "farrowing-#{source.id}"})}

            {:error, :same_farrowing} ->
              {:noreply,
               put_flash(socket, :error, gettext("Source and destination must differ."))}

            {:error, :invalid_quantity} ->
              {:noreply, put_flash(socket, :error, gettext("Quantity must be at least 1."))}

            {:error, :insufficient_surviving} ->
              {:noreply,
               put_flash(socket, :error, gettext("Quantity exceeds surviving piglets."))}

            {:error, {_step, %Ecto.Changeset{} = cs}} ->
              {:noreply, assign(socket, :form, to_form(cs, as: :litter_event))}
          end
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("show_ledger", %{"farrowing-id" => id}, socket) do
    scope = socket.assigns.current_scope
    farrowing = Breeding.get_farrowing!(scope, String.to_integer(id))
    surviving = Breeding.surviving_piglet_count(farrowing)
    events = load_ledger_events(scope, farrowing)

    {:noreply,
     assign(socket,
       form_mode: :litter_ledger,
       form_target: farrowing,
       form_sow_tag: farrowing.sow.ear_tag,
       form_born_alive: farrowing.born_alive,
       form_surviving: surviving,
       ledger_events: events
     )}
  end

  def handle_event("delete_litter_event", %{"event-id" => id}, socket) do
    if socket.assigns.can_record do
      scope = socket.assigns.current_scope
      event = Peggy.Repo.get!(LitterEvent, String.to_integer(id))

      case Breeding.delete_litter_event(scope, event) do
        {:ok, :deleted} ->
          farrowing = socket.assigns.form_target

          if farrowing do
            events = load_ledger_events(scope, farrowing)
            surviving = Breeding.surviving_piglet_count(farrowing)

            {:noreply,
             socket
             |> load_rows()
             |> assign(ledger_events: events, form_surviving: surviving)
             |> put_flash(:info, gettext("Litter event deleted."))}
          else
            {:noreply,
             socket
             |> load_rows()
             |> put_flash(:info, gettext("Litter event deleted."))}
          end

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

  def handle_event("cancel", _, socket), do: {:noreply, close_form(socket)}

  def handle_event("delete_farrowing", %{"farrowing-id" => id}, socket) do
    scope = socket.assigns.current_scope

    if socket.assigns.can_record do
      farrowing = Breeding.get_farrowing!(scope, String.to_integer(id))

      case Breeding.delete_farrowing(scope, farrowing) do
        {:ok, _} ->
          {:noreply,
           socket
           |> load_rows()
           |> put_flash(:info, gettext("Farrowing deleted. Restore from the Deleted tab."))}

        {:error, :farrowing_has_weaning} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("Cannot delete — a weaning has been recorded for this farrowing.")
           )}

        {:error, :farrowing_has_activity} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("Cannot delete — the litter has downstream activity (moves or mortality).")
           )}

        {:error, :already_deleted} ->
          {:noreply, put_flash(socket, :error, gettext("Farrowing is already deleted."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not delete farrowing."))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("filter_lactating", params, socket) do
    query = %{
      "q" => params["q"] || "",
      "age" => params["age"] || "all",
      "pen_id" => params["pen_id"] || "",
      "pen_search" => params["pen_search"] || "",
      "min_parity" => params["min_parity"] || "",
      "max_parity" => params["max_parity"] || ""
    }

    {:noreply, push_patch(socket, to: Shared.tab_path(socket, "lactating", query))}
  end

  def handle_event("load_more", _, socket) do
    {:noreply, append_rows(socket)}
  end

  def handle_event("sort", %{"col" => col}, socket) do
    new_sort = lactating_sort_param(col)

    new_dir =
      cond do
        new_sort == socket.assigns.sort and socket.assigns.dir == "asc" -> "desc"
        new_sort == socket.assigns.sort and socket.assigns.dir == "desc" -> "asc"
        true -> "asc"
      end

    {:noreply,
     push_patch(socket,
       to: Shared.tab_path(socket, "lactating", %{"sort" => new_sort, "dir" => new_dir})
     )}
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp do_save_weaning(socket, farrowing, params) do
    case Breeding.record_weaning(socket.assigns.current_scope, farrowing, params) do
      {:ok, _weaning, _batch} ->
        {:noreply,
         socket
         |> close_form()
         |> load_rows()
         |> put_flash(:info, gettext("Weaning recorded."))}

      {:error, :already_weaned} ->
        {:noreply,
         socket
         |> close_form()
         |> load_rows()
         |> put_flash(:error, gettext("Already weaned."))}

      {:error, :batch_tag_required} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Enter a weaner batch id to pool into (or a new id for a fresh batch).")
         )}

      {:error, cs} ->
        {:noreply, assign(socket, :form, weaning_form(socket.assigns.current_scope, params, cs))}
    end
  end

  defp load_rows(socket) do
    scope = socket.assigns.current_scope
    filters = socket.assigns.filters

    opts = [
      search: filters.q,
      age_bucket: filters.age,
      pen_id: filters.pen_id,
      pen_search: blank_to_nil(filters.pen_search),
      min_parity: blank_to_nil(filters.min_parity),
      max_parity: blank_to_nil(filters.max_parity),
      sort: socket.assigns.sort,
      dir: socket.assigns.dir,
      limit: @per_page,
      offset: 0
    ]

    rows =
      Breeding.list_lactating_sows(scope, opts)
      |> Enum.map(fn f ->
        %{farrowing: f, surviving: Breeding.surviving_piglet_count(f)}
      end)
      |> attach_parity(scope)

    total = Breeding.count_lactating_sows(scope, opts)

    socket
    |> assign(total: total, page: 1, has_more: length(rows) < total)
    |> stream(:lactating, rows, reset: true)
  end

  defp append_rows(socket) do
    scope = socket.assigns.current_scope
    filters = socket.assigns.filters
    next_page = socket.assigns.page + 1

    opts = [
      search: filters.q,
      age_bucket: filters.age,
      pen_id: filters.pen_id,
      pen_search: blank_to_nil(filters.pen_search),
      min_parity: blank_to_nil(filters.min_parity),
      max_parity: blank_to_nil(filters.max_parity),
      sort: socket.assigns.sort,
      dir: socket.assigns.dir,
      limit: @per_page,
      offset: (next_page - 1) * @per_page
    ]

    rows =
      Breeding.list_lactating_sows(scope, opts)
      |> Enum.map(fn f ->
        %{farrowing: f, surviving: Breeding.surviving_piglet_count(f)}
      end)
      |> attach_parity(scope)

    loaded = next_page * @per_page

    socket =
      Enum.reduce(rows, socket, fn row, acc -> stream_insert(acc, :lactating, row) end)

    assign(socket, page: next_page, has_more: loaded < socket.assigns.total)
  end

  defp close_form(socket) do
    assign(socket,
      form_mode: nil,
      form: nil,
      form_target: nil,
      form_sow_tag: nil,
      form_born_alive: nil,
      form_surviving: nil,
      ledger_events: [],
      ac: Shared.default_ac(socket.assigns.current_scope)
    )
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  defp attach_parity(rows, scope) do
    sow_ids = Enum.map(rows, & &1.farrowing.sow_id)
    parities = Breeding.parities_for(scope, sow_ids)
    Enum.map(rows, &Map.put(&1, :parity, Map.get(parities, &1.farrowing.sow_id, 0)))
  end

  defp foster_dest_items(scope, source_farrowing_id) do
    scope
    |> Breeding.list_lactating_sows(limit: :all)
    |> Enum.reject(&(&1.id == source_farrowing_id))
    |> Enum.map(&%{id: &1.id, label: &1.sow.ear_tag})
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

  defp weaning_form(scope, fields, changeset \\ nil) do
    fields = normalize_weaning_fields(fields)

    weaned_at =
      fields["weaned_at"] ||
        (changeset && Ecto.Changeset.get_field(changeset, :weaned_at)) ||
        FarmClock.today(scope)

    params =
      fields
      |> Map.put("weaned_at", weaned_at)
      |> then(fn p ->
        Map.put(
          p,
          "batch_tag",
          p["batch_tag"] || Breeding.default_wean_batch_tag(weaned_at)
        )
      end)

    to_form(params, as: :weaning)
  end

  defp normalize_weaning_fields(fields) when is_map(fields) do
    Map.new(fields, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp normalize_weaning_fields(fields) when is_list(fields),
    do: normalize_weaning_fields(Map.new(fields))

  # The batch-tag autocomplete uses phx-update="ignore", so change its
  # wrapper id when weaned_at changes to remount with the refreshed value.
  defp weaning_picker_date_key(form) do
    form
    |> Shared.fv(:weaned_at)
    |> case do
      %Date{} = d -> Date.to_iso8601(d)
      s when is_binary(s) -> s
      _ -> "unknown"
    end
    |> String.replace("-", "")
  end

  defp refresh_weaning_batch_tag(form, params) do
    Map.put(
      params,
      "batch_tag",
      Breeding.refresh_auto_batch_tag(
        params["batch_tag"] || Shared.fv(form, :batch_tag),
        Shared.fv(form, :weaned_at),
        params["weaned_at"]
      )
    )
  end

  # Shows a live hint below the batch_tag field so the operator knows
  # whether the tag pools into an existing batch or starts a new one.
  defp batch_tag_hint(scope, tag) do
    case Breeding.find_active_weaner_batch(scope, tag || "") do
      nil ->
        case (tag || "") |> to_string() |> String.trim() do
          "" ->
            gettext(
              "Defaults to W<date> (e.g. W20260612). Same wean day pools together; override to split."
            )

          _ ->
            gettext("New batch — will be created with this id.")
        end

      batch ->
        gettext("Pooling into existing batch — %{n} head.", n: batch.quantity || 0)
    end
  end

  defp wn_state_text(:resolved), do: gettext("✓ Open farrowing found")
  defp wn_state_text(:not_found), do: gettext("⚠ No sow with this ear tag")

  defp wn_state_text(:no_open_farrowing),
    do: gettext("⚠ Sow has no open farrowing — record a farrowing first")

  defp wn_state_text(:empty), do: gettext("Type a sow ear tag to begin")
  defp wn_state_text(_), do: nil

  defp weaning_save_enabled?(nil), do: false
  defp weaning_save_enabled?(%{locked: true}), do: true
  defp weaning_save_enabled?(%{sow_state: :resolved}), do: true

  defp weaning_save_enabled?(%{sow_state: :not_found, backfill: bf, sow_tag: tag}) do
    tag not in [nil, ""] and bf.served_at not in [nil, ""] and
      bf.farrowed_at not in [nil, ""]
  end

  defp weaning_save_enabled?(%{sow_state: :no_open_farrowing, backfill: bf}) do
    bf.served_at not in [nil, ""] and bf.farrowed_at not in [nil, ""]
  end

  defp weaning_save_enabled?(_), do: false

  defp weaning_save_label(%{sow_state: :not_found}),
    do: gettext("Save weaning + register sow")

  defp weaning_save_label(%{sow_state: :no_open_farrowing}),
    do: gettext("Save weaning + backfill farrowing")

  defp weaning_save_label(_), do: gettext("Save")

  defp default_wn_backfill(scope, weaned_at) do
    case weaned_at do
      %Date{} = w ->
        farrowed = Date.add(w, -Breeding.lactation_days(scope))
        served = Date.add(farrowed, -Breeding.gestation_days(scope))
        dob = Date.add(served, -Breeding.minimum_sow_age_days(scope))

        %{
          breed: "",
          dob: to_string(dob),
          served_at: to_string(served),
          farrowed_at: to_string(farrowed),
          boar_tag: "",
          born_alive: ""
        }

      _ ->
        %{
          breed: "",
          dob: "",
          served_at: "",
          farrowed_at: "",
          boar_tag: "",
          born_alive: ""
        }
    end
  end

  defp merge_wn_backfill_params(socket, all, weaning_params) do
    wn = socket.assigns.wn
    scope = socket.assigns.current_scope

    if is_nil(wn) do
      socket
    else
      existing = wn.backfill || default_wn_backfill(scope, nil)
      weaned_at_input = Map.get(weaning_params, "weaned_at")

      farrowed_at_input = Map.get(all, "farrowed_at")

      farrowed_at =
        cond do
          is_binary(farrowed_at_input) and farrowed_at_input != "" -> farrowed_at_input
          existing.farrowed_at not in [nil, ""] -> existing.farrowed_at
          true -> derive_farrowed_from_weaned(scope, weaned_at_input)
        end

      served_at_input = Map.get(all, "served_at")

      served_at =
        cond do
          is_binary(served_at_input) and served_at_input != "" ->
            served_at_input

          existing.served_at not in [nil, ""] and farrowed_at == existing.farrowed_at ->
            existing.served_at

          true ->
            derive_served_from_farrowed(scope, farrowed_at)
        end

      dob_input = Map.get(all, "sow_dob")

      dob =
        cond do
          is_binary(dob_input) and dob_input != "" -> dob_input
          existing.dob not in [nil, ""] and served_at == existing.served_at -> existing.dob
          true -> derive_dob_from_served(scope, served_at)
        end

      backfill = %{
        breed: Map.get(all, "sow_breed", existing.breed) || "",
        dob: dob || "",
        served_at: served_at || "",
        farrowed_at: farrowed_at || "",
        boar_tag: Map.get(all, "boar_tag", existing.boar_tag) || "",
        born_alive: Map.get(all, "born_alive", existing.born_alive) || ""
      }

      assign(socket, wn: %{wn | backfill: backfill})
    end
  end

  defp derive_farrowed_from_weaned(scope, weaned_at) do
    case parse_date(weaned_at) do
      %Date{} = d -> to_string(Date.add(d, -Breeding.lactation_days(scope)))
      _ -> ""
    end
  end

  defp derive_served_from_farrowed(scope, farrowed_at) do
    case parse_date(farrowed_at) do
      %Date{} = d -> to_string(Date.add(d, -Breeding.gestation_days(scope)))
      _ -> ""
    end
  end

  defp derive_dob_from_served(scope, served_at) do
    case parse_date(served_at) do
      %Date{} = d -> to_string(Date.add(d, -Breeding.minimum_sow_age_days(scope)))
      _ -> ""
    end
  end

  defp parse_date(nil), do: nil
  defp parse_date(%Date{} = d), do: d

  defp parse_date(s) when is_binary(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  defp parse_date(_), do: nil

  defp do_save_weaning_backfill(socket, kind, weaning_params) do
    scope = socket.assigns.current_scope
    wn = socket.assigns.wn
    bf = wn.backfill

    # The farrowing happened in the past; default its pen_id to the sow's
    # destination pen (the operator already picked one for the weaning),
    # so the cascade has the required pen without forcing extra input.
    pen_id = presence(weaning_params["destination_pen_id"])

    attrs =
      weaning_params
      |> Map.put("served_at", bf.served_at)
      |> Map.put("farrowed_at", bf.farrowed_at)
      |> Map.put("pen_id", pen_id)
      |> Map.put("born_alive", presence(bf.born_alive) || weaning_params["weaned_count"] || "0")
      |> Map.put("boar_id", resolve_boar_id(scope, bf.boar_tag))

    mode =
      case kind do
        :new_sow ->
          {:new_sow,
           %{
             "ear_tag" => wn.sow_tag,
             "breed" => presence(bf.breed),
             "dob" => presence(bf.dob)
           }}

        :existing_sow ->
          sow = Animals.find_by_ear_tag(scope, wn.sow_tag)
          {:existing_sow, sow && sow.id}
      end

    case Breeding.record_weaning_with_backfill(scope, mode, attrs) do
      {:ok, _weaning, _batch} ->
        {:noreply,
         socket
         |> close_form()
         |> load_rows()
         |> put_flash(
           :info,
           gettext("Weaning recorded with backfilled farrowing (flagged for review).")
         )}

      {:error, :weaned_at_required} ->
        {:noreply, put_flash(socket, :error, gettext("Weaned at is required."))}

      {:error, :served_at_required} ->
        {:noreply, put_flash(socket, :error, gettext("Service date is required for backfill."))}

      {:error, :farrowed_at_required} ->
        {:noreply, put_flash(socket, :error, gettext("Farrowed at is required for backfill."))}

      {:error, :gestation_out_of_range} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Farrowed date must be within 3 days of the 114-day gestation.")
         )}

      {:error, :sow_not_found} ->
        {:noreply, put_flash(socket, :error, gettext("Sow not found for backfill."))}

      {:error, :batch_tag_required} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Enter a weaner batch id to pool into (or a new id for a fresh batch).")
         )}

      {:error, {:sow, cs}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Could not register sow: %{err}", err: Shared.format_cs_error(cs))
         )}

      {:error, {:service, cs}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Could not create service: %{err}", err: Shared.format_cs_error(cs))
         )}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Could not save backfilled weaning: %{err}",
             err: Shared.format_cs_error(cs)
           )
         )}

      {:error, other} ->
        {:noreply, put_flash(socket, :error, inspect(other))}
    end
  end

  defp resolve_boar_id(_scope, nil), do: nil
  defp resolve_boar_id(_scope, ""), do: nil

  defp resolve_boar_id(scope, tag) when is_binary(tag) do
    case Animals.find_by_ear_tag(scope, String.trim(tag)) do
      %{id: id} -> id
      _ -> nil
    end
  end

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(s) when is_binary(s), do: s
  defp presence(other), do: other

  defp print_path(slug, filters, sort, dir) do
    query =
      %{
        "q" => filters.q,
        "age" => filters.age,
        "pen_id" => filters.pen_id,
        "pen_search" => filters.pen_search,
        "min_parity" => filters.min_parity,
        "max_parity" => filters.max_parity,
        "sort" => sort,
        "dir" => dir
      }
      |> Shared.prune_query()

    base = ~p"/farms/#{slug}/breeding/lactating/print"

    case query do
      m when map_size(m) == 0 -> base
      m -> base <> "?" <> URI.encode_query(m)
    end
  end

  defp resolve_wn_sow(socket, sow_tag) do
    scope = socket.assigns.current_scope
    wn = socket.assigns.wn
    tag = (sow_tag || "") |> to_string() |> String.trim()

    cond do
      tag == "" ->
        assign(socket,
          wn: %{wn | sow_tag: "", sow_state: :empty, resolved_farrowing: nil},
          form_target: nil,
          form_sow_tag: nil,
          form_born_alive: nil,
          form_surviving: nil
        )

      true ->
        case Animals.find_by_ear_tag(scope, tag) do
          nil ->
            assign(socket,
              wn: %{wn | sow_tag: tag, sow_state: :not_found, resolved_farrowing: nil},
              form_target: nil,
              form_sow_tag: nil,
              form_born_alive: nil,
              form_surviving: nil
            )

          sow ->
            case Breeding.latest_open_farrowing_for_sow(scope, sow.id) do
              nil ->
                assign(socket,
                  wn: %{
                    wn
                    | sow_tag: tag,
                      sow_state: :no_open_farrowing,
                      resolved_farrowing: nil
                  },
                  form_target: nil,
                  form_sow_tag: sow.ear_tag,
                  form_born_alive: nil,
                  form_surviving: nil
                )

              farrowing ->
                surviving = Breeding.surviving_piglet_count(farrowing)

                assign(socket,
                  wn: %{
                    wn
                    | sow_tag: tag,
                      sow_state: :resolved,
                      resolved_farrowing: farrowing
                  },
                  form_target: farrowing,
                  form_sow_tag: sow.ear_tag,
                  form_born_alive: farrowing.born_alive,
                  form_surviving: surviving
                )
            end
        end
    end
  end
end
