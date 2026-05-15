defmodule PeggyWeb.FarmLive.Animals do
  use PeggyWeb, :live_view

  alias Peggy.Animals
  alias Peggy.Animals.Animal
  alias Peggy.Breeding
  alias Peggy.FarmClock
  alias Peggy.Locations
  alias Peggy.Policy

  @per_page 50

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-7xl">
        <.header>
          {gettext("Animals")}
          <:subtitle>{gettext("Individual pigs and batches")}</:subtitle>
          <:actions>
            <.link
              navigate={~p"/farms/#{@current_scope.farm.slug}/animals/promote"}
              class="btn btn-sm btn-ghost"
            >
              {gettext("Promote batches")}
            </.link>
            <.iframe_print_button
              id="animals-print-btn"
              url={print_path(@current_scope.farm.slug, assigns)}
            />
          </:actions>
        </.header>

        <form
          phx-change="filter"
          phx-submit="filter"
          class="mt-2 flex gap-1 flex-nowrap items-end overflow-x-auto [&_.fieldset>label]:flex [&_.fieldset>label]:flex-col [&_.fieldset>label]:items-start"
        >
          <.input
            name="stage"
            value={@filter_stage}
            type="select"
            label={gettext("Stage")}
            class="select select-sm w-28"
            options={[{gettext("All"), ""} | Enum.map(Animal.stages(), &{String.capitalize(&1), &1})]}
          />
          <.input
            name="status"
            value={@filter_status}
            type="select"
            label={gettext("Status")}
            class="select select-sm w-32"
            options={status_options(@filter_stage)}
          />
          <.input
            name="tag_search"
            value={@filter_tag_search}
            type="text"
            label={gettext("Tag / ID")}
            class="input input-sm"
            placeholder={gettext("e.g. 12345 or #42")}
          />
          <.input
            name="pen_search"
            value={@filter_pen_search}
            type="text"
            label={gettext("Pen")}
            class="input input-sm"
            placeholder={gettext("e.g. H1-P2")}
          />
          <.input
            :if={@filter_stage in ~w(weaner grower finisher)}
            name="min_age"
            value={@filter_min_age}
            type="number"
            label={gettext("Min age (d)")}
            class="input input-sm"
            min="0"
          />
          <.input
            :if={@filter_stage in ~w(weaner grower finisher)}
            name="max_age"
            value={@filter_max_age}
            type="number"
            label={gettext("Max age (d)")}
            class="input input-sm"
            min="0"
          />
          <.input
            :if={@filter_stage == "sow"}
            name="min_parity"
            value={@filter_min_parity}
            type="number"
            label={gettext("Min parity")}
            class="input input-sm"
            min="0"
          />
          <.input
            :if={@filter_stage == "sow"}
            name="max_parity"
            value={@filter_max_parity}
            type="number"
            label={gettext("Max parity")}
            class="input input-sm"
            min="0"
          />
          <.input
            name="needs_review"
            value={if @filter_needs_review, do: "1", else: ""}
            type="select"
            label={gettext("Needs review")}
            class="select select-sm w-24"
            options={[{gettext("All"), ""}, {gettext("Yes"), "1"}]}
          />
        </form>

        <div class="mt-4 overflow-x-auto">
          <table class="table table-sm w-full">
            <thead class="text-left text-base-content/60">
              <tr>
                <th class="py-2">
                  <.sort_header label={gettext("Tag / ID")} col="tag" sort={@sort} dir={@dir} />
                </th>
                <th class="py-2">
                  <.sort_header label={gettext("Stage")} col="stage" sort={@sort} dir={@dir} />
                </th>
                <th class="py-2">{gettext("Breed")}</th>
                <th class="py-2">
                  <.sort_header label={gettext("Pen")} col="pen" sort={@sort} dir={@dir} />
                </th>
                <th class="py-2">
                  <.sort_header label={gettext("Status")} col="status" sort={@sort} dir={@dir} />
                </th>
                <th :if={show_days_col?(@filter_stage)} class="py-2 text-right">
                  <.sort_header
                    label={gettext("Days in status")}
                    col="days"
                    sort={@sort}
                    dir={@dir}
                    align="right"
                  />
                </th>
                <th class="py-2 w-6"></th>
              </tr>
            </thead>
            <tbody id="animals" phx-update="stream">
              <tr
                :for={{dom_id, a} <- @streams.animals}
                id={dom_id}
                class="border-t border-base-200 hover:bg-base-200/50 cursor-pointer"
                phx-click={JS.navigate(~p"/farms/#{@current_scope.farm.slug}/animals/#{a.id}")}
              >
                <td class="py-2 font-mono font-semibold">
                  <span class="inline-flex items-center gap-1">
                    {a.ear_tag || "##{a.id}"}
                    <span :if={a.needs_review} title={gettext("Needs review")}>
                      <.icon name="hero-exclamation-triangle-micro" class="size-4 text-warning" />
                    </span>
                  </span>
                </td>
                <td class="py-2">
                  {String.capitalize(a.stage)}
                  <span
                    :if={detail = stage_detail(a, @parity_map, @avg_wean_age, @today)}
                    class="text-base-content/60"
                  >
                    · {detail}
                  </span>
                </td>
                <td class="py-2">{a.breed}</td>
                <td class="py-2 font-mono">
                  {pen_label(a)}
                </td>
                <td class="py-2">
                  <.status_badge status={a.status} class="badge-sm" />
                </td>
                <td
                  :if={show_days_col?(@filter_stage)}
                  class="py-2 text-right font-mono text-base-content/70"
                >
                  {days_in_status(a, @today)}
                </td>
                <td class="py-2 text-base-content/40">
                  <.icon name="hero-chevron-right-micro" class="size-4" />
                </td>
              </tr>
            </tbody>
          </table>
          <p :if={@animal_count == 0} class="mt-4 text-center text-base-content/60">
            {gettext("No animals registered yet.")}
          </p>
          <.infinite_scroll has_more={@has_more} total={@animal_count} id="animals-sentinel" />
        </div>

        <%!-- Create/Edit modal --%>
        <div
          :if={@form}
          id="animal-modal"
          class="fixed inset-0 bg-black/40 flex items-center justify-center z-50"
        >
          <div
            class="bg-base-100 rounded p-4 sm:p-6 w-full max-w-2xl mx-4 max-h-[85vh] overflow-y-auto"
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
              <.input
                :if={
                  form_value(@form, :tracking_type) == "individual" and
                    form_value(@form, :stage) == "sow"
                }
                field={@form[:legacy_parity]}
                type="number"
                label={gettext("Legacy parity")}
                min="0"
              />
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
     |> assign(filter_stage: "", filter_status: "present", filter_needs_review: false)
     |> assign(
       filter_pen_search: "",
       filter_tag_search: "",
       filter_min_age: "",
       filter_max_age: "",
       filter_min_parity: "",
       filter_max_parity: ""
     )
     |> assign(sort: "tag", dir: "asc")
     |> assign(form: nil, form_title: nil, form_target: nil)
     |> assign(ac: default_ac())
     |> assign(animal_count: 0, page: 1, has_more: false)
     |> assign(parity_map: %{}, avg_wean_age: nil, today: FarmClock.today(scope))
     |> stream(:animals, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    stage = Map.get(params, "stage", "")
    status = Map.get(params, "status", "present")
    needs_review = Map.get(params, "needs_review") in ["1", "true"]

    socket =
      socket
      |> assign(
        filter_stage: stage,
        filter_status: status,
        filter_needs_review: needs_review,
        filter_pen_search: Map.get(params, "pen_search", ""),
        filter_tag_search: Map.get(params, "tag_search", ""),
        filter_min_age: Map.get(params, "min_age", ""),
        filter_max_age: Map.get(params, "max_age", ""),
        filter_min_parity: Map.get(params, "min_parity", ""),
        filter_max_parity: Map.get(params, "max_parity", ""),
        sort: sort_param(Map.get(params, "sort")),
        dir: dir_param(Map.get(params, "dir"))
      )
      |> load_rows()
      |> maybe_open_new(params)

    {:noreply, socket}
  end

  defp maybe_open_new(socket, %{"new" => "1"}) do
    if socket.assigns.can_manage and is_nil(socket.assigns.form) do
      open_form(
        socket,
        nil,
        %Animal{tracking_type: "individual", stage: "sow"},
        gettext("Register animal")
      )
    else
      socket
    end
  end

  defp maybe_open_new(socket, _), do: socket

  @impl true
  def handle_event("filter", params, socket) do
    # Status is always kept in the URL — an empty `status=` is the
    # explicit "All" choice, distinct from a missing param which
    # defaults to "present". Other filters drop when blank.
    raw_status = Map.get(params, "status", "present")
    new_stage = Map.get(params, "stage", "")
    status = if valid_status_for_stage?(raw_status, new_stage), do: raw_status, else: "present"

    query =
      %{
        "stage" => new_stage,
        "pen_search" => Map.get(params, "pen_search", ""),
        "tag_search" => Map.get(params, "tag_search", ""),
        "min_age" => Map.get(params, "min_age", ""),
        "max_age" => Map.get(params, "max_age", ""),
        "min_parity" => Map.get(params, "min_parity", ""),
        "max_parity" => Map.get(params, "max_parity", ""),
        "needs_review" =>
          if(Map.get(params, "needs_review") in ["1", "true", "on"], do: "1", else: "")
      }
      |> Enum.reject(fn {_k, v} -> v == "" end)
      |> Enum.into(%{})
      |> Map.put("status", status)
      |> merge_sort(socket)

    {:noreply,
     push_patch(socket,
       to: ~p"/farms/#{socket.assigns.current_scope.farm.slug}/animals?#{query}"
     )}
  end

  def handle_event("sort", %{"col" => col}, socket) do
    new_sort = sort_param(col)

    new_dir =
      cond do
        new_sort == socket.assigns.sort and socket.assigns.dir == "asc" -> "desc"
        new_sort == socket.assigns.sort and socket.assigns.dir == "desc" -> "asc"
        true -> "asc"
      end

    query =
      current_query_params(socket)
      |> Map.put("sort", new_sort)
      |> Map.put("dir", new_dir)

    {:noreply,
     push_patch(socket,
       to: ~p"/farms/#{socket.assigns.current_scope.farm.slug}/animals?#{query}"
     )}
  end

  def handle_event("new", _, socket) do
    if socket.assigns.can_manage do
      {:noreply,
       open_form(
         socket,
         nil,
         %Animal{tracking_type: "individual", stage: "sow"},
         gettext("Register animal")
       )}
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("cancel", _, socket), do: {:noreply, close_form(socket)}

  def handle_event("load_more", _, socket) do
    {:noreply, append_rows(socket)}
  end

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
         |> load_rows()}

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
         |> load_rows()}

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
        |> Enum.map(&%{id: &1.id, label: "#{&1.house.code}-#{&1.code}"}),
      pen_label: nil,
      sire_items: animal_items(active_animals, "boar"),
      sire_label: nil,
      dam_items: animal_items(active_animals, "sow"),
      dam_label: nil
    }
  end

  defp animal_items(animals, stage) do
    animals
    |> Enum.filter(&(&1.stage == stage and &1.ear_tag != nil))
    |> Enum.map(&%{id: &1.id, label: &1.ear_tag})
  end

  defp maybe_preselect_pen(ac, socket, %{current_pen_id: pen_id}) when not is_nil(pen_id) do
    scope = socket.assigns.current_scope
    pen = Peggy.Repo.preload(Locations.get_pen!(scope, pen_id), :house)
    %{ac | pen_label: "#{pen.house.code}-#{pen.code}"}
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

  defp load_rows(socket) do
    opts = filter_opts(socket) ++ [limit: @per_page, offset: 0]
    scope = socket.assigns.current_scope
    rows = Animals.list_animals(scope, opts)
    total = Animals.count_animals(scope, filter_opts(socket))

    socket
    |> assign(
      animal_count: total,
      page: 1,
      has_more: length(rows) < total,
      parity_map: parity_map(scope, rows),
      avg_wean_age: Breeding.avg_weaning_age_days(scope)
    )
    |> stream(:animals, rows, reset: true)
  end

  defp append_rows(socket) do
    scope = socket.assigns.current_scope
    next_page = socket.assigns.page + 1
    opts = filter_opts(socket) ++ [limit: @per_page, offset: (next_page - 1) * @per_page]
    rows = Animals.list_animals(scope, opts)
    loaded = next_page * @per_page

    socket =
      Enum.reduce(rows, socket, fn row, acc -> stream_insert(acc, :animals, row) end)

    assign(socket,
      page: next_page,
      has_more: loaded < socket.assigns.animal_count,
      parity_map: Map.merge(socket.assigns.parity_map, parity_map(scope, rows))
    )
  end

  defp parity_map(scope, rows) do
    sow_ids =
      rows
      |> Enum.filter(&(&1.stage == "sow" and &1.tracking_type == "individual"))
      |> Enum.map(& &1.id)

    Breeding.parities_for(scope, sow_ids)
  end

  defp filter_opts(socket) do
    stage = if socket.assigns.filter_stage == "", do: nil, else: socket.assigns.filter_stage
    status = if socket.assigns.filter_status == "", do: nil, else: socket.assigns.filter_status

    [
      stage: stage,
      status: status,
      needs_review: socket.assigns.filter_needs_review,
      pen_search: blank_to_nil(socket.assigns.filter_pen_search),
      tag_search: blank_to_nil(socket.assigns.filter_tag_search),
      min_age_days: parse_int_filter(socket.assigns.filter_min_age),
      max_age_days: parse_int_filter(socket.assigns.filter_max_age),
      min_parity: parse_int_filter(socket.assigns.filter_min_parity),
      max_parity: parse_int_filter(socket.assigns.filter_max_parity),
      sort: socket.assigns.sort,
      dir: socket.assigns.dir
    ]
  end

  @sort_columns ~w(tag stage pen status days)
  defp sort_param(s) when s in @sort_columns, do: s
  defp sort_param(_), do: "tag"

  defp dir_param("desc"), do: "desc"
  defp dir_param(_), do: "asc"

  defp merge_sort(query, socket) do
    query
    |> Map.put("sort", socket.assigns.sort)
    |> Map.put("dir", socket.assigns.dir)
  end

  # Snapshots the current URL filters from socket assigns so the sort
  # event can preserve them when patching back.
  defp current_query_params(socket) do
    a = socket.assigns

    %{
      "stage" => a.filter_stage,
      "status" => a.filter_status,
      "pen_search" => a.filter_pen_search,
      "tag_search" => a.filter_tag_search,
      "min_age" => a.filter_min_age,
      "max_age" => a.filter_max_age,
      "min_parity" => a.filter_min_parity,
      "max_parity" => a.filter_max_parity,
      "needs_review" => if(a.filter_needs_review, do: "1", else: "")
    }
    |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
    |> Enum.into(%{})
    # `status` is sticky — keep an explicit "" if user opted into All.
    |> Map.put("status", a.filter_status)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(v), do: v

  defp print_path(slug, assigns) do
    query =
      %{
        "stage" => assigns.filter_stage,
        "status" => assigns.filter_status,
        "pen_search" => assigns.filter_pen_search,
        "tag_search" => assigns.filter_tag_search,
        "min_age" => assigns.filter_min_age,
        "max_age" => assigns.filter_max_age,
        "min_parity" => assigns.filter_min_parity,
        "max_parity" => assigns.filter_max_parity,
        "needs_review" => if(assigns.filter_needs_review, do: "1", else: ""),
        "sort" => assigns.sort,
        "dir" => assigns.dir
      }
      |> Enum.reject(fn {_, v} -> v in [nil, ""] end)
      |> Map.new()

    base = ~p"/farms/#{slug}/animals/print"

    case query do
      m when map_size(m) == 0 -> base
      m -> base <> "?" <> URI.encode_query(m)
    end
  end

  defp parse_int_filter(nil), do: nil
  defp parse_int_filter(""), do: nil

  defp parse_int_filter(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} when n >= 0 -> n
      _ -> nil
    end
  end

  defp parse_int_filter(n) when is_integer(n) and n >= 0, do: n
  defp parse_int_filter(_), do: nil

  defp form_value(form, field) do
    Phoenix.HTML.Form.input_value(form, field)
  end

  # Individuals live in `current_pen`; batches live in a list of active
  # `placements`. For the list view we render each batch's distribution
  # compactly, e.g. "H1/P1 ×40 · H2/P2 ×60".
  defp stage_detail(%{stage: "sow"} = a, parity_map, _avg, _today) do
    case Map.get(parity_map, a.id) do
      nil -> nil
      0 -> "P0"
      n -> "P#{n}"
    end
  end

  defp stage_detail(%{stage: stage} = a, _parity, avg_wean_age, today)
       when stage in ~w(weaner grower finisher) do
    case batch_age_days(a, avg_wean_age, today) do
      nil -> nil
      d -> "#{d}d"
    end
  end

  defp stage_detail(_, _, _, _), do: nil

  defp batch_age_days(%{farrowing: %{weaning: %{weaned_at: weaned_at}}}, avg, today)
       when not is_nil(weaned_at) and is_integer(avg) do
    Date.diff(today, weaned_at) + avg
  end

  defp batch_age_days(%{dob: %Date{} = dob}, _avg, today) do
    Date.diff(today, dob)
  end

  defp batch_age_days(_, _, _), do: nil

  defp pen_label(%{tracking_type: "batch", placements: [_ | _] = placements}) do
    assigns = %{placements: placements}

    ~H"""
    <span :for={p <- @placements} class="mr-2">
      {p.pen.house.code}-{p.pen.code} ×<span class="italic text-xs">{p.quantity}</span>
    </span>
    """
  end

  defp pen_label(%{current_pen: %{code: code, house: %{code: hcode}}}), do: "#{hcode}-#{code}"
  defp pen_label(%{current_pen: %{code: code}}), do: code
  defp pen_label(_), do: nil

  # Days since the animal entered its current status. Only meaningful
  # for sows in a present (on-farm) status — boar status rarely changes
  # in a way worth surfacing per row, and weaner/grower/finisher batches
  # roll up multiple animals so a single timestamp is misleading.
  defp days_in_status(
         %{stage: "sow", status: status, status_changed_at: %DateTime{} = ts},
         today
       )
       when is_binary(status) do
    if status in Animal.present_statuses() do
      Date.diff(today, DateTime.to_date(ts))
    else
      nil
    end
  end

  defp days_in_status(_, _), do: nil

  # Status dropdown options shaped to the active stage filter:
  #   - sow → breeding-relevant statuses + Serviceable / Breeding herd groupings
  #   - boar → individual statuses only
  #   - weaner/grower/finisher → batch-relevant statuses (active + departed)
  #   - all stages → full set (today's behaviour)
  # `Present`, `Departed`, and `All` are universal meta-groupings.
  defp status_options(stage) do
    base = [{gettext("Present (any)"), "present"}]

    sow_groupings =
      if stage == "sow" or stage == "" or is_nil(stage) do
        [
          {gettext("Serviceable"), "serviceable"},
          {gettext("Breeding herd"), "breeding_herd"}
        ]
      else
        []
      end

    tail = [
      {gettext("Departed (any)"), "departed"},
      {gettext("All"), ""}
    ]

    individual_statuses =
      stage
      |> Animal.statuses_for_stage()
      |> Enum.map(&{String.capitalize(&1), &1})

    base ++ sow_groupings ++ tail ++ individual_statuses
  end

  # When the stage filter changes, the previously selected status may
  # no longer apply (e.g. switching sow → weaner with status=lactating).
  # Reset to "present" in that case so the page doesn't render an empty
  # list with a stale status sticking around.
  defp valid_status_for_stage?(status, stage) do
    status in [nil, "", "present", "departed", "serviceable", "breeding_herd", "saleable"] or
      status in Animal.statuses_for_stage(stage)
  end

  # The "Days in status" cell only ever fills for sows (see
  # days_in_status/2). When the stage filter is set to a non-sow stage
  # the column would be uniformly blank, so hide it.
  defp show_days_col?(filter_stage) when filter_stage in ~w(weaner grower finisher boar),
    do: false

  defp show_days_col?(_), do: true
end
