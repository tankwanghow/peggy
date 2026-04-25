defmodule PeggyWeb.FarmLive.AnimalDetail do
  use PeggyWeb, :live_view

  alias Peggy.Animals
  alias Peggy.Animals.{Animal, Movement}
  alias Peggy.Breeding
  alias Peggy.FarmClock
  alias Peggy.Locations
  alias Peggy.Policy

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-5xl">
        <div class="text-sm text-base-content/60 mb-1">
          <.link
            navigate={~p"/farms/#{@current_scope.farm.slug}/animals"}
            class="text-primary underline hover:text-primary/80"
          >
            ← {gettext("All animals")}
          </.link>
        </div>
        <.header>
          <span class="font-mono">{@animal.ear_tag || "##{@animal.id}"}</span>
          <.status_badge status={@animal.status} class="ml-2" />
          <span class="ml-2 text-base-content/60 text-base font-normal">
            {String.capitalize(@animal.stage)} · {String.capitalize(@animal.tracking_type)}
            <%= if @animal.tracking_type == "batch" do %>
              ({@animal.quantity})
            <% end %>
            <%= if @animal.breed do %>
              · {@animal.breed}
            <% end %>
            <%= if @animal.dob do %>
              · {@animal.dob}
            <% end %>
            <%= if @animal.rfid do %>
              · <span class="font-mono">{@animal.rfid}</span>
            <% end %>
            <%= if @animal.tracking_type == "individual" do %>
              · <span class="font-mono">{pen_label(@animal) || "—"}</span>
            <% end %>
            <%= if @animal.tracking_type == "individual" and @animal.sire do %>
              · {gettext("Sire")}:
              <.link
                navigate={~p"/farms/#{@current_scope.farm.slug}/animals/#{@animal.sire.id}"}
                class="font-mono text-primary underline underline-offset-2 decoration-dotted hover:decoration-solid"
              >
                {@animal.sire.ear_tag}
              </.link>
            <% end %>
            <%= if @animal.tracking_type == "individual" and @animal.dam do %>
              · {gettext("Dam")}:
              <.link
                navigate={~p"/farms/#{@current_scope.farm.slug}/animals/#{@animal.dam.id}"}
                class="font-mono text-primary underline underline-offset-2 decoration-dotted hover:decoration-solid"
              >
                {@animal.dam.ear_tag}
              </.link>
            <% end %>
            <%= if @animal.stage == "sow" do %>
              · {gettext("Parity")}: {@parity}
              <%= if (@animal.legacy_parity || 0) > 0 do %>
                <span class="text-base-content/50">
                  ({@animal.legacy_parity} {gettext("prior to Peggy")})
                </span>
              <% end %>
            <% end %>
          </span>
          <:actions>
            <.link
              :if={
                @can_move && @animal.tracking_type == "batch" &&
                  Peggy.Animals.Animal.present_status?(@animal.status)
              }
              navigate={~p"/farms/#{@current_scope.farm.slug}/animals/#{@animal.id}/batch-entry"}
              class="btn btn-sm"
            >
              {gettext("Batch Transfer")}
            </.link>
            <.button
              :if={
                @can_manage && @animal.tracking_type == "batch" &&
                  Peggy.Animals.Animal.present_status?(@animal.status) &&
                  promote_targets(@animal) != []
              }
              phx-click="promote_open"
              class="btn btn-sm"
            >
              {gettext("Promote stage")}
            </.button>
            <.button
              :if={@can_manage && Peggy.Animals.Animal.present_status?(@animal.status)}
              phx-click="edit"
              class="btn btn-primary btn-sm"
            >
              {gettext("Edit")}
            </.button>
          </:actions>
        </.header>

        <div
          :if={@animal.needs_review}
          class="mt-4 rounded-md border border-warning/40 bg-warning/10 p-3 flex items-start gap-3"
        >
          <.icon name="hero-exclamation-triangle-micro" class="size-5 text-warning mt-0.5" />
          <div class="flex-1 text-sm">
            <p class="font-medium">
              {gettext("This record needs review.")}
            </p>
            <p class="text-base-content/70">
              {if @animal.inferred,
                do:
                  gettext(
                    "It was auto-created from a backfill (%{via}). Verify the details below — dob, breed, sire, dam, pen — then confirm.",
                    via: @animal.created_via || "backfill"
                  ),
                else: gettext("Verify the details below, then confirm.")}
            </p>
          </div>
          <.button
            :if={@can_manage}
            phx-click="mark_reviewed"
            data-confirm={gettext("Confirm this record as reviewed?")}
            class="btn btn-sm btn-warning"
          >
            {gettext("Confirm reviewed")}
          </.button>
        </div>

        <div :if={@animal.notes} class="mt-4 text-sm">
          <span class="text-base-content/60">{gettext("Notes")}</span>
          <p class="whitespace-pre-wrap">{@animal.notes}</p>
        </div>

        <%!-- Placements (batch only) --%>
        <section :if={@animal.tracking_type == "batch"} class="mt-6">
          <h3 class="font-semibold">
            {gettext("Current placements")}
            <span class="text-base-content/60 font-normal text-sm">
              ({@animal.quantity} {gettext("total")})
            </span>
          </h3>
          <div :if={@placements != []} class="mt-2 flex flex-wrap gap-2 text-sm font-mono">
            <span
              :for={p <- @placements}
              class="inline-flex items-center gap-1 rounded bg-base-200 px-2 py-0.5"
            >
              {p.pen.house.code}-{p.pen.code}
              <span class="text-base-content/60">×{p.quantity}</span>
            </span>
          </div>
          <p :if={@placements == []} class="mt-2 text-sm text-base-content/60">
            {gettext("Not currently placed in any pen.")}
          </p>
          <p :if={unplaced_count(@animal, @placements) > 0} class="mt-2 text-sm text-warning">
            {gettext("Currently has %{n} animals unplaced in this batch",
              n: unplaced_count(@animal, @placements)
            )}
          </p>
        </section>

        <%!-- Offspring --%>
        <section :if={@offspring != []} class="mt-8">
          <h3 class="font-semibold">{gettext("Offspring")} ({length(@offspring)})</h3>
          <ul class="mt-2 space-y-1 text-sm">
            <li :for={o <- @offspring} class="flex gap-2">
              <.link
                navigate={~p"/farms/#{@current_scope.farm.slug}/animals/#{o.id}"}
                class="font-mono text-primary underline underline-offset-2 decoration-dotted hover:decoration-solid"
              >
                {o.ear_tag || "##{o.id}"}
              </.link>
              <span class="text-base-content/60">
                {String.capitalize(o.stage)} · {String.capitalize(o.status)}
              </span>
            </li>
          </ul>
        </section>

        <%!-- Movement form --%>
        <section :if={@can_move && Peggy.Animals.Animal.present_status?(@animal.status)} class="mt-8">
          <h3 class="font-semibold mb-2">{gettext("Record movement")}</h3>
          <.form
            for={@move_form}
            id="movement-form"
            phx-submit="record_movement"
            phx-change="validate_movement"
            class="grid grid-cols-2 md:grid-cols-7 gap-1"
          >
            <.input
              field={@move_form[:reason]}
              type="select"
              label={gettext("Reason")}
              options={reason_options(@animal)}
            />
            <.autocomplete
              :if={
                @animal.tracking_type == "batch" and
                  Phoenix.HTML.Form.input_value(@move_form, :reason) not in [
                    "placement",
                    "adjustment_gain"
                  ]
              }
              id="move-from-pen-picker"
              label={gettext("From pen")}
              name="movement[from_pen_id]"
              value={Phoenix.HTML.Form.input_value(@move_form, :from_pen_id)}
              items={@ac.from_pen_items}
              selected_label={@ac.from_pen_label}
              class="w-full input font-mono"
              placeholder={gettext("Search pens...")}
            />
            <.autocomplete
              :if={
                Phoenix.HTML.Form.input_value(@move_form, :reason) in [
                  "placement",
                  "pen_transfer",
                  "adjustment_gain"
                ]
              }
              id="move-pen-picker"
              label={gettext("To pen")}
              name="movement[to_pen_id]"
              value={Phoenix.HTML.Form.input_value(@move_form, :to_pen_id)}
              items={@ac.move_pen_items}
              selected_label={@ac.move_pen_label}
              class="input font-mono"
              placeholder={gettext("Search pens...")}
            />
            <.input
              :if={@animal.tracking_type == "batch"}
              field={@move_form[:quantity]}
              type="number"
              label={gettext("Quantity")}
              min="1"
            />
            <.input
              field={@move_form[:moved_at]}
              type="date"
              label={gettext("When")}
            />
            <.input field={@move_form[:notes]} type="text" label={gettext("Notes")} />
            <div class="fieldset mb-2">
              <span class="label mb-1">&nbsp;</span>
              <.button class="btn btn-primary btn-sm" phx-disable-with={gettext("Recording...")}>
                {gettext("Record")}
              </.button>
            </div>
          </.form>
        </section>

        <%!-- Movement history (batches only) --%>
        <section :if={@animal.tracking_type == "batch"} class="mt-8">
          <h3 class="font-semibold mb-2">{gettext("Movement history")}</h3>
          <table class="table table-sm w-full text-sm">
            <thead class="text-left text-base-content/60">
              <tr>
                <th class="py-2">{gettext("When")}</th>
                <th class="py-2">{gettext("Reason")}</th>
                <th class="py-2">{gettext("From pen")}</th>
                <th class="py-2">{gettext("To pen")}</th>
                <th class="py-2">{gettext("Qty")}</th>
                <th class="py-2">{gettext("Dam")}</th>
                <th class="py-2">{gettext("Notes")}</th>
                <th :if={@can_move} class="py-2"></th>
              </tr>
            </thead>
            <tbody id="movements" phx-update="stream">
              <tr
                :for={{dom_id, m} <- @streams.movements}
                id={dom_id}
                class="border-t border-base-200"
              >
                <td class="py-2 whitespace-nowrap">{m.moved_at}</td>
                <td class="py-2">{String.replace(m.reason, "_", " ")}</td>
                <td class="py-2 font-mono">
                  {m.from_pen && "#{m.from_pen.house.code}-#{m.from_pen.code}"}
                </td>
                <td class="py-2 font-mono">
                  {m.to_pen && "#{m.to_pen.house.code}-#{m.to_pen.code}"}
                </td>
                <td class="py-2">{m.quantity}</td>
                <td class="py-2 font-mono">{wean_sow_tag(m)}</td>
                <td class="py-2 text-base-content/60">{m.notes}</td>
                <td :if={@can_move} class="py-2 text-right">
                  <button
                    :if={m.id == @latest_movement_id}
                    phx-click="undo_last_movement"
                    class="btn btn-ghost btn-sm text-error"
                    data-confirm={
                      gettext("Undo this movement? This will reverse all related state changes.")
                    }
                  >
                    {gettext("Undo")}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
          <p :if={@movement_count == 0} class="mt-2 text-sm text-base-content/60">
            {gettext("No movements recorded.")}
          </p>
        </section>

        <%!-- Unified history (individuals only): movements + breeding --%>
        <section :if={@animal.tracking_type == "individual"} class="mt-8">
          <h3 class="font-semibold mb-2">{gettext("History")}</h3>
          <table class="table table-sm w-full text-sm">
            <thead class="text-left text-base-content/60">
              <tr>
                <th class="py-2">{gettext("When")}</th>
                <th class="py-2">{gettext("Event")}</th>
                <th class="py-2">{gettext("Detail")}</th>
                <th class="py-2">{gettext("From → To")}</th>
                <th class="py-2">{gettext("Notes")}</th>
                <th :if={@can_move} class="py-2"></th>
              </tr>
            </thead>
            <tbody id="history" phx-update="stream">
              <tr
                :for={{dom_id, row} <- @streams.history}
                id={dom_id}
                class="border-t border-base-200"
              >
                <td class="py-2 whitespace-nowrap">{history_date(row)}</td>
                <td class="py-2">{history_event_label(row)}</td>
                <td class="py-2 text-base-content/80">
                  <.history_detail row={row} current_scope={@current_scope} animal={@animal} />
                </td>
                <td class="py-2 font-mono">{history_from_to(row)}</td>
                <td class="py-2 text-base-content/60">{history_notes(row)}</td>
                <td :if={@can_move} class="py-2 text-right">
                  <button
                    :if={history_undoable?(row, @latest_movement_id)}
                    phx-click="undo_last_movement"
                    class="btn btn-ghost btn-sm text-error"
                    data-confirm={
                      gettext("Undo this movement? This will reverse all related state changes.")
                    }
                  >
                    {gettext("Undo")}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
          <p :if={@history_count == 0} class="mt-2 text-sm text-base-content/60">
            {gettext("No history recorded.")}
          </p>
        </section>

        <%!-- Promote stage modal --%>
        <div
          :if={@promote_stage}
          id="promote-modal"
          class="fixed inset-0 bg-black/40 flex items-center justify-center z-50"
        >
          <div
            class="bg-base-100 rounded p-6 w-full max-w-md"
            phx-click-away="promote_cancel"
            phx-window-keydown="promote_cancel"
            phx-key="escape"
          >
            <h3 class="text-lg font-semibold mb-3">{gettext("Promote batch stage")}</h3>
            <p class="text-sm text-base-content/60 mb-3">
              {gettext("Current stage")}:
              <span class="font-medium text-base-content">{String.capitalize(@animal.stage)}</span>
              · {@animal.quantity} {gettext("animals across")} {length(@placements)} {gettext(
                "pen(s)"
              )}
            </p>
            <form phx-submit="promote_submit">
              <.input
                name="new_stage"
                value={@promote_stage}
                type="select"
                label={gettext("New stage")}
                options={promote_targets(@animal)}
              />
              <div class="mt-4 flex gap-2 justify-end">
                <button type="button" phx-click="promote_cancel" class="btn btn-ghost">
                  {gettext("Cancel")}
                </button>
                <.button class="btn btn-primary" phx-disable-with={gettext("Promoting...")}>
                  {gettext("Promote")}
                </.button>
              </div>
            </form>
          </div>
        </div>

        <%!-- Edit modal --%>
        <div
          :if={@edit_form}
          id="edit-modal"
          class="fixed inset-0 bg-black/40 flex items-center justify-center z-50"
        >
          <div
            class="bg-base-100 rounded p-4 sm:p-6 w-full max-w-2xl mx-4 max-h-[85vh] overflow-y-auto"
            phx-click-away="cancel_edit"
            phx-window-keydown="cancel_edit"
            phx-key="escape"
          >
            <h3 class="text-lg font-semibold mb-3">{gettext("Edit animal")}</h3>
            <.form
              for={@edit_form}
              id="edit-animal-form"
              phx-submit="save_edit"
              phx-change="validate_edit"
              class="grid grid-cols-2 gap-x-4 gap-y-1"
            >
              <.input
                field={@edit_form[:ear_tag]}
                type="text"
                label={
                  if @animal.tracking_type == "batch",
                    do: gettext("Batch number"),
                    else: gettext("Ear tag")
                }
                class="w-full input font-mono"
                required={@animal.tracking_type == "individual"}
              />
              <.input
                :if={@animal.tracking_type == "individual"}
                field={@edit_form[:rfid]}
                type="text"
                label={gettext("RFID")}
                class="w-full input font-mono"
              />
              <.input
                field={@edit_form[:stage]}
                type="select"
                label={gettext("Stage")}
                options={
                  Enum.map(
                    Animal.stages_for(@animal.tracking_type),
                    &{String.capitalize(&1), &1}
                  )
                }
              />
              <.input field={@edit_form[:breed]} type="text" label={gettext("Breed")} />
              <.input field={@edit_form[:dob]} type="date" label={gettext("Date of birth")} />
              <.input
                :if={@animal.tracking_type == "individual" and @animal.stage == "sow"}
                field={@edit_form[:legacy_parity]}
                type="number"
                label={gettext("Legacy parity")}
                min="0"
              />
              <.autocomplete
                :if={@animal.tracking_type == "individual"}
                id="edit-sire-picker"
                label={gettext("Sire")}
                name="animal[sire_id]"
                value={Phoenix.HTML.Form.input_value(@edit_form, :sire_id)}
                items={@ac.sire_items}
                selected_label={@ac.sire_label}
                class="w-full input font-mono"
                placeholder={gettext("Search by ear tag...")}
              />
              <.autocomplete
                :if={@animal.tracking_type == "individual"}
                id="edit-dam-picker"
                label={gettext("Dam")}
                name="animal[dam_id]"
                value={Phoenix.HTML.Form.input_value(@edit_form, :dam_id)}
                items={@ac.dam_items}
                selected_label={@ac.dam_label}
                class="w-full input font-mono"
                placeholder={gettext("Search by ear tag...")}
              />
              <div class="col-span-2">
                <.input field={@edit_form[:notes]} type="textarea" label={gettext("Notes")} />
              </div>
              <div class="col-span-2 flex items-center gap-2 text-sm text-base-content/60">
                <span>{gettext("Status")}:</span>
                <.status_badge status={@animal.status} />
                <span class="text-xs">
                  {gettext(
                    "Status changes through service, farrowing, weaning, movement, or treatment — not this form."
                  )}
                </span>
              </div>
              <div class="col-span-2 flex gap-2 justify-end">
                <button type="button" phx-click="cancel_edit" class="btn btn-ghost">
                  {gettext("Cancel")}
                </button>
                <.button class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
                  {gettext("Save")}
                </.button>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    animal = Animals.get_animal!(scope, String.to_integer(id))
    offspring = Animals.list_offspring(scope, animal)
    placements = Animals.list_placements(scope, animal)
    movements = Animals.list_movements(scope, animal)
    {services, litter_events} = breeding_data(scope, animal)
    history = build_history(animal, movements, services, litter_events)

    move_cs =
      Animals.change_movement(new_movement(socket.assigns.current_scope, animal, placements), %{})

    latest_id = movements |> List.first() |> then(&(&1 && &1.id))
    parity = sow_parity(scope, animal)

    {:ok,
     socket
     |> assign(
       animal: animal,
       offspring: offspring,
       placements: placements,
       parity: parity,
       can_manage: Policy.can?(scope, :manage_animals),
       can_move: Policy.can?(scope, :record_movement),
       edit_form: nil,
       move_form: to_form(move_cs, as: :movement),
       movement_count: length(movements),
       latest_movement_id: latest_id,
       history_count: length(history),
       ac: move_ac_items(scope, placements),
       promote_stage: nil
     )
     |> stream(:movements, movements)
     |> stream(:history, history)}
  end

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

  defp build_history(_animal, _movements, _services, _litter_events), do: []

  defp row_from_movement(m) do
    %{
      id: "m-#{m.id}",
      date: m.moved_at,
      priority: 2,
      kind: :movement,
      data: m
    }
  end

  defp rows_from_service(s, animal_id) do
    open = %{
      id: "s-#{s.id}",
      date: s.served_at,
      priority: 1,
      kind: :service,
      data: %{service: s, animal_id: animal_id}
    }

    close =
      if s.result && s.result_at do
        closed_kind =
          case s.result do
            "farrowing" -> :farrowing
            _ -> :service_closed
          end

        %{
          id: "sc-#{s.id}",
          date: s.result_at,
          priority: if(closed_kind == :farrowing, do: 3, else: 6),
          kind: closed_kind,
          data: %{service: s, animal_id: animal_id}
        }
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
    %{
      id: "le-#{e.id}",
      date: e.occurred_at,
      priority: 4,
      kind: :litter_event,
      data: e
    }
  end

  @impl true
  def handle_event("validate_movement", %{"movement" => params}, socket) do
    cs = Animals.change_movement(%Movement{}, params) |> Map.put(:action, :validate)
    socket = assign(socket, :move_form, to_form(cs, as: :movement))

    # When the user switches reason, one or both pen pickers may no
    # longer be rendered — reset whichever is hidden so a stale value
    # doesn't leak into the submission.
    reason = Map.get(params, "reason")

    socket =
      socket
      |> maybe_reset_picker(
        reason not in ["placement", "pen_transfer", "adjustment_gain"],
        "move-pen-picker"
      )
      |> maybe_reset_picker(
        reason in ["placement", "adjustment_gain"],
        "move-from-pen-picker"
      )

    {:noreply, socket}
  end

  def handle_event("record_movement", %{"movement" => params}, socket) do
    scope = socket.assigns.current_scope
    animal = socket.assigns.animal

    case Animals.record_movement(scope, animal, params) do
      {:ok, _} ->
        animal = Animals.get_animal!(scope, animal.id)
        placements = Animals.list_placements(scope, animal)
        movements = Animals.list_movements(scope, animal)
        {services, litter_events} = breeding_data(scope, animal)
        history = build_history(animal, movements, services, litter_events)

        move_cs =
          Animals.change_movement(
            new_movement(socket.assigns.current_scope, animal, placements),
            %{}
          )

        {:noreply,
         socket
         |> assign(
           animal: animal,
           placements: placements,
           movement_count: length(movements),
           history_count: length(history)
         )
         |> assign(:move_form, to_form(move_cs, as: :movement))
         |> assign(:ac, move_ac_items(scope, placements))
         |> stream(:movements, movements, reset: true)
         |> stream(:history, history, reset: true)
         |> push_event("ac:reset", %{id: "move-pen-picker"})
         |> push_event("ac:reset", %{id: "move-from-pen-picker"})
         |> put_flash(:info, gettext("Movement recorded."))}

      {:error, cs} ->
        cs = Map.put(cs, :action, :insert)

        {:noreply,
         socket
         |> assign(:move_form, to_form(cs, as: :movement))
         |> put_flash(:error, movement_error_flash(cs))}
    end
  end

  def handle_event("undo_last_movement", _, socket) do
    if socket.assigns.can_move do
      scope = socket.assigns.current_scope
      animal = socket.assigns.animal

      case Animals.undo_last_movement(scope, animal) do
        {:ok, _} ->
          animal = Animals.get_animal!(scope, animal.id)
          placements = Animals.list_placements(scope, animal)
          movements = Animals.list_movements(scope, animal)
          {services, litter_events} = breeding_data(scope, animal)
          history = build_history(animal, movements, services, litter_events)
          latest_id = movements |> List.first() |> then(&(&1 && &1.id))

          move_cs =
            Animals.change_movement(
              new_movement(socket.assigns.current_scope, animal, placements),
              %{}
            )

          {:noreply,
           socket
           |> assign(
             animal: animal,
             placements: placements,
             movement_count: length(movements),
             latest_movement_id: latest_id,
             history_count: length(history),
             move_form: to_form(move_cs, as: :movement),
             ac: move_ac_items(scope, placements)
           )
           |> stream(:movements, movements, reset: true)
           |> stream(:history, history, reset: true)
           |> put_flash(:info, gettext("Movement undone."))}

        {:error, :no_movements} ->
          {:noreply, put_flash(socket, :error, gettext("No movements to undo."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not undo movement."))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("promote_open", _, socket) do
    if socket.assigns.can_manage do
      default = promote_targets(socket.assigns.animal) |> List.first() |> elem(1)
      {:noreply, assign(socket, :promote_stage, default)}
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("promote_cancel", _, socket) do
    {:noreply, assign(socket, :promote_stage, nil)}
  end

  def handle_event("mark_reviewed", _, socket) do
    if socket.assigns.can_manage do
      scope = socket.assigns.current_scope

      case Animals.mark_reviewed(scope, socket.assigns.animal) do
        {:ok, _} ->
          animal = Animals.get_animal!(scope, socket.assigns.animal.id)

          {:noreply,
           socket
           |> assign(animal: animal)
           |> put_flash(:info, gettext("Record confirmed as reviewed."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not mark as reviewed."))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("promote_submit", %{"new_stage" => new_stage}, socket) do
    if socket.assigns.can_manage do
      scope = socket.assigns.current_scope

      case Animals.promote_batch_stage(scope, socket.assigns.animal, new_stage) do
        {:ok, _} ->
          animal = Animals.get_animal!(scope, socket.assigns.animal.id)

          {:noreply,
           socket
           |> assign(animal: animal, promote_stage: nil)
           |> put_flash(:info, gettext("Stage updated."))}

        {:error, %Ecto.Changeset{} = cs} ->
          msg =
            cs.errors
            |> Enum.map(fn {f, {m, _}} -> "#{f} #{m}" end)
            |> Enum.join(", ")

          {:noreply, put_flash(socket, :error, msg)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not promote stage."))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("edit", _, socket) do
    if socket.assigns.can_manage do
      scope = socket.assigns.current_scope
      animal = socket.assigns.animal
      cs = Animals.change_animal(animal, %{})

      ac =
        scope
        |> edit_ac_items(animal, socket.assigns.placements)
        |> maybe_preselect_parent(:sire, socket, animal)
        |> maybe_preselect_parent(:dam, socket, animal)

      {:noreply,
       assign(socket,
         edit_form: to_form(cs, as: :animal),
         ac: ac
       )}
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply,
     assign(socket,
       edit_form: nil,
       ac: move_ac_items(socket.assigns.current_scope, socket.assigns.placements)
     )}
  end

  def handle_event("validate_edit", %{"animal" => params}, socket) do
    cs =
      Animals.change_animal(socket.assigns.animal, params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :edit_form, to_form(cs, as: :animal))}
  end

  def handle_event("save_edit", %{"animal" => params}, socket) do
    if socket.assigns.can_manage do
      scope = socket.assigns.current_scope

      case Animals.update_animal(scope, socket.assigns.animal, params) do
        {:ok, _} ->
          animal = Animals.get_animal!(scope, socket.assigns.animal.id)
          placements = Animals.list_placements(scope, animal)

          {:noreply,
           socket
           |> assign(
             animal: animal,
             placements: placements,
             parity: sow_parity(scope, animal),
             edit_form: nil,
             ac: move_ac_items(scope, placements)
           )
           |> put_flash(:info, gettext("Animal updated."))}

        {:error, cs} ->
          {:noreply, assign(socket, :edit_form, to_form(cs, as: :animal))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  ## Autocomplete state helpers

  defp maybe_reset_picker(socket, true, id), do: push_event(socket, "ac:reset", %{id: id})
  defp maybe_reset_picker(socket, false, _), do: socket

  defp move_ac_items(scope, placements) do
    %{
      move_pen_items: pen_items(scope),
      move_pen_label: nil,
      from_pen_items: placement_items(placements),
      from_pen_label: nil,
      sire_items: [],
      sire_label: nil,
      dam_items: [],
      dam_label: nil
    }
  end

  defp edit_ac_items(scope, animal, placements) do
    animals =
      scope
      |> Animals.list_animals(status: "present")
      |> Enum.reject(&(&1.id == animal.id))

    %{
      move_pen_items: pen_items(scope),
      move_pen_label: nil,
      from_pen_items: placement_items(placements),
      from_pen_label: nil,
      sire_items: animal_items(animals, "boar"),
      sire_label: nil,
      dam_items: animal_items(animals, "sow"),
      dam_label: nil
    }
  end

  defp placement_items(placements) do
    Enum.map(placements, fn p ->
      %{id: p.pen_id, label: "#{p.pen.house.code}-#{p.pen.code} (#{p.quantity})"}
    end)
  end

  defp pen_items(scope) do
    scope
    |> Locations.list_all_pens()
    |> Enum.map(&%{id: &1.id, label: "#{&1.house.code}-#{&1.code}"})
  end

  defp animal_items(animals, stage) do
    animals
    |> Enum.filter(&(&1.stage == stage and &1.ear_tag != nil))
    |> Enum.map(&%{id: &1.id, label: &1.ear_tag})
  end

  defp maybe_preselect_parent(ac, :sire, socket, %{sire_id: id}) when not is_nil(id) do
    animal = Animals.get_animal!(socket.assigns.current_scope, id)
    %{ac | sire_label: animal.ear_tag}
  end

  defp maybe_preselect_parent(ac, :dam, socket, %{dam_id: id}) when not is_nil(id) do
    animal = Animals.get_animal!(socket.assigns.current_scope, id)
    %{ac | dam_label: animal.ear_tag}
  end

  defp maybe_preselect_parent(ac, _, _, _), do: ac

  # Adjustments (loss/gain) are batch-only — they don't make sense for
  # individuals since the count is always 1.
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

  # Stages a batch can be promoted to, excluding its current stage.
  defp promote_targets(%Animal{tracking_type: "batch", stage: current}) do
    Animal.stages_for("batch")
    |> Enum.reject(&(&1 == current))
    |> Enum.map(&{String.capitalize(&1), &1})
  end

  defp promote_targets(_), do: []

  defp wean_sow_tag(%Movement{reason: "wean", weaning: %{farrowing: %{sow: %{ear_tag: tag}}}}),
    do: tag

  defp wean_sow_tag(_), do: nil

  defp service_role(%{sow_id: id}, id), do: gettext("Sow")
  defp service_role(%{boar_id: id}, id), do: gettext("Boar")
  defp service_role(_, _), do: ""

  defp service_mate(%{sow_id: id, boar: boar}, id), do: boar
  defp service_mate(%{boar_id: id, sow: sow}, id), do: sow
  defp service_mate(_, _), do: nil

  ## Unified history helpers

  defp history_date(%{date: d}), do: d

  defp history_event_label(%{kind: :movement, data: m}), do: String.replace(m.reason, "_", " ")
  defp history_event_label(%{kind: :service}), do: gettext("Service")
  defp history_event_label(%{kind: :farrowing}), do: gettext("Farrowing")
  defp history_event_label(%{kind: :service_closed}), do: gettext("Service closed")
  defp history_event_label(%{kind: :weaning}), do: gettext("Weaning")

  defp history_event_label(%{kind: :litter_event, data: %{kind: "death"}}),
    do: gettext("Piglet death")

  defp history_event_label(%{kind: :litter_event, data: %{kind: "foster_out"}}),
    do: gettext("Piglet foster-out")

  defp history_event_label(%{kind: :litter_event, data: %{kind: "foster_in"}}),
    do: gettext("Piglet foster-in")

  defp history_from_to(%{kind: :movement, data: m}) do
    from = m.from_pen && "#{m.from_pen.house.code}-#{m.from_pen.code}"
    to = m.to_pen && "#{m.to_pen.house.code}-#{m.to_pen.code}"

    case {from, to} do
      {nil, nil} -> ""
      {nil, t} -> "→ #{t}"
      {f, nil} -> "#{f} →"
      {f, t} -> "#{f} → #{t}"
    end
  end

  defp history_from_to(%{kind: :farrowing, data: %{service: %{farrowing: %{pen: pen}}}})
       when not is_nil(pen) do
    "→ #{pen.house.code}-#{pen.code}"
  end

  defp history_from_to(_), do: ""

  defp history_notes(%{kind: :movement, data: m}), do: m.notes
  defp history_notes(%{kind: :service, data: %{service: s}}), do: s.notes
  defp history_notes(%{kind: :service_closed, data: %{service: s}}), do: s.result_notes
  defp history_notes(%{kind: :farrowing, data: %{service: %{farrowing: f}}}), do: f.notes
  defp history_notes(%{kind: :weaning, data: %{weaning: w}}), do: w.notes
  defp history_notes(%{kind: :litter_event, data: e}), do: e.notes
  defp history_notes(_), do: nil

  defp history_undoable?(%{kind: :movement, data: %{id: id}}, latest_id), do: id == latest_id
  defp history_undoable?(_, _), do: false

  # Renders the Detail cell per row kind. Uses links for mate/counterpart
  # sow so the user can jump between animals.
  attr :row, :map, required: true
  attr :current_scope, :map, required: true
  attr :animal, :map, required: true

  defp history_detail(%{row: %{kind: :service}} = assigns) do
    ~H"""
    <span>
      {@row.data.service.service_type} · {service_role(@row.data.service, @animal.id)}
      <%= if mate = service_mate(@row.data.service, @animal.id) do %>
        · {gettext("mate")}
        <.link
          navigate={~p"/farms/#{@current_scope.farm.slug}/animals/#{mate.id}"}
          class="font-mono text-primary underline underline-offset-2 decoration-dotted hover:decoration-solid"
        >
          {mate.ear_tag}
        </.link>
      <% end %>
    </span>
    """
  end

  defp history_detail(%{row: %{kind: :farrowing}} = assigns) do
    ~H"""
    <span>
      {gettext("born")} {@row.data.service.farrowing.born_alive}
      <%= if (@row.data.service.farrowing.stillborn || 0) > 0 do %>
        · {gettext("stillborn")} {@row.data.service.farrowing.stillborn}
      <% end %>
      <%= if (@row.data.service.farrowing.mummified || 0) > 0 do %>
        · {gettext("mummified")} {@row.data.service.farrowing.mummified}
      <% end %>
    </span>
    """
  end

  defp history_detail(%{row: %{kind: :service_closed}} = assigns) do
    ~H"""
    <span>{String.replace(@row.data.service.result, "_", " ")}</span>
    """
  end

  defp history_detail(%{row: %{kind: :weaning}} = assigns) do
    assigns =
      assign(assigns,
        qty: assigns.row.data.weaning.weaned_count,
        age: Date.diff(assigns.row.data.weaning.weaned_at, assigns.row.data.farrowing.farrowed_at)
      )

    ~H"""
    <span>{gettext("qty")} {@qty} · {gettext("age")} {@age}d</span>
    """
  end

  defp history_detail(%{row: %{kind: :litter_event, data: %{kind: "death"}}} = assigns) do
    ~H"""
    <span>{@row.data.quantity}</span>
    """
  end

  defp history_detail(%{row: %{kind: :litter_event, data: %{kind: "foster_out"}}} = assigns) do
    ~H"""
    <span>
      {@row.data.quantity} →
      <.link
        :if={counterpart_sow(@row.data)}
        navigate={~p"/farms/#{@current_scope.farm.slug}/animals/#{counterpart_sow(@row.data).id}"}
        class="font-mono text-primary underline underline-offset-2 decoration-dotted hover:decoration-solid"
      >
        {gettext("sow")} {counterpart_sow(@row.data).ear_tag}
      </.link>
    </span>
    """
  end

  defp history_detail(%{row: %{kind: :litter_event, data: %{kind: "foster_in"}}} = assigns) do
    ~H"""
    <span>
      {@row.data.quantity} ←
      <.link
        :if={counterpart_sow(@row.data)}
        navigate={~p"/farms/#{@current_scope.farm.slug}/animals/#{counterpart_sow(@row.data).id}"}
        class="font-mono text-primary underline underline-offset-2 decoration-dotted hover:decoration-solid"
      >
        {gettext("sow")} {counterpart_sow(@row.data).ear_tag}
      </.link>
    </span>
    """
  end

  defp history_detail(assigns) do
    ~H"""
    """
  end

  defp counterpart_sow(%{counterpart_farrowing: %{sow: %{} = sow}}), do: sow
  defp counterpart_sow(_), do: nil

  defp unplaced_count(%Animal{quantity: total}, placements) do
    placed = Enum.reduce(placements, 0, fn p, acc -> acc + p.quantity end)
    total - placed
  end

  defp movement_error_flash(%Ecto.Changeset{errors: [{field, {msg, opts}} | _]}) do
    humanized = field |> to_string() |> String.replace("_", " ") |> String.capitalize()
    "#{humanized}: #{PeggyWeb.CoreComponents.translate_error({msg, opts})}"
  end

  defp movement_error_flash(_), do: gettext("Could not record movement.")

  # Seed a blank Movement for the form. Default to "placement" only when
  # there's still quantity in the batch that isn't placed anywhere yet —
  # that's the "just registered, now assign to pens" case.
  defp new_movement(scope, %Animal{tracking_type: "batch"} = animal, placements) do
    placed = Enum.reduce(placements, 0, fn p, acc -> acc + p.quantity end)
    reason = if placed < animal.quantity, do: "placement", else: "pen_transfer"
    %Movement{moved_at: FarmClock.today(scope), reason: reason}
  end

  defp new_movement(scope, %Animal{}, _),
    do: %Movement{moved_at: FarmClock.today(scope), reason: "pen_transfer"}

  ## Display helpers

  defp pen_label(animal) do
    case animal do
      %{current_pen: %{code: code, house: %{code: hcode}}} -> "#{hcode}-#{code}"
      %{current_pen: %{code: code}} -> code
      _ -> nil
    end
  end
end
