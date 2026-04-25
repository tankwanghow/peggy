defmodule PeggyWeb.FarmLive.Breeding.Gestating do
  @moduledoc """
  Gestating tab of the Breeding section. Owns the service-create form
  (with back-fill cascade), farrowing form, close-service form, and
  the gestating sows list.
  """
  use PeggyWeb, :live_view

  alias Peggy.{Breeding, Animals, Policy}
  alias Peggy.Breeding.{Service, Farrowing}
  alias PeggyWeb.FarmLive.Breeding.Shared

  @per_page Shared.per_page()

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-6xl">
        <.header>
          {gettext("Gestating")}
          <:subtitle>{gettext("Services awaiting farrowing")}</:subtitle>
        </.header>

        <section class="mt-4">
          <form
            id="gestating-filters"
            phx-change="filter_gestating"
            phx-submit="filter_gestating"
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
                <span class="label-text text-xs">{gettext("Due window")}</span>
              </div>
              <select name="window" class="select select-sm select-bordered">
                <option value="all" selected={@filters.window == "all"}>{gettext("All")}</option>
                <option value="7" selected={@filters.window == "7"}>
                  {gettext("≤ 7 days")}
                </option>
                <option value="14" selected={@filters.window == "14"}>
                  {gettext("≤ 14 days")}
                </option>
                <option value="overdue" selected={@filters.window == "overdue"}>
                  {gettext("Overdue")}
                </option>
              </select>
            </label>
            <label class="form-control w-28">
              <div class="label py-1">
                <span class="label-text text-xs">{gettext("Type")}</span>
              </div>
              <select name="service_type" class="select select-sm select-bordered">
                <option value="all" selected={@filters.service_type == "all"}>
                  {gettext("All")}
                </option>
                <option value="ai" selected={@filters.service_type == "ai"}>
                  {gettext("AI")}
                </option>
                <option value="natural" selected={@filters.service_type == "natural"}>
                  {gettext("Natural")}
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
                  <th class="py-2">{gettext("Sow")}</th>
                  <th class="py-2">{gettext("Pen")}</th>
                  <th class="py-2">{gettext("Boar")}</th>
                  <th class="py-2 text-right">{gettext("Parity")}</th>
                  <th class="py-2">{gettext("Served")}</th>
                  <th class="py-2">{gettext("Expected")}</th>
                  <th class="py-2 text-right">{gettext("Left(d)")}</th>
                  <th :if={@can_record} class="py-2"></th>
                </tr>
              </thead>
              <tbody id="gestating-rows" phx-update="stream">
                <tr
                  :for={{dom_id, entry} <- @streams.gestating}
                  id={dom_id}
                  class="border-t border-base-200"
                >
                  <td class="py-2 font-mono font-semibold">
                    <.link
                      navigate={
                        ~p"/farms/#{@current_scope.farm.slug}/animals/#{entry.service.sow_id}"
                      }
                      class="text-primary underline underline-offset-2 decoration-dotted hover:decoration-solid"
                    >
                      {entry.service.sow.ear_tag}
                    </.link>
                  </td>
                  <td class="py-2 font-mono text-base-content/70">
                    {sow_pen_label(entry.service.sow)}
                  </td>
                  <td class="py-2 font-mono">
                    {entry.service.boar && entry.service.boar.ear_tag}
                  </td>
                  <td class="py-2 text-right font-mono">{entry.parity}</td>
                  <td class="py-2">{entry.service.served_at}</td>
                  <td class="py-2">{entry.expected_farrow_date}</td>
                  <td class={[
                    "py-2 text-right font-mono",
                    days_left(entry) <= 7 && "text-warning font-bold",
                    days_left(entry) <= 0 && "text-error font-bold"
                  ]}>
                    {days_left(entry)}
                  </td>
                  <td :if={@can_record} class="py-2 text-right">
                    <button
                      phx-click="new_farrowing"
                      phx-value-service-id={entry.service.id}
                      class="btn btn-ghost btn-sm"
                    >
                      {gettext("Farrow")}
                    </button>
                    <button
                      phx-click="close_service_prompt"
                      phx-value-service-id={entry.service.id}
                      class="btn btn-ghost btn-sm text-base-content/50"
                    >
                      {gettext("Close")}
                    </button>
                    <button
                      phx-click="delete_service"
                      phx-value-service-id={entry.service.id}
                      data-confirm={gettext("Delete this service? The sow will be reverted to open.")}
                      class="btn btn-ghost btn-sm text-error/70"
                      title={gettext("Delete service")}
                    >
                      <.icon name="hero-trash" class="size-4" />
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
            <p :if={@total == 0} class="mt-2 text-sm text-base-content/60">
              {gettext("No gestating sows match the filters.")}
            </p>
          </div>

          <.infinite_scroll
            has_more={@has_more}
            total={@total}
            id="gestating-sentinel"
          />
        </section>

        <%!-- Service form modal (with back-fill cascade) --%>
        <Shared.modal
          :if={@form_mode == :service}
          title={gettext("Record Service")}
          on_cancel="cancel"
        >
          <form
            id="service-form"
            phx-change="validate_service"
            phx-submit="save_service"
            phx-debounce="300"
            class="grid grid-cols-2 gap-x-4 gap-y-3"
          >
            <div class="col-span-2">
              <label class="label" for="service-sow-ear-tag">
                <span class="label-text">{gettext("Sow ear tag")}</span>
              </label>
              <input
                type="text"
                id="service-sow-ear-tag"
                name="sow_ear_tag"
                value={@svc.sow_ear_tag}
                phx-debounce="300"
                autocomplete="off"
                spellcheck="false"
                class={[
                  "input input-bordered w-full font-mono",
                  sow_input_class(@svc.sow_state)
                ]}
                placeholder={gettext("e.g. SOW1234")}
              />
              <p class={[
                "mt-1 text-xs",
                @svc.sow_state == :existing && "text-success",
                @svc.sow_state == :new && "text-warning",
                @svc.sow_state == :similar && "text-error",
                @svc.sow_state == :similar_overridable && "text-warning",
                @svc.sow_state == :not_serviceable && "text-error",
                @svc.sow_state == :empty && "text-base-content/40"
              ]}>
                {sow_state_text(@svc)}
              </p>
            </div>

            <div
              :if={@svc.sow_state == :new or @svc.sow_state == :similar_overridable}
              class="col-span-2 rounded border border-warning/40 bg-warning/5 p-3"
            >
              <p class="text-sm font-semibold text-warning mb-2">
                {gettext("New sow — will be registered on save")}
              </p>
              <div class="grid grid-cols-2 gap-x-3 gap-y-2">
                <div>
                  <label class="label">
                    <span class="label-text">{gettext("Breed")}</span>
                  </label>
                  <input
                    type="text"
                    name="backfill_sow[breed]"
                    value={@svc.backfill[:breed]}
                    class="input input-bordered w-full"
                    placeholder={gettext("e.g. Large White")}
                  />
                </div>
                <div>
                  <label class="label">
                    <span class="label-text">{gettext("Date of birth")}</span>
                  </label>
                  <input
                    type="date"
                    name="backfill_sow[dob]"
                    value={@svc.backfill[:dob] || @svc.default_dob}
                    class="input input-bordered w-full"
                  />
                </div>
              </div>
              <p class="mt-2 text-xs text-base-content/60">
                {gettext(
                  "Defaults to female sow, status open, DOB = served_at − 1 year. Marked needs-review."
                )}
              </p>
            </div>

            <div
              :if={@svc.sow_state in [:similar, :similar_overridable]}
              class={[
                "col-span-2 rounded border p-3",
                @svc.sow_state == :similar && "border-error/40 bg-error/5",
                @svc.sow_state == :similar_overridable && "border-warning/40 bg-warning/5"
              ]}
            >
              <p class={[
                "text-sm font-semibold",
                @svc.sow_state == :similar && "text-error",
                @svc.sow_state == :similar_overridable && "text-warning"
              ]}>
                {gettext("Did you mean one of these?")}
              </p>
              <div class="mt-2 flex flex-wrap gap-2">
                <button
                  :for={tag <- @svc.similar_tags}
                  type="button"
                  phx-click="pick_similar_tag"
                  phx-value-tag={tag}
                  class="btn btn-sm btn-outline btn-error font-mono"
                >
                  {tag}
                </button>
              </div>
              <label class="mt-3 flex items-center gap-2 cursor-pointer">
                <input type="hidden" name="backfill_sow[force_create]" value="false" />
                <input
                  type="checkbox"
                  name="backfill_sow[force_create]"
                  value="true"
                  checked={@svc.force_create}
                  class="checkbox checkbox-sm"
                />
                <span class="text-sm">
                  {gettext("Create anyway — this is a different sow")}
                </span>
              </label>
            </div>

            <div>
              <label class="label">
                <span class="label-text">{gettext("Service type")}</span>
              </label>
              <select name="service_type" class="select select-bordered w-full">
                <option value="ai" selected={@svc.service_type == "ai"}>
                  {gettext("AI")}
                </option>
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
                id="service-boar-picker"
                label={gettext("Boar")}
                name="boar_id"
                value={@svc.boar_id}
                items={@ac.boar_items}
                selected_label={@ac.boar_label}
                class="w-full input font-mono"
                placeholder={gettext("Search by ear tag...")}
              />
            </div>

            <div class="col-span-2">
              <.autocomplete
                id={"service-pen-picker-#{@svc.resolved_sow_id || "none"}"}
                label={gettext("Service pen (optional)")}
                name="pen_id"
                value={@svc.pen_id}
                items={@ac.pen_items}
                selected_label={@ac.pen_label}
                class="w-full input font-mono"
                placeholder={gettext("Search pens...")}
              />
              <p class="mt-1 text-xs text-base-content/60">
                {gettext(
                  "If set: new sow placed, or existing sow transferred when different from current pen."
                )}
              </p>
            </div>

            <div class="col-span-2">
              <label class="label">
                <span class="label-text">{gettext("Notes")}</span>
              </label>
              <textarea
                name="notes"
                rows="2"
                class="textarea textarea-bordered w-full"
              >{@svc.notes}</textarea>
            </div>

            <p :if={@svc.error_message} class="col-span-2 text-sm text-error">
              {@svc.error_message}
            </p>

            <div class="col-span-2 flex gap-2 justify-end pt-2">
              <button type="button" phx-click="cancel" class="btn btn-ghost">
                {gettext("Cancel")}
              </button>
              <.button
                class="btn btn-primary"
                phx-disable-with={gettext("Saving...")}
                disabled={not service_save_enabled?(@svc)}
              >
                {service_save_label(@svc)}
              </.button>
            </div>
          </form>
        </Shared.modal>

        <%!-- Farrowing form modal --%>
        <Shared.modal
          :if={@form_mode == :farrowing}
          title={gettext("Record Farrowing")}
          on_cancel="cancel"
        >
          <.form
            for={@form}
            id="farrowing-form"
            phx-submit="save_farrowing"
            phx-change="validate_farrowing"
            class="grid grid-cols-2 gap-x-4 gap-y-1"
          >
            <%!-- Sow tag: read-only when launched from a row, editable at top-level --%>
            <div :if={@frw && @frw.locked} class="col-span-2 mb-2 text-sm">
              <span class="text-base-content/60">{gettext("Sow:")}</span>
              <span class="font-mono font-semibold">{@form_sow_tag}</span>
            </div>
            <div :if={@frw && not @frw.locked} class="col-span-2">
              <label class="form-control w-full">
                <div class="label py-1">
                  <span class="label-text">{gettext("Sow ear tag")}</span>
                </div>
                <input
                  type="text"
                  name="sow_tag"
                  value={@frw.sow_tag}
                  phx-debounce="300"
                  autocomplete="off"
                  placeholder={gettext("Type sow ear tag…")}
                  class={[
                    "input input-bordered font-mono",
                    @frw.sow_state == :resolved && "border-success focus:border-success",
                    @frw.sow_state in [:not_found, :no_open_service] &&
                      "border-error focus:border-error"
                  ]}
                />
                <p class={[
                  "label pt-1 text-xs",
                  @frw.sow_state == :resolved && "text-success",
                  @frw.sow_state in [:not_found, :no_open_service] && "text-error",
                  @frw.sow_state == :empty && "text-base-content/40"
                ]}>
                  {frw_state_text(@frw.sow_state)}
                </p>
              </label>
            </div>

            <%!-- Sanity check panel --%>
            <div
              :if={@frw && @frw.resolved_service}
              class="col-span-2 mb-2 rounded border border-base-300 bg-base-200/50 p-3 text-sm"
            >
              <div class="font-semibold mb-1">{gettext("Open service to farrow against")}</div>
              <dl class="grid grid-cols-2 gap-x-4 gap-y-0.5 text-xs">
                <dt class="text-base-content/60">{gettext("Served at")}</dt>
                <dd class="font-mono">{@frw.resolved_service.served_at}</dd>
                <dt class="text-base-content/60">{gettext("Service type")}</dt>
                <dd>{@frw.resolved_service.service_type}</dd>
                <dt class="text-base-content/60">{gettext("Boar")}</dt>
                <dd class="font-mono">
                  {@frw.resolved_service.boar && @frw.resolved_service.boar.ear_tag}
                </dd>
                <dt class="text-base-content/60">{gettext("Expected farrow")}</dt>
                <dd class="font-mono">{expected_farrow(@frw.resolved_service)}</dd>
              </dl>
            </div>

            <%!-- Backfill panel (no open service, or sow unknown) --%>
            <div
              :if={@frw && @frw.sow_state in [:not_found, :no_open_service]}
              class="col-span-2 mb-2 rounded border border-warning/40 bg-warning/5 p-3 text-sm"
            >
              <div class="font-semibold text-warning mb-1">
                {if @frw.sow_state == :not_found,
                  do: gettext("Register new sow + backfill service"),
                  else: gettext("Backfill open service")}
              </div>
              <p class="text-xs text-base-content/70 mb-2">
                {gettext(
                  "This will create an inferred AI service (and sow, if unknown) flagged for review."
                )}
              </p>

              <div :if={@frw.sow_state == :not_found} class="grid grid-cols-2 gap-x-4 gap-y-1 mb-2">
                <label class="form-control">
                  <div class="label py-1">
                    <span class="label-text text-xs">{gettext("Breed (optional)")}</span>
                  </div>
                  <input
                    type="text"
                    name="sow_breed"
                    value={@frw.backfill.breed}
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
                    value={@frw.backfill.dob}
                    class="input input-sm input-bordered"
                  />
                </label>
              </div>

              <div class="grid grid-cols-2 gap-x-4 gap-y-1">
                <label class="form-control">
                  <div class="label py-1">
                    <span class="label-text text-xs">
                      {gettext("Served at (defaults to farrowed − 114d)")}
                    </span>
                  </div>
                  <input
                    type="date"
                    name="served_at"
                    value={@frw.backfill.served_at}
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
                    value={@frw.backfill.boar_tag}
                    class="input input-sm input-bordered font-mono"
                  />
                </label>
              </div>
            </div>
            <.input
              field={@form[:farrowed_at]}
              type="date"
              label={gettext("Farrowed at")}
            />
            <.autocomplete
              id="farrowing-pen-picker"
              label={gettext("Farrowing pen")}
              name="farrowing[pen_id]"
              value={Shared.fv(@form, :pen_id)}
              items={@ac.pen_items}
              selected_label={@ac.pen_label}
              class="w-full input font-mono"
              placeholder={gettext("Search pens...")}
            />
            <.input
              field={@form[:born_alive]}
              type="number"
              label={gettext("Born alive")}
              min="0"
            />
            <.input
              field={@form[:stillborn]}
              type="number"
              label={gettext("Stillborn")}
              min="0"
            />
            <.input
              field={@form[:mummified]}
              type="number"
              label={gettext("Mummified")}
              min="0"
            />
            <.input
              field={@form[:total_birth_weight_g]}
              type="number"
              label={gettext("Total birth weight (g)")}
              min="0"
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
                disabled={not farrowing_save_enabled?(@frw)}
              >
                {farrowing_save_label(@frw)}
              </.button>
            </div>
          </.form>
        </Shared.modal>

        <%!-- Close service modal --%>
        <Shared.modal
          :if={@form_mode == :close_service}
          title={gettext("Close Service")}
          on_cancel="cancel"
        >
          <div class="mb-3 text-sm">
            <span class="text-base-content/60">{gettext("Sow:")}</span>
            <span class="font-mono font-semibold">{@form_sow_tag}</span>
          </div>
          <.form
            for={@form}
            id="close-service-form"
            phx-submit="save_close_service"
            phx-change="validate_close_service"
            class="grid grid-cols-2 gap-x-4 gap-y-1"
          >
            <.input
              field={@form[:result]}
              type="select"
              label={gettext("Result")}
              options={[
                {gettext("Abortion"), "abortion"},
                {gettext("Death"), "death"},
                {gettext("Cull"), "cull"}
              ]}
            />
            <.input
              field={@form[:result_at]}
              type="date"
              label={gettext("Date")}
            />
            <div class="col-span-2">
              <.input
                field={@form[:result_notes]}
                type="textarea"
                label={gettext("Notes")}
              />
            </div>
            <div class="col-span-2 flex gap-2 justify-end">
              <button type="button" phx-click="cancel" class="btn btn-ghost">
                {gettext("Cancel")}
              </button>
              <.button class="btn btn-error" phx-disable-with={gettext("Closing...")}>
                {gettext("Close Service")}
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
       svc: nil,
       frw: nil,
       ac: Shared.default_ac(scope),
       per_page: @per_page
     )
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

    socket =
      socket
      |> assign(filters: filters, page: 1)
      |> load_rows()
      |> maybe_open_from_params(params)

    {:noreply, socket}
  end

  defp maybe_open_from_params(socket, %{"new" => "service"}) do
    if socket.assigns.can_record do
      {:noreply, s} = handle_event("new_service", %{}, socket)
      s
    else
      socket
    end
  end

  defp maybe_open_from_params(socket, %{"new" => "farrowing"}) do
    if socket.assigns.can_record do
      {:noreply, s} = handle_event("new_top_farrowing", %{}, socket)
      s
    else
      socket
    end
  end

  defp maybe_open_from_params(socket, _), do: socket

  # ── Events ─────────────────────────────────────────────────────────

  @impl true
  def handle_event("new_service", _, socket) do
    today = Date.utc_today()

    {:noreply,
     socket
     |> assign(
       form_mode: :service,
       form_target: nil,
       ac: Shared.default_ac(socket.assigns.current_scope),
       svc: %{
         sow_ear_tag: "",
         sow_state: :empty,
         not_serviceable_status: nil,
         similar_tags: [],
         resolved_sow_id: nil,
         force_create: false,
         backfill: %{},
         service_type: "ai",
         served_at: to_string(today),
         boar_id: nil,
         pen_id: nil,
         notes: nil,
         default_dob: to_string(Date.add(today, -Breeding.minimum_sow_age_days())),
         error_message: nil
       }
     )}
  end

  def handle_event("validate_service", params, socket) do
    {:noreply,
     socket
     |> update_svc_from_params(params)
     |> resolve_svc_sow()}
  end

  def handle_event("pick_similar_tag", %{"tag" => tag}, socket) do
    svc = %{socket.assigns.svc | sow_ear_tag: tag, force_create: false}
    {:noreply, socket |> assign(svc: svc) |> resolve_svc_sow()}
  end

  def handle_event("save_service", params, socket) do
    if socket.assigns.can_record do
      socket = socket |> update_svc_from_params(params) |> resolve_svc_sow()
      do_save_service(socket)
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("new_farrowing", %{"service-id" => id}, socket) do
    scope = socket.assigns.current_scope

    service =
      Breeding.get_service!(scope, String.to_integer(id)) |> Peggy.Repo.preload([:boar])

    sow = Animals.get_animal!(scope, service.sow_id)

    cs =
      Breeding.change_farrowing(%Farrowing{
        farrowed_at: Date.utc_today(),
        born_alive: 0,
        stillborn: 0,
        mummified: 0
      })

    ac =
      Shared.default_ac(scope)
      |> Shared.maybe_preselect_pen(scope, sow)

    frw = %{
      locked: true,
      sow_tag: sow.ear_tag,
      sow_state: :resolved,
      resolved_service: service,
      backfill: default_backfill(Date.utc_today())
    }

    {:noreply,
     assign(socket,
       form_mode: :farrowing,
       form: to_form(cs, as: :farrowing),
       form_target: service,
       form_sow_tag: sow.ear_tag,
       frw: frw,
       ac: ac
     )}
  end

  def handle_event("new_top_farrowing", _, socket) do
    scope = socket.assigns.current_scope

    cs =
      Breeding.change_farrowing(%Farrowing{
        farrowed_at: Date.utc_today(),
        born_alive: 0,
        stillborn: 0,
        mummified: 0
      })

    frw = %{
      locked: false,
      sow_tag: "",
      sow_state: :empty,
      resolved_service: nil,
      backfill: default_backfill(Date.utc_today())
    }

    {:noreply,
     assign(socket,
       form_mode: :farrowing,
       form: to_form(cs, as: :farrowing),
       form_target: nil,
       form_sow_tag: nil,
       frw: frw,
       ac: Shared.default_ac(scope)
     )}
  end

  def handle_event("validate_farrowing", %{"farrowing" => params} = all, socket) do
    cs = Breeding.change_farrowing(%Farrowing{}, params) |> Map.put(:action, :validate)
    socket = assign(socket, :form, to_form(cs, as: :farrowing))

    socket = merge_backfill_params(socket, all, params)

    sow_tag = all["sow_tag"]

    socket =
      if (socket.assigns.frw && not socket.assigns.frw.locked) and not is_nil(sow_tag) do
        resolve_frw_sow(socket, sow_tag)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("save_farrowing", %{"farrowing" => params}, socket) do
    if socket.assigns.can_record do
      frw = socket.assigns.frw

      cond do
        is_nil(frw) ->
          {:noreply, put_flash(socket, :error, gettext("Form state lost; please retry."))}

        frw.locked ->
          do_save_farrowing(socket, socket.assigns.form_target, params)

        frw.sow_state == :resolved ->
          do_save_farrowing(socket, frw.resolved_service, params)

        frw.sow_state == :not_found ->
          do_save_farrowing_backfill(socket, :new_sow, params)

        frw.sow_state == :no_open_service ->
          do_save_farrowing_backfill(socket, :existing_sow, params)

        true ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("Type a sow ear tag before saving.")
           )}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("close_service_prompt", %{"service-id" => id}, socket) do
    scope = socket.assigns.current_scope
    service = Breeding.get_service!(scope, String.to_integer(id))

    cs =
      Service.close_changeset(service, %{
        "result" => "abortion",
        "result_at" => Date.utc_today()
      })
      |> Map.put(:action, nil)

    {:noreply,
     assign(socket,
       form_mode: :close_service,
       form: to_form(cs, as: :service),
       form_target: service,
       form_sow_tag: service.sow.ear_tag
     )}
  end

  def handle_event("validate_close_service", %{"service" => params}, socket) do
    service = socket.assigns.form_target
    cs = Service.close_changeset(service, params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(cs, as: :service))}
  end

  def handle_event("save_close_service", %{"service" => params}, socket) do
    if socket.assigns.can_record do
      service = socket.assigns.form_target
      result = Map.get(params, "result")

      case Breeding.close_service(socket.assigns.current_scope, service, result, params) do
        {:ok, _} ->
          {:noreply,
           socket
           |> close_form()
           |> load_rows()
           |> put_flash(:info, gettext("Service closed."))}

        {:error, :already_closed} ->
          {:noreply,
           socket
           |> close_form()
           |> load_rows()
           |> put_flash(:error, gettext("Service is already closed."))}

        {:error, cs} ->
          {:noreply, assign(socket, :form, to_form(cs, as: :service))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("cancel", _, socket), do: {:noreply, close_form(socket)}

  def handle_event("delete_service", %{"service-id" => id}, socket) do
    scope = socket.assigns.current_scope

    if socket.assigns.can_record do
      service = Breeding.get_service!(scope, String.to_integer(id))

      case Breeding.delete_service(scope, service) do
        {:ok, _} ->
          {:noreply,
           socket
           |> load_rows()
           |> put_flash(:info, gettext("Service deleted. Restore from the Deleted tab."))}

        {:error, :service_has_closed_outcome} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("Cannot delete a service with a recorded outcome.")
           )}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not delete service."))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("filter_gestating", params, socket) do
    query = %{
      "q" => params["q"] || "",
      "window" => params["window"] || "all",
      "service_type" => params["service_type"] || "all",
      "pen_search" => params["pen_search"] || "",
      "min_parity" => params["min_parity"] || "",
      "max_parity" => params["max_parity"] || ""
    }

    {:noreply, push_patch(socket, to: Shared.tab_path(socket, "gestating", query))}
  end

  def handle_event("load_more", _, socket) do
    {:noreply, append_rows(socket)}
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp do_save_farrowing(socket, service, params) do
    case Breeding.record_farrowing(socket.assigns.current_scope, service, params) do
      {:ok, _farrowing} ->
        {:noreply,
         socket
         |> close_form()
         |> load_rows()
         |> put_flash(:info, gettext("Farrowing recorded."))}

      {:error, :service_already_closed} ->
        {:noreply,
         socket
         |> close_form()
         |> load_rows()
         |> put_flash(:error, gettext("Service is already closed."))}

      {:error, :sow_not_served} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Sow status must be \"served\" to record farrowing.")
         )}

      {:error, :gestation_out_of_range} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Farrowed date must be within 3 days of the 114-day gestation.")
         )}

      {:error, cs} ->
        {:noreply, assign(socket, :form, to_form(cs, as: :farrowing))}
    end
  end

  defp resolve_frw_sow(socket, sow_tag) do
    scope = socket.assigns.current_scope
    frw = socket.assigns.frw
    tag = (sow_tag || "") |> String.trim()

    {new_frw, new_ac} =
      cond do
        tag == "" ->
          {%{frw | sow_tag: "", sow_state: :empty, resolved_service: nil},
           Shared.default_ac(scope)}

        true ->
          case Animals.find_by_ear_tag(scope, tag) do
            nil ->
              {%{frw | sow_tag: tag, sow_state: :not_found, resolved_service: nil},
               Shared.default_ac(scope)}

            sow ->
              case Breeding.latest_open_service_for_sow(scope, sow.id) do
                nil ->
                  {%{frw | sow_tag: tag, sow_state: :no_open_service, resolved_service: nil},
                   Shared.default_ac(scope)}

                service ->
                  ac = Shared.default_ac(scope) |> Shared.maybe_preselect_pen(scope, sow)

                  {%{frw | sow_tag: tag, sow_state: :resolved, resolved_service: service}, ac}
              end
          end
      end

    assign(socket, frw: new_frw, ac: new_ac)
  end

  defp default_backfill(farrowed_at) do
    {served_at_s, dob_s} =
      case farrowed_at do
        %Date{} = d ->
          served = Date.add(d, -Breeding.gestation_days())
          dob = Date.add(served, -Breeding.minimum_sow_age_days())
          {to_string(served), to_string(dob)}

        _ ->
          {"", ""}
      end

    %{breed: "", dob: dob_s, served_at: served_at_s, boar_tag: ""}
  end

  defp merge_backfill_params(socket, all, farrowing_params) do
    frw = socket.assigns.frw
    if is_nil(frw), do: socket, else: do_merge_backfill(socket, frw, all, farrowing_params)
  end

  defp do_merge_backfill(socket, frw, all, farrowing_params) do
    existing = frw.backfill || default_backfill(nil)

    served_at_input = Map.get(all, "served_at")

    served_at =
      cond do
        is_binary(served_at_input) and served_at_input != "" -> served_at_input
        existing.served_at not in [nil, ""] -> existing.served_at
        true -> derive_served_from_farrowed(farrowing_params)
      end

    dob_input = Map.get(all, "sow_dob")

    dob =
      cond do
        is_binary(dob_input) and dob_input != "" -> dob_input
        existing.dob not in [nil, ""] and served_at == existing.served_at -> existing.dob
        true -> derive_dob_from_served(served_at)
      end

    backfill = %{
      breed: Map.get(all, "sow_breed", existing.breed) || "",
      dob: dob || "",
      served_at: served_at || "",
      boar_tag: Map.get(all, "boar_tag", existing.boar_tag) || ""
    }

    assign(socket, frw: %{frw | backfill: backfill})
  end

  defp derive_dob_from_served(served_at) do
    case parse_date(served_at) do
      %Date{} = d -> to_string(Date.add(d, -Breeding.minimum_sow_age_days()))
      _ -> ""
    end
  end

  defp derive_served_from_farrowed(params) do
    case parse_date(Map.get(params, "farrowed_at")) do
      %Date{} = d -> to_string(Date.add(d, -Breeding.gestation_days()))
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

  defp do_save_farrowing_backfill(socket, kind, farrowing_params) do
    scope = socket.assigns.current_scope
    frw = socket.assigns.frw
    bf = frw.backfill

    attrs =
      farrowing_params
      |> Map.put("served_at", bf.served_at)
      |> Map.put("boar_id", resolve_boar_id(scope, bf.boar_tag))

    mode =
      case kind do
        :new_sow ->
          {:new_sow,
           %{
             "ear_tag" => frw.sow_tag,
             "breed" => Shared.presence(bf.breed),
             "dob" => Shared.presence(bf.dob)
           }}

        :existing_sow ->
          sow = Animals.find_by_ear_tag(scope, frw.sow_tag)
          {:existing_sow, sow && sow.id}
      end

    case Breeding.record_farrowing_with_backfill(scope, mode, attrs) do
      {:ok, _farrowing} ->
        {:noreply,
         socket
         |> close_form()
         |> load_rows()
         |> put_flash(
           :info,
           gettext("Farrowing recorded with backfilled service (flagged for review).")
         )}

      {:error, :served_at_required} ->
        {:noreply, put_flash(socket, :error, gettext("Service date is required for backfill."))}

      {:error, :farrowed_at_required} ->
        {:noreply, put_flash(socket, :error, gettext("Farrowed at is required."))}

      {:error, :gestation_out_of_range} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Farrowed date must be within 3 days of the 114-day gestation.")
         )}

      {:error, :sow_not_found} ->
        {:noreply, put_flash(socket, :error, gettext("Sow not found for backfill."))}

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
        {:noreply, assign(socket, :form, to_form(cs, as: :farrowing))}

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

  defp farrowing_save_enabled?(nil), do: false
  defp farrowing_save_enabled?(%{locked: true}), do: true
  defp farrowing_save_enabled?(%{sow_state: :resolved}), do: true

  defp farrowing_save_enabled?(%{sow_state: :not_found, backfill: bf, sow_tag: tag}) do
    tag not in [nil, ""] and bf.served_at not in [nil, ""]
  end

  defp farrowing_save_enabled?(%{sow_state: :no_open_service, backfill: bf}) do
    bf.served_at not in [nil, ""]
  end

  defp farrowing_save_enabled?(_), do: false

  defp farrowing_save_label(%{sow_state: :not_found}),
    do: gettext("Save farrowing + register sow")

  defp farrowing_save_label(%{sow_state: :no_open_service}),
    do: gettext("Save farrowing + backfill service")

  defp farrowing_save_label(_), do: gettext("Save")

  defp do_save_service(socket) do
    svc = socket.assigns.svc
    scope = socket.assigns.current_scope

    cond do
      svc.sow_state == :empty ->
        {:noreply,
         assign(socket, svc: %{svc | error_message: gettext("Sow ear tag is required.")})}

      svc.sow_state == :similar ->
        {:noreply,
         assign(socket,
           svc: %{
             svc
             | error_message:
                 gettext("Pick an existing tag or tick \"Create anyway\" to override.")
           }
         )}

      svc.sow_state == :not_serviceable ->
        {:noreply,
         assign(socket,
           svc: %{
             svc
             | error_message:
                 gettext("Sow is %{status} — cannot record a new service.",
                   status: svc.not_serviceable_status
                 )
           }
         )}

      true ->
        attrs = build_service_attrs(svc)

        case Breeding.record_service_with_backfill(scope, attrs) do
          {:ok, %{inferred?: inferred?, sow: sow}} ->
            msg =
              if inferred?,
                do: gettext("Service recorded — new sow %{tag} registered.", tag: sow.ear_tag),
                else: gettext("Service recorded for %{tag}.", tag: sow.ear_tag)

            {:noreply,
             socket
             |> close_form()
             |> load_rows()
             |> put_flash(:info, msg)}

          {:error, {:similar_tag, tags}} ->
            {:noreply,
             assign(socket,
               svc: %{
                 svc
                 | sow_state: :similar,
                   similar_tags: tags,
                   error_message: gettext("Tag is too similar to an existing sow.")
               }
             )}

          {:error, :sow_not_found} ->
            {:noreply, assign(socket, svc: %{svc | error_message: gettext("Sow tag not found.")})}

          {:error, %Ecto.Changeset{} = cs} ->
            {:noreply, assign(socket, svc: %{svc | error_message: Shared.format_cs_error(cs)})}

          {:error, other} ->
            {:noreply, assign(socket, svc: %{svc | error_message: inspect(other)})}
        end
    end
  end

  defp update_svc_from_params(socket, params) do
    svc = socket.assigns.svc
    backfill_params = Map.get(params, "backfill_sow", %{})

    backfill = %{
      breed: Shared.presence(Map.get(backfill_params, "breed")),
      dob: Shared.presence(Map.get(backfill_params, "dob"))
    }

    force_create = Shared.truthy?(Map.get(backfill_params, "force_create"))
    service_type = Map.get(params, "service_type", svc.service_type)

    boar_id =
      case Integer.parse(Map.get(params, "boar_id", "") || "") do
        {i, ""} -> i
        _ -> nil
      end

    pen_id =
      case Integer.parse(Map.get(params, "pen_id", "") || "") do
        {i, ""} -> i
        _ -> nil
      end

    svc = %{
      svc
      | sow_ear_tag:
          params |> Map.get("sow_ear_tag", svc.sow_ear_tag) |> to_string() |> String.trim(),
        service_type: service_type,
        served_at: Map.get(params, "served_at", svc.served_at),
        boar_id: if(service_type == "natural", do: boar_id, else: nil),
        pen_id: pen_id,
        notes: Shared.presence(Map.get(params, "notes")),
        backfill: backfill,
        force_create: force_create,
        error_message: nil
    }

    assign(socket, svc: svc)
  end

  defp resolve_svc_sow(socket) do
    svc = socket.assigns.svc
    ac = socket.assigns.ac
    scope = socket.assigns.current_scope
    tag = svc.sow_ear_tag

    {svc, ac} =
      cond do
        tag in [nil, ""] ->
          {%{
             svc
             | sow_state: :empty,
               not_serviceable_status: nil,
               similar_tags: [],
               resolved_sow_id: nil
           }, %{ac | pen_label: nil}}

        true ->
          case Animals.find_by_ear_tag(scope, tag) do
            %{id: id} = sow ->
              state =
                if sow_serviceable_status?(sow.status), do: :existing, else: :not_serviceable

              svc = %{
                svc
                | sow_state: state,
                  not_serviceable_status: if(state == :not_serviceable, do: sow.status),
                  similar_tags: [],
                  resolved_sow_id: id
              }

              svc = if is_nil(svc.pen_id), do: %{svc | pen_id: sow.current_pen_id}, else: svc
              {svc, Shared.maybe_preselect_pen(%{ac | pen_label: nil}, scope, sow)}

            nil ->
              ac = %{ac | pen_label: nil}

              case Animals.similar_ear_tags(scope, tag) do
                [] ->
                  {%{
                     svc
                     | sow_state: :new,
                       not_serviceable_status: nil,
                       similar_tags: [],
                       resolved_sow_id: nil
                   }, ac}

                tags ->
                  state = if svc.force_create, do: :similar_overridable, else: :similar

                  {%{
                     svc
                     | sow_state: state,
                       not_serviceable_status: nil,
                       similar_tags: tags,
                       resolved_sow_id: nil
                   }, ac}
              end
          end
      end

    assign(socket, svc: svc, ac: ac)
  end

  defp build_service_attrs(svc) do
    base = %{
      sow_ear_tag: svc.sow_ear_tag,
      service_type: svc.service_type,
      served_at: svc.served_at,
      notes: svc.notes
    }

    base =
      if svc.service_type == "natural" and svc.boar_id,
        do: Map.put(base, :boar_id, svc.boar_id),
        else: base

    base = if svc.pen_id, do: Map.put(base, :pen_id, svc.pen_id), else: base

    case svc.sow_state do
      :existing ->
        Map.put(base, :sow_id, svc.resolved_sow_id)

      :new ->
        Map.put(base, :backfill_sow, %{
          breed: svc.backfill[:breed],
          dob: svc.backfill[:dob] || svc.default_dob
        })

      :similar_overridable ->
        Map.put(base, :backfill_sow, %{
          breed: svc.backfill[:breed],
          dob: svc.backfill[:dob] || svc.default_dob,
          force_create: true
        })

      _ ->
        base
    end
  end

  defp service_save_enabled?(%{sow_state: :not_serviceable}), do: false

  defp service_save_enabled?(%{sow_state: state, service_type: type, boar_id: boar_id}) do
    has_sow? = state in [:existing, :new, :similar_overridable]
    boar_ok? = type != "natural" or not is_nil(boar_id)
    has_sow? and boar_ok?
  end

  defp service_save_label(%{sow_state: state})
       when state in [:new, :similar_overridable],
       do: gettext("Save service + register sow")

  defp service_save_label(_), do: gettext("Save service")

  defp sow_input_class(:existing), do: "border-success focus:border-success"
  defp sow_input_class(:new), do: "border-warning focus:border-warning"
  defp sow_input_class(:similar_overridable), do: "border-warning focus:border-warning"
  defp sow_input_class(:similar), do: "border-error focus:border-error"
  defp sow_input_class(:not_serviceable), do: "border-error focus:border-error"
  defp sow_input_class(_), do: ""

  defp sow_state_text(%{sow_state: :not_serviceable, not_serviceable_status: status}),
    do: gettext("✗ Sow is %{status} — cannot record service", status: status)

  defp sow_state_text(%{sow_state: state}), do: sow_state_text(state)
  defp sow_state_text(:existing), do: gettext("✓ Existing sow on file")
  defp sow_state_text(:new), do: gettext("+ New tag — will register on save")
  defp sow_state_text(:similar), do: gettext("⚠ Looks similar to an existing tag")

  defp sow_state_text(:similar_overridable),
    do: gettext("⚠ Override active — will create as new sow")

  defp sow_state_text(_), do: gettext("Type a tag to begin")

  @serviceable_statuses ~w(active open dry served)
  defp sow_serviceable_status?(status), do: status in @serviceable_statuses

  defp frw_state_text(:resolved), do: gettext("✓ Open service found")
  defp frw_state_text(:not_found), do: gettext("⚠ No sow with that tag")

  defp frw_state_text(:no_open_service),
    do: gettext("⚠ Sow has no open service to farrow against")

  defp frw_state_text(_), do: gettext("Type the sow ear tag to begin")

  defp load_rows(socket) do
    scope = socket.assigns.current_scope
    filters = socket.assigns.filters

    opts = [
      search: filters.q,
      due_window: filters.window,
      service_type: filters.service_type,
      pen_search: blank_to_nil(filters.pen_search),
      min_parity: blank_to_nil(filters.min_parity),
      max_parity: blank_to_nil(filters.max_parity),
      limit: @per_page,
      offset: 0
    ]

    rows = Breeding.list_gestating_sows(scope, opts) |> attach_parity(scope)
    total = Breeding.count_gestating_sows(scope, opts)

    socket
    |> assign(total: total, page: 1, has_more: length(rows) < total)
    |> stream(:gestating, rows, reset: true)
  end

  defp append_rows(socket) do
    scope = socket.assigns.current_scope
    filters = socket.assigns.filters
    next_page = socket.assigns.page + 1

    opts = [
      search: filters.q,
      due_window: filters.window,
      service_type: filters.service_type,
      pen_search: blank_to_nil(filters.pen_search),
      min_parity: blank_to_nil(filters.min_parity),
      max_parity: blank_to_nil(filters.max_parity),
      limit: @per_page,
      offset: (next_page - 1) * @per_page
    ]

    rows = Breeding.list_gestating_sows(scope, opts) |> attach_parity(scope)
    loaded = next_page * @per_page

    socket =
      Enum.reduce(rows, socket, fn row, acc -> stream_insert(acc, :gestating, row) end)

    assign(socket, page: next_page, has_more: loaded < socket.assigns.total)
  end

  defp close_form(socket) do
    assign(socket,
      form_mode: nil,
      form: nil,
      form_target: nil,
      form_sow_tag: nil,
      svc: nil,
      frw: nil,
      ac: Shared.default_ac(socket.assigns.current_scope)
    )
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  defp attach_parity(rows, scope) do
    sow_ids = Enum.map(rows, & &1.service.sow_id)
    parities = Breeding.parities_for(scope, sow_ids)
    Enum.map(rows, &Map.put(&1, :parity, Map.get(parities, &1.service.sow_id, 0)))
  end

  defp days_left(%{expected_farrow_date: efd}) do
    Date.diff(efd, Date.utc_today())
  end

  defp sow_pen_label(%{current_pen: %{code: code, house: %{code: hcode}}}), do: "#{hcode}-#{code}"
  defp sow_pen_label(%{current_pen: %{code: code}}), do: code
  defp sow_pen_label(_), do: "—"

  defp expected_farrow(%{served_at: %Date{} = d}),
    do: Date.add(d, Breeding.gestation_days())

  defp expected_farrow(_), do: nil
end
