defmodule PeggyWeb.FarmLive.Breeding do
  use PeggyWeb, :live_view

  alias Peggy.{Breeding, Animals, Locations, Policy}
  alias Peggy.Breeding.{Service, Farrowing, Weaning}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-6xl">
        <.header>
          {gettext("Breeding")}
          <:subtitle>{gettext("Services, farrowings, and weanings")}</:subtitle>
          <:actions>
            <.link
              :if={@can_record}
              navigate={~p"/farms/#{@current_scope.farm.slug}/breeding/batch-service"}
              class="btn btn-sm"
            >
              {gettext("Batch Service")}
            </.link>
            <.button :if={@can_record} phx-click="new_service" class="btn btn-primary btn-sm">
              {gettext("Record Service")}
            </.button>
          </:actions>
        </.header>

        <%!-- Tabs --%>
        <div role="tablist" class="tabs tabs-bordered mt-6">
          <button
            type="button"
            role="tab"
            phx-click="change_tab"
            phx-value-tab="gestating"
            class={["tab", @tab == "gestating" && "tab-active"]}
          >
            {gettext("Gestating")}
            <span class="ml-1 text-base-content/60 text-sm">({@total})</span>
          </button>
          <button
            type="button"
            role="tab"
            phx-click="change_tab"
            phx-value-tab="lactating"
            class={["tab", @tab == "lactating" && "tab-active"]}
          >
            {gettext("Lactating")}
            <span :if={@tab == "lactating"} class="ml-1 text-base-content/60 text-sm">
              ({@total})
            </span>
          </button>
        </div>

        <%!-- Gestating tab --%>
        <section :if={@tab == "gestating"} class="mt-4">
          <form
            id="gestating-filters"
            phx-change="filter_gestating"
            phx-submit="filter_gestating"
            class="flex flex-wrap gap-3 items-end"
          >
            <label class="form-control w-full sm:w-56">
              <div class="label py-1">
                <span class="label-text text-xs">{gettext("Search sow tag")}</span>
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
            <label class="form-control w-full sm:w-48">
              <div class="label py-1">
                <span class="label-text text-xs">{gettext("Due window")}</span>
              </div>
              <select name="window" class="select select-sm select-bordered">
                <option value="all" selected={@filters.window == "all"}>{gettext("All")}</option>
                <option value="7" selected={@filters.window == "7"}>
                  {gettext("Due in 7 days")}
                </option>
                <option value="14" selected={@filters.window == "14"}>
                  {gettext("Due in 14 days")}
                </option>
                <option value="overdue" selected={@filters.window == "overdue"}>
                  {gettext("Overdue")}
                </option>
              </select>
            </label>
            <label class="form-control w-full sm:w-40">
              <div class="label py-1">
                <span class="label-text text-xs">{gettext("Service type")}</span>
              </div>
              <select name="service_type" class="select select-sm select-bordered">
                <option value="all" selected={@filters.service_type == "all"}>
                  {gettext("All")}
                </option>
                <option value="natural" selected={@filters.service_type == "natural"}>
                  {gettext("Natural")}
                </option>
                <option value="ai" selected={@filters.service_type == "ai"}>
                  {gettext("AI")}
                </option>
              </select>
            </label>
          </form>

          <div class="mt-4 overflow-x-auto">
            <table class="table table-sm w-full">
              <thead class="text-left text-base-content/60">
                <tr>
                  <th class="py-2">{gettext("Sow")}</th>
                  <th class="py-2">{gettext("Boar")}</th>
                  <th class="py-2">{gettext("Type")}</th>
                  <th class="py-2">{gettext("Served")}</th>
                  <th class="py-2">{gettext("Expected farrow")}</th>
                  <th class="py-2 text-right">{gettext("Days left")}</th>
                  <th :if={@can_record} class="py-2"></th>
                </tr>
              </thead>
              <tbody id="gestating-rows" phx-update="stream">
                <tr
                  :for={{dom_id, entry} <- @streams.gestating}
                  id={dom_id}
                  class="border-t border-base-200"
                >
                  <td class="py-1.5 font-mono font-semibold">
                    <.link
                      navigate={
                        ~p"/farms/#{@current_scope.farm.slug}/animals/#{entry.service.sow_id}"
                      }
                      class="text-primary hover:underline"
                    >
                      {entry.service.sow.ear_tag}
                    </.link>
                  </td>
                  <td class="py-1.5 font-mono">
                    {entry.service.boar && entry.service.boar.ear_tag}
                  </td>
                  <td class="py-1.5">{entry.service.service_type}</td>
                  <td class="py-1.5">{entry.service.served_at}</td>
                  <td class="py-1.5">{entry.expected_farrow_date}</td>
                  <td class={[
                    "py-1.5 text-right font-mono",
                    days_left(entry) <= 7 && "text-warning font-bold",
                    days_left(entry) <= 0 && "text-error font-bold"
                  ]}>
                    {days_left(entry)}
                  </td>
                  <td :if={@can_record} class="py-1.5 text-right">
                    <button
                      phx-click="new_farrowing"
                      phx-value-service-id={entry.service.id}
                      class="btn btn-ghost btn-xs"
                    >
                      {gettext("Farrow")}
                    </button>
                    <button
                      phx-click="close_service_prompt"
                      phx-value-service-id={entry.service.id}
                      class="btn btn-ghost btn-xs text-base-content/50"
                    >
                      {gettext("Close")}
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
            <p :if={@total == 0} class="mt-2 text-sm text-base-content/60">
              {gettext("No gestating sows match the filters.")}
            </p>
          </div>

          <.pagination page={@page} per_page={@per_page} total={@total} />
        </section>

        <%!-- Lactating tab --%>
        <section :if={@tab == "lactating"} class="mt-4">
          <form
            id="lactating-filters"
            phx-change="filter_lactating"
            phx-submit="filter_lactating"
            class="flex flex-wrap gap-3 items-end"
          >
            <label class="form-control w-full sm:w-56">
              <div class="label py-1">
                <span class="label-text text-xs">{gettext("Search sow tag")}</span>
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
            <label class="form-control w-full sm:w-44">
              <div class="label py-1">
                <span class="label-text text-xs">{gettext("Litter age")}</span>
              </div>
              <select name="age" class="select select-sm select-bordered">
                <option value="all" selected={@filters.age == "all"}>{gettext("All")}</option>
                <option value="week1" selected={@filters.age == "week1"}>
                  {gettext("Week 1 (0–6d)")}
                </option>
                <option value="week2" selected={@filters.age == "week2"}>
                  {gettext("Week 2 (7–13d)")}
                </option>
                <option value="week3" selected={@filters.age == "week3"}>
                  {gettext("Week 3 (14–20d)")}
                </option>
                <option value="wean_due" selected={@filters.age == "wean_due"}>
                  {gettext("Due to wean (21d+)")}
                </option>
              </select>
            </label>
            <label class="form-control w-full sm:w-56">
              <div class="label py-1">
                <span class="label-text text-xs">{gettext("Pen")}</span>
              </div>
              <select name="pen_id" class="select select-sm select-bordered font-mono">
                <option value="" selected={@filters.pen_id in [nil, ""]}>
                  {gettext("All pens")}
                </option>
                <option
                  :for={p <- @pens}
                  value={p.id}
                  selected={"#{p.id}" == "#{@filters.pen_id}"}
                >
                  {p.house.code}/{p.code}
                </option>
              </select>
            </label>
          </form>

          <div class="mt-4 overflow-x-auto">
            <table class="table table-sm w-full">
              <thead class="text-left text-base-content/60">
                <tr>
                  <th class="py-2">{gettext("Sow")}</th>
                  <th class="py-2">{gettext("Farrowed")}</th>
                  <th class="py-2 text-right">{gettext("Born alive")}</th>
                  <th class="py-2 text-right">{gettext("Surviving")}</th>
                  <th class="py-2">{gettext("Pen")}</th>
                  <th class="py-2 text-right">{gettext("Days")}</th>
                  <th :if={@can_record} class="py-2"></th>
                </tr>
              </thead>
              <tbody id="lactating-rows" phx-update="stream">
                <tr
                  :for={{dom_id, entry} <- @streams.lactating}
                  id={dom_id}
                  class="border-t border-base-200"
                >
                  <td class="py-1.5 font-mono font-semibold">
                    <.link
                      navigate={
                        ~p"/farms/#{@current_scope.farm.slug}/animals/#{entry.farrowing.sow_id}"
                      }
                      class="text-primary hover:underline"
                    >
                      {entry.farrowing.sow.ear_tag}
                    </.link>
                  </td>
                  <td class="py-1.5">{entry.farrowing.farrowed_at}</td>
                  <td class="py-1.5 text-right">{entry.farrowing.born_alive}</td>
                  <td class="py-1.5 text-right">{entry.surviving}</td>
                  <td class="py-1.5 font-mono">
                    {entry.farrowing.pen &&
                      "#{entry.farrowing.pen.house.code}/#{entry.farrowing.pen.code}"}
                  </td>
                  <td class="py-1.5 text-right font-mono">
                    {Date.diff(Date.utc_today(), entry.farrowing.farrowed_at)}
                  </td>
                  <td :if={@can_record} class="py-1.5 text-right">
                    <button
                      phx-click="new_weaning"
                      phx-value-farrowing-id={entry.farrowing.id}
                      class="btn btn-ghost btn-xs"
                    >
                      {gettext("Wean")}
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
            <p :if={@total == 0} class="mt-2 text-sm text-base-content/60">
              {gettext("No lactating sows match the filters.")}
            </p>
          </div>

          <.pagination page={@page} per_page={@per_page} total={@total} />
        </section>

        <%!-- Service form modal --%>
        <.modal
          :if={@form_mode == :service}
          title={gettext("Record Service")}
          on_cancel="cancel"
        >
          <.form
            for={@form}
            id="service-form"
            phx-submit="save_service"
            phx-change="validate_service"
            class="grid grid-cols-2 gap-x-4 gap-y-1"
          >
            <.autocomplete
              id="service-sow-picker"
              label={gettext("Sow")}
              name="service[sow_id]"
              value={fv(@form, :sow_id)}
              items={@ac.sow_items}
              selected_label={@ac.sow_label}
              class="w-full input font-mono"
              placeholder={gettext("Search by ear tag...")}
            />
            <.input
              field={@form[:service_type]}
              type="select"
              label={gettext("Service type")}
              options={[
                {gettext("Natural"), "natural"},
                {gettext("AI"), "ai"}
              ]}
            />
            <.autocomplete
              :if={fv(@form, :service_type) == "natural"}
              id="service-boar-picker"
              label={gettext("Boar")}
              name="service[boar_id]"
              value={fv(@form, :boar_id)}
              items={@ac.boar_items}
              selected_label={@ac.boar_label}
              class="w-full input font-mono"
              placeholder={gettext("Search by ear tag...")}
            />
            <.input
              field={@form[:served_at]}
              type="date"
              label={gettext("Served at")}
            />
            <div class="col-span-2">
              <.input field={@form[:notes]} type="textarea" label={gettext("Notes")} />
            </div>
            <div class="col-span-2 flex gap-2 justify-end">
              <button type="button" phx-click="cancel" class="btn btn-ghost">
                {gettext("Cancel")}
              </button>
              <.button class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
                {gettext("Save")}
              </.button>
            </div>
          </.form>
        </.modal>

        <%!-- Farrowing form modal --%>
        <.modal
          :if={@form_mode == :farrowing}
          title={gettext("Record Farrowing")}
          on_cancel="cancel"
        >
          <div class="mb-3 text-sm">
            <span class="text-base-content/60">{gettext("Sow:")}</span>
            <span class="font-mono font-semibold">{@form_sow_tag}</span>
          </div>
          <.form
            for={@form}
            id="farrowing-form"
            phx-submit="save_farrowing"
            phx-change="validate_farrowing"
            class="grid grid-cols-2 gap-x-4 gap-y-1"
          >
            <.input
              field={@form[:farrowed_at]}
              type="date"
              label={gettext("Farrowed at")}
            />
            <.autocomplete
              id="farrowing-pen-picker"
              label={gettext("Farrowing pen")}
              name="farrowing[pen_id]"
              value={fv(@form, :pen_id)}
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
              <.button class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
                {gettext("Save")}
              </.button>
            </div>
          </.form>
        </.modal>

        <%!-- Weaning form modal --%>
        <.modal
          :if={@form_mode == :weaning}
          title={gettext("Record Weaning")}
          on_cancel="cancel"
        >
          <div class="mb-3 text-sm">
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
            <.autocomplete
              id="weaning-dest-pen-picker"
              label={gettext("Destination pen")}
              name="weaning[destination_pen_id]"
              value={fv(@form, :destination_pen_id)}
              items={@ac.pen_items}
              selected_label={@ac.dest_pen_label}
              class="w-full input font-mono"
              placeholder={gettext("Search pens...")}
            />
            <div class="col-span-2">
              <.input field={@form[:notes]} type="textarea" label={gettext("Notes")} />
            </div>
            <div class="col-span-2 flex gap-2 justify-end">
              <button type="button" phx-click="cancel" class="btn btn-ghost">
                {gettext("Cancel")}
              </button>
              <.button class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
                {gettext("Save")}
              </.button>
            </div>
          </.form>
        </.modal>

        <%!-- Close service modal --%>
        <.modal
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
        </.modal>
      </div>
    </Layouts.app>
    """
  end

  # ── Modal component ────────────────────────────────────────────────

  attr :title, :string, required: true
  attr :on_cancel, :string, required: true
  slot :inner_block, required: true

  defp modal(assigns) do
    ~H"""
    <div
      id="breeding-modal"
      class="fixed inset-0 bg-black/40 flex items-center justify-center z-50"
    >
      <div
        class="bg-base-100 rounded p-6 w-full max-w-2xl max-h-[90vh] overflow-y-auto"
        phx-click-away={@on_cancel}
        phx-window-keydown={@on_cancel}
        phx-key="escape"
      >
        <h3 class="text-lg font-semibold mb-3">{@title}</h3>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # ── Mount ──────────────────────────────────────────────────────────

  @per_page 25

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
       ac: default_ac(scope),
       pens: Locations.list_all_pens(scope),
       per_page: @per_page
     )
     |> stream_configure(:gestating, dom_id: &"service-#{&1.service.id}")
     |> stream_configure(:lactating, dom_id: &"farrowing-#{&1.farrowing.id}")
     |> stream(:gestating, [])
     |> stream(:lactating, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = param_tab(params["tab"])

    filters = %{
      q: params["q"] || "",
      window: param_window(params["window"]),
      service_type: param_service_type(params["service_type"]),
      age: param_age(params["age"]),
      pen_id: params["pen_id"] || ""
    }

    page = param_page(params["page"])

    {:noreply,
     socket
     |> assign(tab: tab, filters: filters, page: page)
     |> load_tab()}
  end

  # ── Events ─────────────────────────────────────────────────────────

  @impl true
  def handle_event("new_service", _, socket) do
    cs =
      Breeding.change_service(%Service{
        service_type: "natural",
        served_at: Date.utc_today()
      })

    {:noreply,
     socket
     |> assign(
       form_mode: :service,
       form: to_form(cs, as: :service),
       form_target: nil,
       ac: default_ac(socket.assigns.current_scope)
     )}
  end

  def handle_event("validate_service", %{"service" => params}, socket) do
    cs = Breeding.change_service(%Service{}, params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(cs, as: :service))}
  end

  def handle_event("save_service", %{"service" => params}, socket) do
    if socket.assigns.can_record do
      case Breeding.record_service(socket.assigns.current_scope, params) do
        {:ok, _} ->
          {:noreply,
           socket
           |> close_form()
           |> load_tab()
           |> put_flash(:info, gettext("Service recorded."))}

        {:error, cs} ->
          {:noreply, assign(socket, :form, to_form(cs, as: :service))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("new_farrowing", %{"service-id" => id}, socket) do
    scope = socket.assigns.current_scope
    service = Breeding.get_service!(scope, String.to_integer(id))
    sow = Animals.get_animal!(scope, service.sow_id)

    cs =
      Breeding.change_farrowing(%Farrowing{
        farrowed_at: Date.utc_today(),
        born_alive: 0,
        stillborn: 0,
        mummified: 0
      })

    ac =
      default_ac(scope)
      |> maybe_preselect_pen(scope, sow)

    {:noreply,
     assign(socket,
       form_mode: :farrowing,
       form: to_form(cs, as: :farrowing),
       form_target: service,
       form_sow_tag: sow.ear_tag,
       ac: ac
     )}
  end

  def handle_event("validate_farrowing", %{"farrowing" => params}, socket) do
    cs = Breeding.change_farrowing(%Farrowing{}, params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(cs, as: :farrowing))}
  end

  def handle_event("save_farrowing", %{"farrowing" => params}, socket) do
    if socket.assigns.can_record do
      service = socket.assigns.form_target

      case Breeding.record_farrowing(socket.assigns.current_scope, service, params) do
        {:ok, _farrowing, _piglets} ->
          {:noreply,
           socket
           |> close_form()
           |> load_tab()
           |> put_flash(:info, gettext("Farrowing recorded."))}

        {:error, :service_already_closed} ->
          {:noreply,
           socket
           |> close_form()
           |> load_tab()
           |> put_flash(:error, gettext("Service is already closed."))}

        {:error, cs} ->
          {:noreply, assign(socket, :form, to_form(cs, as: :farrowing))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("new_weaning", %{"farrowing-id" => id}, socket) do
    scope = socket.assigns.current_scope
    farrowing = Breeding.get_farrowing!(scope, String.to_integer(id))
    surviving = Breeding.surviving_piglet_count(farrowing)

    cs =
      Breeding.change_weaning(%Weaning{
        weaned_at: Date.utc_today(),
        weaned_count: surviving
      })

    {:noreply,
     assign(socket,
       form_mode: :weaning,
       form: to_form(cs, as: :weaning),
       form_target: farrowing,
       form_sow_tag: farrowing.sow.ear_tag,
       form_born_alive: farrowing.born_alive,
       form_surviving: surviving,
       ac: default_ac(scope)
     )}
  end

  def handle_event("validate_weaning", %{"weaning" => params}, socket) do
    cs = Breeding.change_weaning(%Weaning{}, params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(cs, as: :weaning))}
  end

  def handle_event("save_weaning", %{"weaning" => params}, socket) do
    if socket.assigns.can_record do
      farrowing = socket.assigns.form_target

      case Breeding.record_weaning(socket.assigns.current_scope, farrowing, params) do
        {:ok, _weaning, _batch} ->
          {:noreply,
           socket
           |> close_form()
           |> load_tab()
           |> put_flash(:info, gettext("Weaning recorded."))}

        {:error, :already_weaned} ->
          {:noreply,
           socket
           |> close_form()
           |> load_tab()
           |> put_flash(:error, gettext("Already weaned."))}

        {:error, cs} ->
          {:noreply, assign(socket, :form, to_form(cs, as: :weaning))}
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
           |> load_tab()
           |> put_flash(:info, gettext("Service closed."))}

        {:error, :already_closed} ->
          {:noreply,
           socket
           |> close_form()
           |> load_tab()
           |> put_flash(:error, gettext("Service is already closed."))}

        {:error, cs} ->
          {:noreply, assign(socket, :form, to_form(cs, as: :service))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("cancel", _, socket), do: {:noreply, close_form(socket)}

  def handle_event("change_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: breeding_path(socket, %{"tab" => tab, "page" => 1}))}
  end

  def handle_event("filter_gestating", params, socket) do
    query = %{
      "tab" => "gestating",
      "q" => params["q"] || "",
      "window" => params["window"] || "all",
      "service_type" => params["service_type"] || "all",
      "page" => 1
    }

    {:noreply, push_patch(socket, to: breeding_path(socket, query))}
  end

  def handle_event("filter_lactating", params, socket) do
    query = %{
      "tab" => "lactating",
      "q" => params["q"] || "",
      "age" => params["age"] || "all",
      "pen_id" => params["pen_id"] || "",
      "page" => 1
    }

    {:noreply, push_patch(socket, to: breeding_path(socket, query))}
  end

  def handle_event("paginate", %{"page" => page}, socket) do
    {:noreply,
     push_patch(socket,
       to: breeding_path(socket, %{"tab" => socket.assigns.tab, "page" => page})
     )}
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp load_tab(%{assigns: %{tab: "gestating"}} = socket) do
    scope = socket.assigns.current_scope
    filters = socket.assigns.filters
    page = socket.assigns.page

    opts = [
      search: filters.q,
      due_window: filters.window,
      service_type: filters.service_type,
      limit: @per_page,
      offset: (page - 1) * @per_page
    ]

    rows = Breeding.list_gestating_sows(scope, opts)
    total = Breeding.count_gestating_sows(scope, opts)

    socket
    |> assign(total: total)
    |> stream(:gestating, rows, reset: true)
  end

  defp load_tab(%{assigns: %{tab: "lactating"}} = socket) do
    scope = socket.assigns.current_scope
    filters = socket.assigns.filters
    page = socket.assigns.page

    opts = [
      search: filters.q,
      age_bucket: filters.age,
      pen_id: filters.pen_id,
      limit: @per_page,
      offset: (page - 1) * @per_page
    ]

    rows =
      Breeding.list_lactating_sows(scope, opts)
      |> Enum.map(fn f ->
        %{farrowing: f, surviving: Breeding.surviving_piglet_count(f)}
      end)

    total = Breeding.count_lactating_sows(scope, opts)

    socket
    |> assign(total: total)
    |> stream(:lactating, rows, reset: true)
  end

  defp breeding_path(socket, overrides) do
    slug = socket.assigns.current_scope.farm.slug
    existing = current_query(socket)
    merged = existing |> Map.merge(overrides) |> prune_query()
    ~p"/farms/#{slug}/breeding?#{merged}"
  end

  defp current_query(%{assigns: assigns} = _socket) do
    filters = Map.get(assigns, :filters, %{})

    base = %{"tab" => Map.get(assigns, :tab, "gestating"), "page" => Map.get(assigns, :page, 1)}

    base
    |> Map.put("q", Map.get(filters, :q, ""))
    |> Map.put("window", Map.get(filters, :window, "all"))
    |> Map.put("service_type", Map.get(filters, :service_type, "all"))
    |> Map.put("age", Map.get(filters, :age, "all"))
    |> Map.put("pen_id", Map.get(filters, :pen_id, ""))
  end

  # Drop empty / default params so URLs stay clean.
  defp prune_query(q) do
    q
    |> Enum.reject(fn
      {_k, nil} -> true
      {_k, ""} -> true
      {"page", 1} -> true
      {"page", "1"} -> true
      {"window", "all"} -> true
      {"service_type", "all"} -> true
      {"age", "all"} -> true
      _ -> false
    end)
    |> Map.new()
  end

  defp param_tab("lactating"), do: "lactating"
  defp param_tab(_), do: "gestating"

  defp param_window(w) when w in ["7", "14", "overdue"], do: w
  defp param_window(_), do: "all"

  defp param_service_type(t) when t in ["natural", "ai"], do: t
  defp param_service_type(_), do: "all"

  defp param_age(a) when a in ["week1", "week2", "week3", "wean_due"], do: a
  defp param_age(_), do: "all"

  defp param_page(p) when is_binary(p) do
    case Integer.parse(p) do
      {n, ""} when n >= 1 -> n
      _ -> 1
    end
  end

  defp param_page(_), do: 1

  # ── Pagination component ───────────────────────────────────────────

  attr :page, :integer, required: true
  attr :per_page, :integer, required: true
  attr :total, :integer, required: true

  defp pagination(assigns) do
    assigns =
      assign(assigns,
        total_pages: max(1, div(assigns.total + assigns.per_page - 1, assigns.per_page)),
        from_n: min((assigns.page - 1) * assigns.per_page + 1, assigns.total),
        to_n: min(assigns.page * assigns.per_page, assigns.total)
      )

    ~H"""
    <div :if={@total > 0} class="mt-3 flex items-center justify-between text-sm">
      <div class="text-base-content/60">
        {gettext("%{from}–%{to} of %{total}", from: @from_n, to: @to_n, total: @total)}
      </div>
      <div class="flex gap-1">
        <button
          type="button"
          phx-click="paginate"
          phx-value-page={max(1, @page - 1)}
          disabled={@page <= 1}
          class="btn btn-ghost btn-xs"
        >
          {gettext("Prev")}
        </button>
        <span class="btn btn-ghost btn-xs no-animation pointer-events-none">
          {gettext("Page %{page} / %{total}", page: @page, total: @total_pages)}
        </span>
        <button
          type="button"
          phx-click="paginate"
          phx-value-page={min(@total_pages, @page + 1)}
          disabled={@page >= @total_pages}
          class="btn btn-ghost btn-xs"
        >
          {gettext("Next")}
        </button>
      </div>
    </div>
    """
  end

  defp close_form(socket) do
    assign(socket,
      form_mode: nil,
      form: nil,
      form_target: nil,
      form_sow_tag: nil,
      form_born_alive: nil,
      form_surviving: nil,
      ac: default_ac(socket.assigns.current_scope)
    )
  end

  defp default_ac(scope) do
    animals = Animals.list_animals(scope, status: "present")
    pens = Locations.list_all_pens(scope)

    pen_items = Enum.map(pens, &%{id: &1.id, label: "#{&1.house.code}/#{&1.code}"})

    %{
      sow_items: animal_items(animals, "female"),
      sow_label: nil,
      boar_items: animal_items(animals, "male"),
      boar_label: nil,
      pen_items: pen_items,
      pen_label: nil,
      dest_pen_label: nil
    }
  end

  defp animal_items(animals, sex) do
    animals
    |> Enum.filter(&(&1.sex == sex and &1.ear_tag != nil))
    |> Enum.map(&%{id: &1.id, label: &1.ear_tag})
  end

  defp maybe_preselect_pen(ac, scope, %{current_pen_id: pen_id}) when not is_nil(pen_id) do
    pen = Locations.get_pen!(scope, pen_id) |> Peggy.Repo.preload(:house)
    %{ac | pen_label: "#{pen.house.code}/#{pen.code}"}
  end

  defp maybe_preselect_pen(ac, _, _), do: ac

  defp fv(form, field), do: Phoenix.HTML.Form.input_value(form, field)

  defp days_left(%{expected_farrow_date: efd}) do
    Date.diff(efd, Date.utc_today())
  end
end
