defmodule PeggyWeb.MobileLive.PromoteBatches do
  @moduledoc """
  Mobile view of the promotion triage screen. Single-column card layout
  with one bulk-promote button per section. Per-row checkboxes follow
  the same per-row partial-success semantics as the desktop view via
  `Peggy.Animals.promote_many/3`.
  """
  use PeggyWeb, :live_view

  alias Peggy.Animals
  alias Peggy.Policy

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_app flash={@flash} current_scope={@current_scope} active={:animals}>
      <header class="sticky top-0 z-10 bg-base-100 border-b border-base-200 px-3 py-2 flex items-center gap-2">
        <.link
          navigate={~p"/m/#{@current_scope.farm.slug}/animals"}
          class="btn btn-ghost btn-square btn-lg"
          aria-label={gettext("Back")}
        >
          <.icon name="hero-chevron-left" class="size-6" />
        </.link>
        <div class="flex-1 min-w-0 font-bold">
          {gettext("Promote batches")}
        </div>
      </header>

      <div class="px-3 py-3 space-y-6">
        <.bucket
          id="bucket-weaner"
          title={gettext("Weaner → Grower")}
          description={gettext("Older than %{n} d from birth", n: @thresholds.weaner)}
          entries={@suggestions.weaner_to_grower}
          target_stage="grower"
          can_manage={@can_manage}
          selected={@selected.weaner_to_grower}
          farm_slug={@current_scope.farm.slug}
        />

        <.bucket
          id="bucket-grower"
          title={gettext("Grower → Finisher")}
          description={gettext("Older than %{n} d from birth", n: @thresholds.grower)}
          entries={@suggestions.grower_to_finisher}
          target_stage="finisher"
          can_manage={@can_manage}
          selected={@selected.grower_to_finisher}
          farm_slug={@current_scope.farm.slug}
        />

        <section>
          <div class="flex items-baseline justify-between gap-2">
            <h2 class="text-lg font-bold">
              {gettext("Overdue finishers")}
              <span class="badge badge-warning ml-1">{length(@suggestions.finisher_overdue)}</span>
            </h2>
            <button
              :if={@can_depart and @suggestions.finisher_overdue != []}
              type="button"
              class="btn btn-sm btn-warning"
              phx-click="depart_all_overdue"
              data-confirm={
                gettext("Mark all %{n} overdue batches as sold today?",
                  n: length(@suggestions.finisher_overdue)
                )
              }
            >
              {gettext("Mark all sold")}
            </button>
          </div>
          <p class="text-sm text-base-content/60">
            {gettext("Older than %{n} d from birth.", n: @thresholds.overdue)}
          </p>

          <ul :if={@suggestions.finisher_overdue != []} class="mt-2 space-y-2">
            <li
              :for={entry <- @suggestions.finisher_overdue}
              class="p-3 rounded-xl border border-base-300 bg-base-100 flex items-center gap-3"
            >
              <.link
                navigate={~p"/m/#{@current_scope.farm.slug}/animals/#{entry.animal.id}"}
                class="flex-1 min-w-0"
              >
                <div class="font-mono font-bold text-lg truncate">
                  {entry.animal.ear_tag}
                </div>
                <div class="text-xs text-base-content/60">
                  ×{entry.animal.quantity} · {gettext("age")} {entry.age_days}d · {entry.animal.dob}
                </div>
              </.link>
              <button
                :if={@can_depart}
                type="button"
                class="btn btn-sm btn-warning"
                phx-click="depart_one"
                phx-value-id={entry.animal.id}
                data-confirm={
                  gettext("Mark batch %{tag} as sold today (qty %{qty})?",
                    tag: entry.animal.ear_tag,
                    qty: entry.animal.quantity
                  )
                }
              >
                {gettext("Sold")}
              </button>
            </li>
          </ul>

          <div :if={@suggestions.finisher_overdue == []} class="mt-2 text-sm text-base-content/60">
            {gettext("None.")}
          </div>
        </section>
      </div>
    </Layouts.mobile_app>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :entries, :list, required: true
  attr :target_stage, :string, required: true
  attr :can_manage, :boolean, required: true
  attr :selected, :any, required: true
  attr :farm_slug, :string, required: true

  defp bucket(assigns) do
    ~H"""
    <section>
      <div class="flex items-baseline justify-between">
        <h2 class="text-lg font-bold">
          {@title}
          <span class="badge badge-ghost ml-1">{length(@entries)}</span>
        </h2>
        <button
          :if={@can_manage and @entries != []}
          type="button"
          class="btn btn-sm btn-primary"
          phx-click="apply_selected"
          phx-value-bucket={@id}
          phx-value-stage={@target_stage}
          disabled={MapSet.size(@selected) == 0}
        >
          {gettext("Promote (%{n})", n: MapSet.size(@selected))}
        </button>
      </div>
      <p class="text-sm text-base-content/60">{@description}</p>

      <div :if={@entries == []} class="mt-2 text-sm text-base-content/60">
        {gettext("None due.")}
      </div>

      <div :if={@entries != []} class="mt-2 flex justify-end">
        <button
          type="button"
          class="text-xs text-primary underline"
          phx-click="toggle_all"
          phx-value-bucket={@id}
        >
          {if MapSet.size(@selected) == length(@entries),
            do: gettext("Clear all"),
            else: gettext("Select all")}
        </button>
      </div>

      <ul :if={@entries != []} class="mt-2 space-y-2">
        <li
          :for={entry <- @entries}
          class={[
            "p-3 rounded-xl border bg-base-100 flex items-center gap-3",
            if(MapSet.member?(@selected, entry.animal.id),
              do: "border-primary",
              else: "border-base-300"
            )
          ]}
          phx-click="toggle_row"
          phx-value-bucket={@id}
          phx-value-id={entry.animal.id}
        >
          <input
            type="checkbox"
            class="checkbox checkbox-lg"
            checked={MapSet.member?(@selected, entry.animal.id)}
            disabled={not @can_manage}
            readonly
          />
          <div class="flex-1 min-w-0">
            <div class="font-mono font-bold text-lg truncate">
              {entry.animal.ear_tag}
            </div>
            <div class="text-xs text-base-content/60">
              ×{entry.animal.quantity} · {gettext("age")} {entry.age_days}d · {entry.animal.dob}
            </div>
          </div>
        </li>
      </ul>
    </section>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    farm = scope.farm

    {:ok,
     socket
     |> assign(
       can_manage: Policy.can?(scope, :manage_animals),
       can_depart: Policy.can?(scope, :record_movement),
       thresholds: %{
         weaner: farm.weaner_to_grower_days,
         grower: farm.grower_to_finisher_days,
         overdue: farm.finisher_overdue_days
       },
       selected: %{
         weaner_to_grower: MapSet.new(),
         grower_to_finisher: MapSet.new()
       }
     )
     |> assign_suggestions()}
  end

  @impl true
  def handle_event("toggle_row", %{"bucket" => bucket, "id" => id}, socket) do
    bucket_key = bucket_key!(bucket)
    id = String.to_integer(id)
    set = Map.fetch!(socket.assigns.selected, bucket_key)

    set =
      if MapSet.member?(set, id), do: MapSet.delete(set, id), else: MapSet.put(set, id)

    {:noreply, update(socket, :selected, &Map.put(&1, bucket_key, set))}
  end

  def handle_event("toggle_all", %{"bucket" => bucket}, socket) do
    bucket_key = bucket_key!(bucket)
    entries = Map.fetch!(socket.assigns.suggestions, bucket_key)
    current = Map.fetch!(socket.assigns.selected, bucket_key)
    all_ids = MapSet.new(Enum.map(entries, & &1.animal.id))

    set =
      if MapSet.size(current) == MapSet.size(all_ids), do: MapSet.new(), else: all_ids

    {:noreply, update(socket, :selected, &Map.put(&1, bucket_key, set))}
  end

  def handle_event("apply_selected", %{"bucket" => bucket, "stage" => stage}, socket) do
    bucket_key = bucket_key!(bucket)
    ids = socket.assigns.selected |> Map.fetch!(bucket_key) |> MapSet.to_list()

    cond do
      ids == [] ->
        {:noreply, put_flash(socket, :error, gettext("Nothing selected."))}

      not socket.assigns.can_manage ->
        {:noreply, put_flash(socket, :error, gettext("Not authorized."))}

      true ->
        result = Animals.promote_many(socket.assigns.current_scope, ids, stage)

        flash_msg =
          case {length(result.ok), length(result.errors)} do
            {n, 0} -> gettext("Promoted %{n} batches.", n: n)
            {0, m} -> gettext("Failed to promote %{m} batches.", m: m)
            {n, m} -> gettext("Promoted %{n} batches, %{m} failed.", n: n, m: m)
          end

        flash_kind = if result.errors == [], do: :info, else: :error

        {:noreply,
         socket
         |> put_flash(flash_kind, flash_msg)
         |> assign(
           selected: %{
             weaner_to_grower: MapSet.new(),
             grower_to_finisher: MapSet.new()
           }
         )
         |> assign_suggestions()}
    end
  end

  def handle_event("depart_one", %{"id" => id}, socket) do
    apply_departure(socket, [String.to_integer(id)])
  end

  def handle_event("depart_all_overdue", _, socket) do
    ids = Enum.map(socket.assigns.suggestions.finisher_overdue, & &1.animal.id)
    apply_departure(socket, ids)
  end

  defp apply_departure(socket, []) do
    {:noreply, put_flash(socket, :error, gettext("Nothing to depart."))}
  end

  defp apply_departure(socket, ids) do
    if socket.assigns.can_depart do
      result = Animals.depart_many(socket.assigns.current_scope, ids, "sale")

      flash_msg =
        case {length(result.ok), length(result.errors)} do
          {n, 0} -> gettext("Marked %{n} batches sold.", n: n)
          {0, m} -> gettext("Failed to depart %{m} batches.", m: m)
          {n, m} -> gettext("Marked %{n} sold, %{m} failed.", n: n, m: m)
        end

      flash_kind = if result.errors == [], do: :info, else: :error

      {:noreply,
       socket
       |> put_flash(flash_kind, flash_msg)
       |> assign_suggestions()}
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  defp assign_suggestions(socket) do
    suggestions = Animals.suggest_promotions(socket.assigns.current_scope)
    assign(socket, :suggestions, suggestions)
  end

  defp bucket_key!("bucket-weaner"), do: :weaner_to_grower
  defp bucket_key!("bucket-grower"), do: :grower_to_finisher
end
