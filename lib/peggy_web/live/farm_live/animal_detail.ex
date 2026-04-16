defmodule PeggyWeb.FarmLive.AnimalDetail do
  use PeggyWeb, :live_view

  alias Peggy.Animals
  alias Peggy.Animals.{Animal, Movement}
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
          <span class={["ml-2 badge", status_badge_class(@animal.status)]}>
            {String.capitalize(@animal.status)}
          </span>
          <span class="ml-2 text-base-content/60 text-base font-normal">
            {String.capitalize(@animal.stage)} · {String.capitalize(@animal.tracking_type)}
            <%= if @animal.tracking_type == "batch" do %>
              ({@animal.quantity})
            <% end %>
            <%= if @animal.breed do %>
              · {@animal.breed}
            <% end %>
            <%= if @animal.sex do %>
              · {String.capitalize(@animal.sex)}
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
            <%= if @animal.sire do %>
              · {gettext("Sire")}:
              <.link
                navigate={~p"/farms/#{@current_scope.farm.slug}/animals/#{@animal.sire.id}"}
                class="font-mono text-primary hover:underline"
              >
                {@animal.sire.ear_tag}
              </.link>
            <% end %>
            <%= if @animal.dam do %>
              · {gettext("Dam")}:
              <.link
                navigate={~p"/farms/#{@current_scope.farm.slug}/animals/#{@animal.dam.id}"}
                class="font-mono text-primary hover:underline"
              >
                {@animal.dam.ear_tag}
              </.link>
            <% end %>
          </span>
          <:actions>
            <.link
              :if={@can_move && @animal.tracking_type == "batch" && @animal.status == "active"}
              navigate={~p"/farms/#{@current_scope.farm.slug}/animals/#{@animal.id}/batch-entry"}
              class="btn btn-sm"
            >
              {gettext("Batch Transfer")}
            </.link>
            <.button
              :if={@can_manage && @animal.status == "active"}
              phx-click="edit"
              class="btn btn-primary btn-sm"
            >
              {gettext("Edit")}
            </.button>
          </:actions>
        </.header>

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
              {p.pen.house.code}/{p.pen.code}
              <span class="text-base-content/60">×{p.quantity}</span>
            </span>
          </div>
          <p :if={@placements == []} class="mt-2 text-sm text-base-content/60">
            {gettext("Not currently placed in any pen.")}
          </p>
        </section>

        <%!-- Offspring --%>
        <section :if={@offspring != []} class="mt-8">
          <h3 class="font-semibold">{gettext("Offspring")} ({length(@offspring)})</h3>
          <ul class="mt-2 space-y-1 text-sm">
            <li :for={o <- @offspring} class="flex gap-2">
              <.link
                navigate={~p"/farms/#{@current_scope.farm.slug}/animals/#{o.id}"}
                class="font-mono text-primary hover:underline"
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
        <section :if={@can_move && @animal.status == "active"} class="mt-8">
          <h3 class="font-semibold mb-2">{gettext("Record movement")}</h3>
          <.form
            for={@move_form}
            id="movement-form"
            phx-submit="record_movement"
            phx-change="validate_movement"
            class="grid grid-cols-2 md:grid-cols-6 gap-3"
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
              placeholder={gettext("Search placements...")}
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
              class="w-full input font-mono"
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

        <%!-- Movement history --%>
        <section class="mt-8">
          <h3 class="font-semibold mb-2">{gettext("Movement history")}</h3>
          <table class="table table-sm w-full text-sm">
            <thead class="text-left text-base-content/60">
              <tr>
                <th class="py-2">{gettext("When")}</th>
                <th class="py-2">{gettext("Reason")}</th>
                <th class="py-2">{gettext("From pen")}</th>
                <th class="py-2">{gettext("To pen")}</th>
                <th class="py-2">{gettext("Qty")}</th>
                <th class="py-2">{gettext("Notes")}</th>
              </tr>
            </thead>
            <tbody id="movements" phx-update="stream">
              <tr
                :for={{dom_id, m} <- @streams.movements}
                id={dom_id}
                class="border-t border-base-200"
              >
                <td class="py-1.5 whitespace-nowrap">
                  {m.moved_at}
                </td>
                <td class="py-1.5">{String.replace(m.reason, "_", " ")}</td>
                <td class="py-1.5 font-mono">
                  {m.from_pen && "#{m.from_pen.house.code}/#{m.from_pen.code}"}
                </td>
                <td class="py-1.5 font-mono">
                  {m.to_pen && "#{m.to_pen.house.code}/#{m.to_pen.code}"}
                </td>
                <td class="py-1.5">{m.quantity}</td>
                <td class="py-1.5 text-base-content/60">{m.notes}</td>
              </tr>
            </tbody>
          </table>
          <p
            :if={@movement_count == 0}
            class="mt-2 text-sm text-base-content/60"
          >
            {gettext("No movements recorded.")}
          </p>
        </section>

        <%!-- Edit modal --%>
        <div
          :if={@edit_form}
          id="edit-modal"
          class="fixed inset-0 bg-black/40 flex items-center justify-center z-50"
        >
          <div
            class="bg-base-100 rounded p-6 w-full max-w-2xl max-h-[90vh] overflow-y-auto"
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
              <.input
                :if={@animal.tracking_type == "individual"}
                field={@edit_form[:sex]}
                type="select"
                label={gettext("Sex")}
                options={Enum.map(Animal.sexes(), &{String.capitalize(&1), &1})}
              />
              <.input field={@edit_form[:breed]} type="text" label={gettext("Breed")} />
              <.input field={@edit_form[:dob]} type="date" label={gettext("Date of birth")} />
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

    move_cs = Animals.change_movement(new_movement(animal, placements), %{})

    {:ok,
     socket
     |> assign(
       animal: animal,
       offspring: offspring,
       placements: placements,
       can_manage: Policy.can?(scope, :manage_animals),
       can_move: Policy.can?(scope, :record_movement),
       edit_form: nil,
       move_form: to_form(move_cs, as: :movement),
       movement_count: length(movements),
       ac: move_ac_items(scope, placements)
     )
     |> stream(:movements, movements)}
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
      |> maybe_reset_picker(reason in ["placement", "adjustment_gain"], "move-from-pen-picker")

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

        move_cs = Animals.change_movement(new_movement(animal, placements), %{})

        {:noreply,
         socket
         |> assign(
           animal: animal,
           placements: placements,
           movement_count: length(movements)
         )
         |> assign(:move_form, to_form(move_cs, as: :movement))
         |> assign(:ac, move_ac_items(scope, placements))
         |> stream(:movements, movements, reset: true)
         |> push_event("ac:reset", %{id: "move-pen-picker"})
         |> push_event("ac:reset", %{id: "move-from-pen-picker"})
         |> put_flash(:info, gettext("Movement recorded."))}

      {:error, cs} ->
        {:noreply, assign(socket, :move_form, to_form(cs, as: :movement))}
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
      |> Animals.list_animals(status: "active")
      |> Enum.reject(&(&1.id == animal.id))

    %{
      move_pen_items: pen_items(scope),
      move_pen_label: nil,
      from_pen_items: placement_items(placements),
      from_pen_label: nil,
      sire_items: animal_items(animals, "male"),
      sire_label: nil,
      dam_items: animal_items(animals, "female"),
      dam_label: nil
    }
  end

  defp placement_items(placements) do
    Enum.map(placements, fn p ->
      %{id: p.pen_id, label: "#{p.pen.house.code}/#{p.pen.code} (#{p.quantity})"}
    end)
  end

  defp pen_items(scope) do
    scope
    |> Locations.list_all_pens()
    |> Enum.map(&%{id: &1.id, label: "#{&1.house.code}/#{&1.code}"})
  end

  defp animal_items(animals, sex) do
    animals
    |> Enum.filter(&(&1.sex == sex and &1.ear_tag != nil))
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
    |> Enum.reject(&(&1 in ["adjustment_loss", "adjustment_gain"]))
    |> Enum.map(&{humanize_reason(&1), &1})
  end

  defp reason_options(_) do
    Enum.map(Movement.reasons(), &{humanize_reason(&1), &1})
  end

  defp humanize_reason(r), do: r |> String.replace("_", " ") |> String.capitalize()

  # Seed a blank Movement for the form. Default to "placement" only when
  # there's still quantity in the batch that isn't placed anywhere yet —
  # that's the "just registered, now assign to pens" case.
  defp new_movement(%Animal{tracking_type: "batch"} = animal, placements) do
    placed = Enum.reduce(placements, 0, fn p, acc -> acc + p.quantity end)
    reason = if placed < animal.quantity, do: "placement", else: "pen_transfer"
    %Movement{moved_at: Date.utc_today(), reason: reason}
  end

  defp new_movement(%Animal{}, _),
    do: %Movement{moved_at: Date.utc_today(), reason: "pen_transfer"}

  ## Display helpers

  defp pen_label(animal) do
    case animal do
      %{current_pen: %{code: code, house: %{code: hcode}}} -> "#{hcode}/#{code}"
      %{current_pen: %{code: code}} -> code
      _ -> nil
    end
  end

  defp status_badge_class("active"), do: "badge-success"
  defp status_badge_class("sold"), do: "badge-info"
  defp status_badge_class("slaughtered"), do: "badge-warning"
  defp status_badge_class("deceased"), do: "badge-error"
  defp status_badge_class("transferred"), do: "badge-ghost"
  defp status_badge_class(_), do: ""
end
