defmodule PeggyWeb.FarmLive.AnimalTrace do
  @moduledoc """
  Per-animal traceability page. Walks back through pedigree (sire +
  dam, plus their parents — 2 generations up), forward to direct
  offspring, and surfaces the immutable audit log scoped to this
  animal so the operator can answer "what changed, when, by whom?"
  """
  use PeggyWeb, :live_view

  alias Peggy.{Animals, Audit, FarmClock, Repo}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-5xl">
        <div class="text-sm text-base-content/60 mb-1">
          <.link
            navigate={~p"/farms/#{@current_scope.farm.slug}/animals/#{@animal.id}"}
            class="text-primary underline hover:text-primary/80"
          >
            ← {gettext("Animal detail")}
          </.link>
        </div>

        <.header>
          <span class="font-mono">{@animal.ear_tag || "##{@animal.id}"}</span>
          <span class="ml-2 text-base font-normal text-base-content/60">
            {gettext("Traceability")}
          </span>
          <:subtitle>
            {String.capitalize(@animal.stage)} · {String.capitalize(@animal.tracking_type)}
            <span :if={@animal.dob}>· {gettext("DOB")} {@animal.dob}</span>
          </:subtitle>
        </.header>

        <%!-- Pedigree (2 generations up) --%>
        <section class="mt-6">
          <h2 class="text-sm uppercase tracking-wide text-base-content/60 mb-2">
            {gettext("Pedigree")}
          </h2>
          <div class="grid grid-cols-2 gap-3">
            <.parent_box
              label={gettext("Sire")}
              parent={@animal.sire}
              grandsire={@grandparents.sire_sire}
              granddam={@grandparents.sire_dam}
              slug={@current_scope.farm.slug}
            />
            <.parent_box
              label={gettext("Dam")}
              parent={@animal.dam}
              grandsire={@grandparents.dam_sire}
              granddam={@grandparents.dam_dam}
              slug={@current_scope.farm.slug}
            />
          </div>
        </section>

        <%!-- Offspring --%>
        <section :if={@offspring != []} class="mt-6">
          <h2 class="text-sm uppercase tracking-wide text-base-content/60 mb-2">
            {gettext("Offspring")} ({length(@offspring)})
          </h2>
          <ul class="rounded-md border border-base-200 divide-y divide-base-200">
            <li
              :for={kid <- @offspring}
              class="px-3 py-2 flex items-center justify-between text-sm"
            >
              <.link
                navigate={~p"/farms/#{@current_scope.farm.slug}/animals/#{kid.id}/trace"}
                class="font-mono text-primary underline underline-offset-2 decoration-dotted"
              >
                {kid.ear_tag || "##{kid.id}"}
              </.link>
              <span class="text-base-content/60">
                {String.capitalize(kid.stage)}
                <span :if={kid.dob}>· {kid.dob}</span>
                · <.status_badge status={kid.status} class="badge-xs" />
              </span>
            </li>
          </ul>
        </section>

        <%!-- Lifetime audit log --%>
        <section class="mt-6">
          <h2 class="text-sm uppercase tracking-wide text-base-content/60 mb-2">
            {gettext("Audit log")} ({@audit_count})
          </h2>
          <p :if={@audit_rows == []} class="text-sm text-base-content/60">
            {gettext("No audit entries for this animal yet.")}
          </p>
          <ul
            :if={@audit_rows != []}
            class="rounded-md border border-base-200 divide-y divide-base-200"
          >
            <li
              :for={row <- @audit_rows}
              class="px-3 py-2 text-sm"
            >
              <div class="flex items-baseline justify-between gap-2">
                <span class="font-mono text-xs uppercase">{row.action}</span>
                <span class="font-mono text-xs text-base-content/60">
                  {format_when(row.inserted_at, @current_scope.farm)}
                </span>
              </div>
              <div class="mt-0.5 text-xs text-base-content/60 flex flex-wrap gap-x-3">
                <span :if={row.actor_user}>
                  {gettext("by")} {row.actor_user.email}
                </span>
                <span :if={row.actor_user == nil} class="text-base-content/40">
                  {gettext("system")}
                </span>
              </div>
              <pre
                :if={row.changes && map_size(row.changes) > 0}
                class="mt-1 text-[11px] text-base-content/70 bg-base-200/40 rounded p-2 whitespace-pre-wrap font-mono"
              >{format_changes(row.changes)}</pre>
            </li>
          </ul>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :parent, :any, default: nil
  attr :grandsire, :any, default: nil
  attr :granddam, :any, default: nil
  attr :slug, :string, required: true

  defp parent_box(assigns) do
    ~H"""
    <div class="rounded-md border border-base-200 p-3">
      <div class="text-xs uppercase tracking-wide text-base-content/50">{@label}</div>
      <div :if={@parent} class="mt-1 font-mono font-semibold">
        <.link
          navigate={~p"/farms/#{@slug}/animals/#{@parent.id}/trace"}
          class="text-primary underline underline-offset-2 decoration-dotted"
        >
          {@parent.ear_tag || "##{@parent.id}"}
        </.link>
        <span :if={@parent.breed} class="text-xs text-base-content/60 ml-1">
          {@parent.breed}
        </span>
      </div>
      <div :if={is_nil(@parent)} class="mt-1 text-base-content/40">—</div>

      <div :if={@parent} class="mt-2 grid grid-cols-2 gap-2 text-xs">
        <div class="rounded border border-base-200 p-2">
          <div class="text-[10px] uppercase tracking-wide text-base-content/50">
            {gettext("%{label}'s sire", label: @label)}
          </div>
          <.parent_link parent={@grandsire} slug={@slug} />
        </div>
        <div class="rounded border border-base-200 p-2">
          <div class="text-[10px] uppercase tracking-wide text-base-content/50">
            {gettext("%{label}'s dam", label: @label)}
          </div>
          <.parent_link parent={@granddam} slug={@slug} />
        </div>
      </div>
    </div>
    """
  end

  attr :parent, :any, default: nil
  attr :slug, :string, required: true

  defp parent_link(%{parent: nil} = assigns) do
    ~H"""
    <span class="text-base-content/40">—</span>
    """
  end

  defp parent_link(assigns) do
    ~H"""
    <.link
      navigate={~p"/farms/#{@slug}/animals/#{@parent.id}/trace"}
      class="font-mono text-primary underline underline-offset-2 decoration-dotted"
    >
      {@parent.ear_tag || "##{@parent.id}"}
    </.link>
    """
  end

  # ── Mount ──────────────────────────────────────────────────────────

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    animal =
      scope
      |> Animals.get_animal!(String.to_integer(id))
      |> Repo.preload(sire: [:sire, :dam], dam: [:sire, :dam])

    offspring = Animals.list_offspring(scope, animal)

    grandparents = %{
      sire_sire: animal.sire && animal.sire.sire,
      sire_dam: animal.sire && animal.sire.dam,
      dam_sire: animal.dam && animal.dam.sire,
      dam_dam: animal.dam && animal.dam.dam
    }

    audit_rows = Audit.list(scope, entity_type: "animal", entity_id: animal.id, limit: 200)

    {:ok,
     assign(socket,
       page_title: "#{gettext("Trace")} — #{animal.ear_tag || animal.id}",
       animal: animal,
       offspring: offspring,
       grandparents: grandparents,
       audit_rows: audit_rows,
       audit_count: length(audit_rows),
       today: FarmClock.today(scope)
     )}
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp format_when(%DateTime{} = dt, %{timezone: tz}) when is_binary(tz) do
    case DateTime.shift_zone(dt, tz) do
      {:ok, local} -> Calendar.strftime(local, "%Y-%m-%d %H:%M")
      _ -> Calendar.strftime(dt, "%Y-%m-%d %H:%M") <> "Z"
    end
  end

  defp format_when(%DateTime{} = dt, _farm),
    do: Calendar.strftime(dt, "%Y-%m-%d %H:%M") <> "Z"

  defp format_changes(changes) when is_map(changes) do
    changes
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.map_join("\n", fn {k, v} -> "#{k}: #{format_value(v)}" end)
  end

  defp format_value(v) when is_binary(v), do: v
  defp format_value(v), do: inspect(v)
end
