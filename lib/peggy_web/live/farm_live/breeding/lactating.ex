defmodule PeggyWeb.FarmLive.Breeding.Lactating do
  @moduledoc """
  Lactating tab of the Breeding section. Owns the weaning form, litter
  death / fostering / ledger modals, and the lactating sows list.
  """
  use PeggyWeb, :live_view

  alias Peggy.{Breeding, Locations, Policy}
  alias Peggy.Breeding.{Weaning, LitterEvent}
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
        </.header>

        <section class="mt-4">
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
                  <td class="py-1.5 text-right">
                    <button
                      phx-click="show_ledger"
                      phx-value-farrowing-id={entry.farrowing.id}
                      class="btn btn-xs btn-outline btn-primary font-mono gap-1"
                      title={gettext("View litter ledger")}
                    >
                      {entry.surviving}
                      <.icon name="hero-book-open" class="size-3" />
                    </button>
                  </td>
                  <td class="py-1.5 font-mono">
                    {entry.farrowing.pen &&
                      "#{entry.farrowing.pen.house.code}/#{entry.farrowing.pen.code}"}
                  </td>
                  <td class="py-1.5 text-right font-mono">
                    {Date.diff(Date.utc_today(), entry.farrowing.farrowed_at)}
                  </td>
                  <td :if={@can_record} class="py-1.5 text-right">
                    <button
                      phx-click="new_litter_death"
                      phx-value-farrowing-id={entry.farrowing.id}
                      class="btn btn-ghost btn-xs text-error/70"
                      title={gettext("Record pre-wean death")}
                    >
                      {gettext("Death")}
                    </button>
                    <button
                      phx-click="new_litter_foster"
                      phx-value-farrowing-id={entry.farrowing.id}
                      class="btn btn-ghost btn-xs"
                      title={gettext("Record fostering")}
                    >
                      {gettext("Foster")}
                    </button>
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
                          "Delete this farrowing? The sow will be reverted and the service reopened."
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

          <Shared.pagination page={@page} per_page={@per_page} total={@total} />
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
                    class="btn btn-ghost btn-xs text-error/80"
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
              value={Shared.fv(@form, :destination_pen_id)}
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
       per_page: @per_page
     )
     |> stream_configure(:lactating, dom_id: &"farrowing-#{&1.farrowing.id}")
     |> stream(:lactating, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = %{
      q: params["q"] || "",
      age: Shared.param_age(params["age"]),
      pen_id: params["pen_id"] || ""
    }

    page = Shared.param_page(params["page"])

    {:noreply,
     socket
     |> assign(filters: filters, page: page)
     |> load_rows()}
  end

  # ── Events ─────────────────────────────────────────────────────────

  @impl true
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
       ac: Shared.default_ac(scope)
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
           |> load_rows()
           |> put_flash(:info, gettext("Weaning recorded."))}

        {:error, :already_weaned} ->
          {:noreply,
           socket
           |> close_form()
           |> load_rows()
           |> put_flash(:error, gettext("Already weaned."))}

        {:error, cs} ->
          {:noreply, assign(socket, :form, to_form(cs, as: :weaning))}
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
        "occurred_at" => Date.utc_today(),
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
        "occurred_at" => Date.utc_today(),
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
           |> put_flash(:info, gettext("Pre-wean death recorded."))}

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
               |> put_flash(:info, gettext("Fostering recorded."))}

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
      "page" => 1
    }

    {:noreply, push_patch(socket, to: Shared.tab_path(socket, "lactating", query))}
  end

  def handle_event("paginate", %{"page" => page}, socket) do
    {:noreply, push_patch(socket, to: Shared.tab_path(socket, "lactating", %{"page" => page}))}
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp load_rows(socket) do
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
end
