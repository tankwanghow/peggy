defmodule PeggyWeb.FarmLive.Animals do
  use PeggyWeb, :live_view

  alias Peggy.Animals
  alias Peggy.Animals.Animal
  alias Peggy.Locations
  alias Peggy.Policy

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-6xl">
        <.header>
          {gettext("Animals")}
          <:subtitle>{gettext("Individual pigs and batches")}</:subtitle>
          <:actions>
            <.link
              :if={@can_move}
              navigate={~p"/farms/#{@current_scope.farm.slug}/animals/bulk-move"}
              class="btn btn-sm"
            >
              {gettext("Bulk Move Sire/Dam")}
            </.link>
            <.button :if={@can_manage} phx-click="new" class="btn btn-primary btn-sm">
              {gettext("Register animal")}
            </.button>
          </:actions>
        </.header>

        <form phx-change="filter" class="mt-4 flex gap-3 flex-wrap">
          <.input
            name="stage"
            value={@filter_stage}
            type="select"
            label={gettext("Stage")}
            options={[{gettext("All"), ""} | Enum.map(Animal.stages(), &{String.capitalize(&1), &1})]}
          />
          <.input
            name="status"
            value={@filter_status}
            type="select"
            label={gettext("Status")}
            options={[
              {gettext("All"), ""} | Enum.map(Animal.statuses(), &{String.capitalize(&1), &1})
            ]}
          />
        </form>

        <div class="mt-4 overflow-x-auto">
          <table class="table table-sm w-full">
            <thead class="text-left text-base-content/60">
              <tr>
                <th class="py-2">{gettext("Tag / ID")}</th>
                <th class="py-2">{gettext("Type")}</th>
                <th class="py-2">{gettext("Stage")}</th>
                <th class="py-2">{gettext("Sex")}</th>
                <th class="py-2">{gettext("Breed")}</th>
                <th class="py-2">{gettext("Pen")}</th>
                <th class="py-2">{gettext("Status")}</th>
              </tr>
            </thead>
            <tbody id="animals" phx-update="stream">
              <tr
                :for={{dom_id, a} <- @streams.animals}
                id={dom_id}
                class="border-t border-base-200 hover:bg-base-200/50 cursor-pointer"
                phx-click={JS.navigate(~p"/farms/#{@current_scope.farm.slug}/animals/#{a.id}")}
              >
                <td class="py-1.5 font-mono font-semibold">
                  {a.ear_tag || "##{a.id}"}
                </td>
                <td class="py-1.5">
                  <span class={[
                    "badge badge-sm",
                    a.tracking_type == "batch" && "badge-secondary"
                  ]}>
                    {a.tracking_type}
                    <span :if={a.tracking_type == "batch"}> ({a.quantity})</span>
                  </span>
                </td>
                <td class="py-1.5">{String.capitalize(a.stage)}</td>
                <td class="py-1.5">{a.sex && String.capitalize(a.sex)}</td>
                <td class="py-1.5">{a.breed}</td>
                <td class="py-1.5 font-mono">
                  {pen_label(a)}
                </td>
                <td class="py-1.5">
                  <span class={[
                    "badge badge-sm",
                    status_badge_class(a.status)
                  ]}>
                    {String.capitalize(a.status)}
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
          <p :if={@animal_count == 0} class="mt-4 text-center text-base-content/60">
            {gettext("No animals registered yet.")}
          </p>
        </div>

        <%!-- Create/Edit modal --%>
        <div
          :if={@form}
          id="animal-modal"
          class="fixed inset-0 bg-black/40 flex items-center justify-center z-50"
        >
          <div
            class="bg-base-100 rounded p-6 w-full max-w-2xl max-h-[90vh] overflow-y-auto"
            phx-click-away="cancel"
            phx-window-keydown="cancel"
            phx-key="escape"
          >
            <h3 class="text-lg font-semibold mb-3">{@form_title}</h3>
            <.form
              for={@form}
              id="animal-form"
              phx-submit="save"
              phx-change="validate"
              class="grid grid-cols-2 gap-x-4 gap-y-1"
            >
              <.input
                field={@form[:tracking_type]}
                type="select"
                label={gettext("Tracking type")}
                options={Enum.map(Animal.tracking_types(), &{String.capitalize(&1), &1})}
              />
              <.input
                field={@form[:stage]}
                type="select"
                label={gettext("Stage")}
                options={
                  Enum.map(
                    Animal.stages_for(form_value(@form, :tracking_type)),
                    &{String.capitalize(&1), &1}
                  )
                }
              />
              <.input
                field={@form[:ear_tag]}
                type="text"
                label={
                  if form_value(@form, :tracking_type) == "batch",
                    do: gettext("Batch number"),
                    else: gettext("Ear tag")
                }
                class="w-full input font-mono"
                required={form_value(@form, :tracking_type) == "individual"}
              />
              <.input
                :if={form_value(@form, :tracking_type) == "individual"}
                field={@form[:sex]}
                type="select"
                label={gettext("Sex")}
                options={Enum.map(Animal.sexes(), &{String.capitalize(&1), &1})}
              />
              <.input
                :if={form_value(@form, :tracking_type) == "batch"}
                field={@form[:quantity]}
                type="number"
                label={gettext("Quantity")}
                min="2"
                required
              />
              <.input
                :if={form_value(@form, :tracking_type) == "individual"}
                field={@form[:rfid]}
                type="text"
                label={gettext("RFID")}
                class="w-full input font-mono"
              />
              <.input field={@form[:breed]} type="text" label={gettext("Breed")} />
              <.input field={@form[:dob]} type="date" label={gettext("Date of birth")} />
              <.autocomplete
                :if={form_value(@form, :tracking_type) == "individual"}
                id="pen-picker"
                label={gettext("Current pen")}
                name="animal[current_pen_id]"
                value={form_value(@form, :current_pen_id)}
                items={@ac.pen_items}
                selected_label={@ac.pen_label}
                class="w-full input font-mono"
                placeholder={gettext("Search pens...")}
              />
              <.autocomplete
                :if={form_value(@form, :tracking_type) == "individual"}
                id="sire-picker"
                label={gettext("Sire")}
                name="animal[sire_id]"
                value={form_value(@form, :sire_id)}
                items={@ac.sire_items}
                selected_label={@ac.sire_label}
                class="w-full input font-mono"
                placeholder={gettext("Search by ear tag...")}
              />
              <.autocomplete
                :if={form_value(@form, :tracking_type) == "individual"}
                id="dam-picker"
                label={gettext("Dam")}
                name="animal[dam_id]"
                value={form_value(@form, :dam_id)}
                items={@ac.dam_items}
                selected_label={@ac.dam_label}
                class="w-full input font-mono"
                placeholder={gettext("Search by ear tag...")}
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
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    can_manage = Policy.can?(scope, :manage_animals)
    can_move = Policy.can?(scope, :record_movement)

    {:ok,
     socket
     |> assign(can_manage: can_manage, can_move: can_move)
     |> assign(filter_stage: "", filter_status: "")
     |> assign(form: nil, form_title: nil, form_target: nil)
     |> assign(ac: default_ac())
     |> load_animals()}
  end

  @impl true
  def handle_event("filter", params, socket) do
    stage = Map.get(params, "stage", "")
    status = Map.get(params, "status", "")

    {:noreply,
     socket
     |> assign(filter_stage: stage, filter_status: status)
     |> load_animals()}
  end

  def handle_event("new", _, socket) do
    if socket.assigns.can_manage do
      {:noreply,
       open_form(
         socket,
         nil,
         %Animal{tracking_type: "individual", stage: "sow", sex: "female"},
         gettext("Register animal")
       )}
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("cancel", _, socket), do: {:noreply, close_form(socket)}

  def handle_event("validate", %{"animal" => params}, socket) do
    target = socket.assigns.form_target || %Animal{}
    params = reset_stage_if_invalid(params)
    cs = Animals.change_animal(target, params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(cs, as: :animal))}
  end

  def handle_event("save", %{"animal" => params}, socket) do
    if socket.assigns.can_manage do
      do_save(socket, socket.assigns.form_target, params)
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  ## Save helpers

  # When the user flips tracking_type, the previously-picked stage may no
  # longer appear in the dropdown. Reset it to the first valid option so
  # the select shows a consistent selection.
  defp reset_stage_if_invalid(%{"tracking_type" => tt, "stage" => stage} = params) do
    valid = Animal.stages_for(tt)
    if stage in valid, do: params, else: Map.put(params, "stage", hd(valid))
  end

  defp reset_stage_if_invalid(params), do: params

  defp do_save(socket, nil, params) do
    case Animals.create_animal(socket.assigns.current_scope, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Animal registered."))
         |> close_form()
         |> load_animals()}

      {:error, cs} ->
        {:noreply, assign(socket, :form, to_form(cs, as: :animal))}
    end
  end

  defp do_save(socket, %Animal{} = animal, params) do
    case Animals.update_animal(socket.assigns.current_scope, animal, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Animal updated."))
         |> close_form()
         |> load_animals()}

      {:error, cs} ->
        {:noreply, assign(socket, :form, to_form(cs, as: :animal))}
    end
  end

  ## Form lifecycle

  defp open_form(socket, target, base, title) do
    cs = Animals.change_animal(base, %{})

    ac =
      socket
      |> load_ac_items()
      |> maybe_preselect_pen(socket, base)
      |> maybe_preselect_parent(:sire, socket, base)
      |> maybe_preselect_parent(:dam, socket, base)

    socket
    |> assign(
      form: to_form(cs, as: :animal),
      form_title: title,
      form_target: target,
      ac: ac
    )
  end

  defp close_form(socket) do
    assign(socket, form: nil, form_title: nil, form_target: nil, ac: default_ac())
  end

  ## Autocomplete state helpers

  defp default_ac do
    %{
      pen_items: [],
      pen_label: nil,
      sire_items: [],
      sire_label: nil,
      dam_items: [],
      dam_label: nil
    }
  end

  defp load_ac_items(socket) do
    scope = socket.assigns.current_scope
    active_animals = Animals.list_animals(scope, status: "active")

    %{
      pen_items:
        scope
        |> Locations.list_all_pens()
        |> Enum.map(&%{id: &1.id, label: "#{&1.house.code}/#{&1.code}"}),
      pen_label: nil,
      sire_items: animal_items(active_animals, "male"),
      sire_label: nil,
      dam_items: animal_items(active_animals, "female"),
      dam_label: nil
    }
  end

  defp animal_items(animals, sex) do
    animals
    |> Enum.filter(&(&1.sex == sex and &1.ear_tag != nil))
    |> Enum.map(&%{id: &1.id, label: &1.ear_tag})
  end

  defp maybe_preselect_pen(ac, socket, %{current_pen_id: pen_id}) when not is_nil(pen_id) do
    scope = socket.assigns.current_scope
    pen = Peggy.Repo.preload(Locations.get_pen!(scope, pen_id), :house)
    %{ac | pen_label: "#{pen.house.code}/#{pen.code}"}
  end

  defp maybe_preselect_pen(ac, _socket, _), do: ac

  defp maybe_preselect_parent(ac, :sire, socket, %{sire_id: id}) when not is_nil(id) do
    animal = Animals.get_animal!(socket.assigns.current_scope, id)
    %{ac | sire_label: animal.ear_tag}
  end

  defp maybe_preselect_parent(ac, :dam, socket, %{dam_id: id}) when not is_nil(id) do
    animal = Animals.get_animal!(socket.assigns.current_scope, id)
    %{ac | dam_label: animal.ear_tag}
  end

  defp maybe_preselect_parent(ac, _, _, _), do: ac

  ## Other helpers

  defp load_animals(socket) do
    scope = socket.assigns.current_scope
    stage = if socket.assigns.filter_stage == "", do: nil, else: socket.assigns.filter_stage
    status = if socket.assigns.filter_status == "", do: nil, else: socket.assigns.filter_status

    animals = Animals.list_animals(scope, stage: stage, status: status)

    socket
    |> assign(:animal_count, length(animals))
    |> stream(:animals, animals, reset: true)
  end

  defp form_value(form, field) do
    Phoenix.HTML.Form.input_value(form, field)
  end

  # Individuals live in `current_pen`; batches live in a list of active
  # `placements`. For the list view we render each batch's distribution
  # compactly, e.g. "H1/P1 ×40 · H2/P2 ×60".
  defp pen_label(%{tracking_type: "batch", placements: [_ | _] = placements}) do
    placements
    |> Enum.map_join(" · ", fn p ->
      "#{p.pen.house.code}/#{p.pen.code}×#{p.quantity}"
    end)
  end

  defp pen_label(%{current_pen: %{code: code, house: %{code: hcode}}}), do: "#{hcode}/#{code}"
  defp pen_label(%{current_pen: %{code: code}}), do: code
  defp pen_label(_), do: nil

  defp status_badge_class("active"), do: "badge-success"
  defp status_badge_class("sold"), do: "badge-info"
  defp status_badge_class("slaughtered"), do: "badge-warning"
  defp status_badge_class("deceased"), do: "badge-error"
  defp status_badge_class("transferred"), do: "badge-ghost"
  defp status_badge_class(_), do: ""
end
