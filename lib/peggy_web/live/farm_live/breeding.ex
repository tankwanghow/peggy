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
            <.link
              :if={@can_record}
              navigate={~p"/farms/#{@current_scope.farm.slug}/breeding/batch-farrowing"}
              class="btn btn-sm"
            >
              {gettext("Batch Farrowing")}
            </.link>
            <.button :if={@can_record} phx-click="new_service" class="btn btn-primary btn-sm">
              {gettext("Record Service")}
            </.button>
          </:actions>
        </.header>

        <%!-- Tabs --%>
        <div role="tablist" class="tabs tabs-boxed bg-base-200 mt-6 w-fit p-1">
          <button
            type="button"
            role="tab"
            phx-click="change_tab"
            phx-value-tab="gestating"
            class={[
              "tab cursor-pointer font-medium px-6 transition-colors",
              @tab == "gestating" && "tab-active bg-primary text-primary-content",
              @tab != "gestating" && "hover:bg-base-300"
            ]}
          >
            {gettext("Gestating")}
          </button>
          <button
            type="button"
            role="tab"
            phx-click="change_tab"
            phx-value-tab="lactating"
            class={[
              "tab cursor-pointer font-medium px-6 transition-colors",
              @tab == "lactating" && "tab-active bg-primary text-primary-content",
              @tab != "lactating" && "hover:bg-base-300"
            ]}
          >
            {gettext("Lactating")}
          </button>
          <button
            type="button"
            role="tab"
            phx-click="change_tab"
            phx-value-tab="weaned"
            class={[
              "tab cursor-pointer font-medium px-6 transition-colors",
              @tab == "weaned" && "tab-active bg-primary text-primary-content",
              @tab != "weaned" && "hover:bg-base-300"
            ]}
          >
            {gettext("Weaned")}
          </button>
          <button
            :if={@can_record}
            type="button"
            role="tab"
            phx-click="change_tab"
            phx-value-tab="deleted"
            class={[
              "tab cursor-pointer font-medium px-6 transition-colors",
              @tab == "deleted" && "tab-active bg-primary text-primary-content",
              @tab != "deleted" && "hover:bg-base-300"
            ]}
          >
            {gettext("Deleted")}
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
                <option value="ai" selected={@filters.service_type == "ai"}>
                  {gettext("AI")}
                </option>
                <option value="natural" selected={@filters.service_type == "natural"}>
                  {gettext("Natural")}
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
                    <button
                      phx-click="delete_service"
                      phx-value-service-id={entry.service.id}
                      data-confirm={gettext("Delete this service? The sow will be reverted to open.")}
                      class="btn btn-ghost btn-xs text-error/70"
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
                    <button
                      phx-click="delete_farrowing"
                      phx-value-farrowing-id={entry.farrowing.id}
                      data-confirm={
                        gettext(
                          "Delete this farrowing? The litter batch and movements will be removed and the sow reverted."
                        )
                      }
                      class="btn btn-ghost btn-xs text-error/70"
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

          <.pagination page={@page} per_page={@per_page} total={@total} />
        </section>

        <%!-- Weaned tab --%>
        <section :if={@tab == "weaned"} class="mt-4">
          <form
            id="weaned-filters"
            phx-change="filter_weaned"
            phx-submit="filter_weaned"
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
          </form>

          <div class="mt-4 overflow-x-auto">
            <table class="table table-sm w-full">
              <thead class="text-left text-base-content/60">
                <tr>
                  <th class="py-2">{gettext("Sow")}</th>
                  <th class="py-2">{gettext("Weaned at")}</th>
                  <th class="py-2 text-right">{gettext("Weaned count")}</th>
                  <th class="py-2 text-right">{gettext("Avg wt (g)")}</th>
                  <th class="py-2">{gettext("Dest. pen")}</th>
                  <th :if={@can_record} class="py-2"></th>
                </tr>
              </thead>
              <tbody id="weaned-rows" phx-update="stream">
                <tr
                  :for={{dom_id, w} <- @streams.weaned}
                  id={dom_id}
                  class="border-t border-base-200"
                >
                  <td class="py-1.5 font-mono font-semibold">
                    {w.farrowing && w.farrowing.sow && w.farrowing.sow.ear_tag}
                  </td>
                  <td class="py-1.5">{w.weaned_at}</td>
                  <td class="py-1.5 text-right">{w.weaned_count}</td>
                  <td class="py-1.5 text-right">{w.avg_wean_weight_g}</td>
                  <td class="py-1.5 font-mono">
                    {w.destination_pen &&
                      "#{w.destination_pen.house.code}/#{w.destination_pen.code}"}
                  </td>
                  <td :if={@can_record} class="py-1.5 text-right">
                    <button
                      phx-click="delete_weaning"
                      phx-value-weaning-id={w.id}
                      data-confirm={
                        gettext("Delete this weaning? The litter batch and sow will be reverted.")
                      }
                      class="btn btn-ghost btn-xs text-error/70"
                      title={gettext("Delete weaning")}
                    >
                      <.icon name="hero-trash" class="size-4" />
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
            <p :if={@total == 0} class="mt-2 text-sm text-base-content/60">
              {gettext("No weanings match the filters.")}
            </p>
          </div>
        </section>

        <%!-- Deleted tab --%>
        <section :if={@tab == "deleted"} class="mt-4 space-y-8">
          <div>
            <h3 class="font-semibold mb-2">{gettext("Deleted services")}</h3>
            <p class="text-sm text-base-content/60 mb-3">
              {gettext("Restore reverts sow status if it is still consistent.")}
            </p>

            <div class="overflow-x-auto">
              <table class="table table-sm w-full">
                <thead class="text-left text-base-content/60">
                  <tr>
                    <th class="py-2">{gettext("Sow")}</th>
                    <th class="py-2">{gettext("Boar")}</th>
                    <th class="py-2">{gettext("Type")}</th>
                    <th class="py-2">{gettext("Served")}</th>
                    <th class="py-2">{gettext("Result")}</th>
                    <th class="py-2">{gettext("Deleted at")}</th>
                    <th class="py-2">{gettext("By")}</th>
                    <th :if={@can_record} class="py-2"></th>
                  </tr>
                </thead>
                <tbody id="deleted-rows" phx-update="stream">
                  <tr
                    :for={{dom_id, s} <- @streams.deleted}
                    id={dom_id}
                    class="border-t border-base-200"
                  >
                    <td class="py-1.5 font-mono font-semibold">
                      {s.sow && s.sow.ear_tag}
                    </td>
                    <td class="py-1.5 font-mono">{s.boar && s.boar.ear_tag}</td>
                    <td class="py-1.5">{s.service_type}</td>
                    <td class="py-1.5">{s.served_at}</td>
                    <td class="py-1.5">{s.result || gettext("open")}</td>
                    <td class="py-1.5 text-base-content/70">
                      {Calendar.strftime(s.deleted_at, "%Y-%m-%d %H:%M")}
                    </td>
                    <td class="py-1.5 text-base-content/70">
                      {s.deleted_by && s.deleted_by.email}
                    </td>
                    <td :if={@can_record} class="py-1.5 text-right">
                      <button
                        phx-click="restore_service"
                        phx-value-service-id={s.id}
                        class="btn btn-ghost btn-xs text-primary"
                      >
                        <.icon name="hero-arrow-uturn-left" class="size-4" />
                        {gettext("Restore")}
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
              <p :if={@deleted_services_empty} class="mt-2 text-sm text-base-content/60">
                {gettext("No deleted services.")}
              </p>
            </div>
          </div>

          <div>
            <h3 class="font-semibold mb-2">{gettext("Deleted farrowings")}</h3>
            <p class="text-sm text-base-content/60 mb-3">
              {gettext("Restoring re-creates the litter batch and reapplies sow and service state.")}
            </p>

            <div class="overflow-x-auto">
              <table class="table table-sm w-full">
                <thead class="text-left text-base-content/60">
                  <tr>
                    <th class="py-2">{gettext("Sow")}</th>
                    <th class="py-2">{gettext("Farrowed")}</th>
                    <th class="py-2 text-right">{gettext("Born alive")}</th>
                    <th class="py-2">{gettext("Pen")}</th>
                    <th class="py-2">{gettext("Deleted at")}</th>
                    <th class="py-2">{gettext("By")}</th>
                    <th :if={@can_record} class="py-2"></th>
                  </tr>
                </thead>
                <tbody id="deleted-farrowing-rows" phx-update="stream">
                  <tr
                    :for={{dom_id, f} <- @streams.deleted_farrowings}
                    id={dom_id}
                    class="border-t border-base-200"
                  >
                    <td class="py-1.5 font-mono font-semibold">
                      {f.sow && f.sow.ear_tag}
                    </td>
                    <td class="py-1.5">{f.farrowed_at}</td>
                    <td class="py-1.5 text-right font-mono">{f.born_alive}</td>
                    <td class="py-1.5 font-mono">
                      {f.pen && "#{f.pen.house.code}/#{f.pen.code}"}
                    </td>
                    <td class="py-1.5 text-base-content/70">
                      {Calendar.strftime(f.deleted_at, "%Y-%m-%d %H:%M")}
                    </td>
                    <td class="py-1.5 text-base-content/70">
                      {f.deleted_by && f.deleted_by.email}
                    </td>
                    <td :if={@can_record} class="py-1.5 text-right">
                      <button
                        phx-click="restore_farrowing"
                        phx-value-farrowing-id={f.id}
                        class="btn btn-ghost btn-xs text-primary"
                      >
                        <.icon name="hero-arrow-uturn-left" class="size-4" />
                        {gettext("Restore")}
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
              <p :if={@deleted_farrowings_empty} class="mt-2 text-sm text-base-content/60">
                {gettext("No deleted farrowings.")}
              </p>
            </div>
          </div>

          <div>
            <h3 class="font-semibold mb-2">{gettext("Deleted weanings")}</h3>
            <p class="text-sm text-base-content/60 mb-3">
              {gettext("Restoring re-applies the batch update and sow transition.")}
            </p>

            <div class="overflow-x-auto">
              <table class="table table-sm w-full">
                <thead class="text-left text-base-content/60">
                  <tr>
                    <th class="py-2">{gettext("Sow")}</th>
                    <th class="py-2">{gettext("Weaned at")}</th>
                    <th class="py-2 text-right">{gettext("Weaned count")}</th>
                    <th class="py-2">{gettext("Dest. pen")}</th>
                    <th class="py-2">{gettext("Deleted at")}</th>
                    <th class="py-2">{gettext("By")}</th>
                    <th :if={@can_record} class="py-2"></th>
                  </tr>
                </thead>
                <tbody id="deleted-weaning-rows" phx-update="stream">
                  <tr
                    :for={{dom_id, w} <- @streams.deleted_weanings}
                    id={dom_id}
                    class="border-t border-base-200"
                  >
                    <td class="py-1.5 font-mono font-semibold">
                      {w.farrowing && w.farrowing.sow && w.farrowing.sow.ear_tag}
                    </td>
                    <td class="py-1.5">{w.weaned_at}</td>
                    <td class="py-1.5 text-right">{w.weaned_count}</td>
                    <td class="py-1.5 font-mono">
                      {w.destination_pen &&
                        "#{w.destination_pen.house.code}/#{w.destination_pen.code}"}
                    </td>
                    <td class="py-1.5 text-base-content/70">
                      {Calendar.strftime(w.deleted_at, "%Y-%m-%d %H:%M")}
                    </td>
                    <td class="py-1.5 text-base-content/70">
                      {w.deleted_by && w.deleted_by.email}
                    </td>
                    <td :if={@can_record} class="py-1.5 text-right">
                      <button
                        phx-click="restore_weaning"
                        phx-value-weaning-id={w.id}
                        class="btn btn-ghost btn-xs text-primary"
                      >
                        <.icon name="hero-arrow-uturn-left" class="size-4" />
                        {gettext("Restore")}
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
              <p :if={@deleted_weanings_empty} class="mt-2 text-sm text-base-content/60">
                {gettext("No deleted weanings.")}
              </p>
            </div>
          </div>
        </section>

        <%!-- Service form modal (with back-fill cascade) --%>
        <.modal
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
                @svc.sow_state == :empty && "text-base-content/40"
              ]}>
                {sow_state_text(@svc.sow_state)}
              </p>
            </div>

            <%!-- New-sow back-fill panel --%>
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

            <%!-- Similar-tag warning + override --%>
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
                  class="btn btn-xs btn-outline btn-error font-mono"
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
       svc: nil,
       ac: default_ac(scope),
       pens: Locations.list_all_pens(scope),
       per_page: @per_page
     )
     |> stream_configure(:gestating, dom_id: &"service-#{&1.service.id}")
     |> stream_configure(:lactating, dom_id: &"farrowing-#{&1.farrowing.id}")
     |> stream_configure(:deleted, dom_id: &"deleted-#{&1.id}")
     |> stream_configure(:deleted_farrowings, dom_id: &"deleted-farrowing-#{&1.id}")
     |> stream_configure(:weaned, dom_id: &"weaning-#{&1.id}")
     |> stream_configure(:deleted_weanings, dom_id: &"deleted-weaning-#{&1.id}")
     |> stream(:gestating, [])
     |> stream(:lactating, [])
     |> stream(:deleted, [])
     |> stream(:deleted_farrowings, [])
     |> stream(:weaned, [])
     |> stream(:deleted_weanings, [])}
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
    today = Date.utc_today()

    {:noreply,
     socket
     |> assign(
       form_mode: :service,
       form_target: nil,
       ac: default_ac(socket.assigns.current_scope),
       svc: %{
         sow_ear_tag: "",
         sow_state: :empty,
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

  def handle_event("delete_service", %{"service-id" => id}, socket) do
    scope = socket.assigns.current_scope

    if socket.assigns.can_record do
      service = Breeding.get_service!(scope, String.to_integer(id))

      case Breeding.delete_service(scope, service) do
        {:ok, _} ->
          {:noreply,
           socket
           |> load_tab()
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

  def handle_event("restore_service", %{"service-id" => id}, socket) do
    scope = socket.assigns.current_scope

    if socket.assigns.can_record do
      service = Breeding.get_deleted_service!(scope, String.to_integer(id))

      case Breeding.restore_service(scope, service) do
        {:ok, _} ->
          {:noreply,
           socket
           |> load_tab()
           |> put_flash(:info, gettext("Service restored."))}

        {:error, :conflicting_open_service} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("Cannot restore — another open service exists for this sow.")
           )}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not restore service."))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("delete_farrowing", %{"farrowing-id" => id}, socket) do
    scope = socket.assigns.current_scope

    if socket.assigns.can_record do
      farrowing = Breeding.get_farrowing!(scope, String.to_integer(id))

      case Breeding.delete_farrowing(scope, farrowing) do
        {:ok, _} ->
          {:noreply,
           socket
           |> load_tab()
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

  def handle_event("restore_farrowing", %{"farrowing-id" => id}, socket) do
    scope = socket.assigns.current_scope

    if socket.assigns.can_record do
      farrowing = Breeding.get_deleted_farrowing!(scope, String.to_integer(id))

      case Breeding.restore_farrowing(scope, farrowing) do
        {:ok, _} ->
          {:noreply,
           socket
           |> load_tab()
           |> put_flash(:info, gettext("Farrowing restored."))}

        {:error, :service_reclosed} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("Cannot restore — the service was closed with a different outcome.")
           )}

        {:error, :conflicting_weaning} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("Cannot restore — a conflicting weaning exists.")
           )}

        {:error, :not_deleted} ->
          {:noreply, put_flash(socket, :error, gettext("Farrowing is not deleted."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not restore farrowing."))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

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

  def handle_event("filter_weaned", params, socket) do
    query = %{
      "tab" => "weaned",
      "q" => params["q"] || "",
      "page" => 1
    }

    {:noreply, push_patch(socket, to: breeding_path(socket, query))}
  end

  def handle_event("delete_weaning", %{"weaning-id" => id}, socket) do
    scope = socket.assigns.current_scope

    if socket.assigns.can_record do
      weaning = Breeding.get_weaning!(scope, String.to_integer(id))

      case Breeding.delete_weaning(scope, weaning) do
        {:ok, _} ->
          {:noreply,
           socket
           |> load_tab()
           |> put_flash(:info, gettext("Weaning deleted. Restore from the Deleted tab."))}

        {:error, :weaning_has_activity} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("Cannot delete — the litter has moved or changed since weaning.")
           )}

        {:error, :already_deleted} ->
          {:noreply, put_flash(socket, :error, gettext("Weaning is already deleted."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not delete weaning."))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("restore_weaning", %{"weaning-id" => id}, socket) do
    scope = socket.assigns.current_scope

    if socket.assigns.can_record do
      weaning = Breeding.get_deleted_weaning!(scope, String.to_integer(id))

      case Breeding.restore_weaning(scope, weaning) do
        {:ok, _} ->
          {:noreply,
           socket
           |> load_tab()
           |> put_flash(:info, gettext("Weaning restored."))}

        {:error, :conflicting_weaning} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("Cannot restore — another weaning already exists for this farrowing.")
           )}

        {:error, :farrowing_deleted} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("Cannot restore — the farrowing has been deleted.")
           )}

        {:error, :not_deleted} ->
          {:noreply, put_flash(socket, :error, gettext("Weaning is not deleted."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not restore weaning."))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("paginate", %{"page" => page}, socket) do
    {:noreply,
     push_patch(socket,
       to: breeding_path(socket, %{"tab" => socket.assigns.tab, "page" => page})
     )}
  end

  # ── Helpers ────────────────────────────────────────────────────────

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
             |> load_tab()
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
            {:noreply, assign(socket, svc: %{svc | error_message: format_cs_error(cs)})}

          {:error, other} ->
            {:noreply, assign(socket, svc: %{svc | error_message: inspect(other)})}
        end
    end
  end

  defp update_svc_from_params(socket, params) do
    svc = socket.assigns.svc
    backfill_params = Map.get(params, "backfill_sow", %{})

    backfill = %{
      breed: presence(Map.get(backfill_params, "breed")),
      dob: presence(Map.get(backfill_params, "dob"))
    }

    force_create = truthy?(Map.get(backfill_params, "force_create"))
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
        notes: presence(Map.get(params, "notes")),
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
          {%{svc | sow_state: :empty, similar_tags: [], resolved_sow_id: nil},
           %{ac | pen_label: nil}}

        true ->
          case Animals.find_by_ear_tag(scope, tag) do
            %{id: id} = sow ->
              svc = %{svc | sow_state: :existing, similar_tags: [], resolved_sow_id: id}
              svc = if is_nil(svc.pen_id), do: %{svc | pen_id: sow.current_pen_id}, else: svc
              {svc, maybe_preselect_pen(%{ac | pen_label: nil}, scope, sow)}

            nil ->
              ac = %{ac | pen_label: nil}

              case Animals.similar_ear_tags(scope, tag) do
                [] ->
                  {%{svc | sow_state: :new, similar_tags: [], resolved_sow_id: nil}, ac}

                tags ->
                  state = if svc.force_create, do: :similar_overridable, else: :similar
                  {%{svc | sow_state: state, similar_tags: tags, resolved_sow_id: nil}, ac}
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
  defp sow_input_class(_), do: ""

  defp sow_state_text(:existing), do: gettext("✓ Existing sow on file")
  defp sow_state_text(:new), do: gettext("+ New tag — will register on save")
  defp sow_state_text(:similar), do: gettext("⚠ Looks similar to an existing tag")

  defp sow_state_text(:similar_overridable),
    do: gettext("⚠ Override active — will create as new sow")

  defp sow_state_text(_), do: gettext("Type a tag to begin")

  defp presence(nil), do: nil
  defp presence(""), do: nil

  defp presence(s) when is_binary(s) do
    case String.trim(s) do
      "" -> nil
      v -> v
    end
  end

  defp truthy?("true"), do: true
  defp truthy?(true), do: true
  defp truthy?(_), do: false

  defp format_cs_error(%Ecto.Changeset{errors: errors}) do
    case errors do
      [{field, {msg, _}} | _] -> "#{field}: #{msg}"
      _ -> gettext("Validation failed")
    end
  end

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

  defp load_tab(%{assigns: %{tab: "deleted"}} = socket) do
    scope = socket.assigns.current_scope
    services = Breeding.list_deleted_services(scope)
    farrowings = Breeding.list_deleted_farrowings(scope)
    weanings = Breeding.list_deleted_weanings(scope)

    socket
    |> assign(
      total: length(services) + length(farrowings) + length(weanings),
      deleted_services_empty: services == [],
      deleted_farrowings_empty: farrowings == [],
      deleted_weanings_empty: weanings == []
    )
    |> stream(:deleted, services, reset: true)
    |> stream(:deleted_farrowings, farrowings, reset: true)
    |> stream(:deleted_weanings, weanings, reset: true)
  end

  defp load_tab(%{assigns: %{tab: "weaned"}} = socket) do
    scope = socket.assigns.current_scope
    filters = socket.assigns.filters
    rows = Breeding.list_recent_weanings(scope, search: filters.q)

    socket
    |> assign(total: length(rows))
    |> stream(:weaned, rows, reset: true)
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
  defp param_tab("weaned"), do: "weaned"
  defp param_tab("deleted"), do: "deleted"
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
      svc: nil,
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
