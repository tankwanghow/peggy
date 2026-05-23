defmodule PeggyWeb.FarmLive.Dashboard do
  use PeggyWeb, :live_view

  alias Peggy.{Breeding, FarmClock, Reports}

  @stage_labels %{
    "sow" => "Sows",
    "boar" => "Boars",
    "weaner" => "Weaners",
    "grower" => "Growers",
    "finisher" => "Finishers",
    "cull" => "Cull"
  }

  @sow_status_labels %{
    "active" => "Active",
    "open" => "Open",
    "served" => "Served",
    "lactating" => "Lactating",
    "dry" => "Dry"
  }

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-6xl space-y-8">
        <section class="grid gap-4 lg:grid-cols-2" aria-label={gettext("Action list")}>
          <div class="rounded-lg border border-base-200 bg-base-100 p-4">
            <div class="flex items-baseline justify-between">
              <h2 class="text-lg font-semibold">{gettext("This week")}</h2>
              <span class="text-xs text-base-content/50">
                {Calendar.strftime(@today, "%a %d %b %Y")}
              </span>
            </div>

            <ul class="mt-3 divide-y divide-base-200">
              <.action_row
                icon="hero-heart-micro"
                label={gettext("Sows due to farrow (≤7d)")}
                count={length(@actions.due_to_farrow_7d)}
                href={~p"/farms/#{@current_scope.farm.slug}/breeding/gestating?window=7"}
              />
              <.action_row
                :if={@actions.overdue_farrow_count > 0}
                icon="hero-exclamation-triangle-micro"
                label={gettext("Overdue to farrow")}
                count={@actions.overdue_farrow_count}
                tone="warn"
                href={~p"/farms/#{@current_scope.farm.slug}/breeding/gestating?window=overdue"}
              />
              <.action_row
                icon="hero-hand-raised-micro"
                label={gettext("Litters due to wean (>%{d}d)", d: @wean_due_days)}
                count={@actions.due_to_wean_count}
                href={~p"/farms/#{@current_scope.farm.slug}/breeding/lactating?age=wean_due"}
              />
              <.action_row
                :if={@actions.active_sow_count > 0}
                icon="hero-sparkles-micro"
                label={gettext("Active sows — awaiting first service")}
                count={@actions.active_sow_count}
                href={~p"/farms/#{@current_scope.farm.slug}/animals?stage=sow&status=active"}
              />
              <.action_row
                icon="hero-arrow-path-micro"
                label={gettext("Dry sows — ready to service")}
                count={@actions.dry_sow_count}
                href={~p"/farms/#{@current_scope.farm.slug}/animals?stage=sow&status=dry"}
              />
              <.action_row
                :if={@actions.open_sow_count > 0}
                icon="hero-arrow-uturn-left-micro"
                label={gettext("Open sows — re-service")}
                count={@actions.open_sow_count}
                tone="warn"
                href={~p"/farms/#{@current_scope.farm.slug}/animals?stage=sow&status=open"}
              />
              <.action_row
                :if={@actions.needs_review_count > 0}
                icon="hero-question-mark-circle-micro"
                label={gettext("Records needing review")}
                count={@actions.needs_review_count}
                tone="warn"
                href={~p"/farms/#{@current_scope.farm.slug}/animals?needs_review=1"}
              />
            </ul>
          </div>

          <div class="rounded-lg border border-base-200 bg-base-100 p-4">
            <h2 class="text-lg font-semibold">{gettext("Herd snapshot")}</h2>
            <p class="mt-1 text-sm text-base-content/60">
              {gettext("%{n} animals on farm, %{p} piglets nursing",
                n: @snapshot.present_total,
                p: @snapshot.nursing_piglets
              )}
            </p>

            <div class="mt-3 grid grid-cols-2 gap-4">
              <div>
                <h3 class="text-xs uppercase tracking-wide text-base-content/60">
                  {gettext("By stage")}
                </h3>
                <dl class="mt-1 space-y-0.5 text-sm">
                  <.link
                    :for={{key, stage, count} <- stages_for_display(@snapshot.by_stage)}
                    navigate={~p"/farms/#{@current_scope.farm.slug}/animals?stage=#{key}"}
                    class="group flex items-center justify-between rounded px-2 py-1 -mx-1 bg-base-200/40 hover:bg-primary/10 cursor-pointer transition-colors"
                  >
                    <dt class="flex items-center gap-1 text-primary underline underline-offset-2 decoration-dotted">
                      {stage}
                      <.icon
                        name="hero-arrow-right-micro"
                        class="size-3 opacity-100 transition-transform group-hover:translate-x-0.5"
                      />
                    </dt>
                    <dd class="tabular-nums font-medium">{count}</dd>
                  </.link>
                </dl>
              </div>
              <div>
                <h3 class="text-xs uppercase tracking-wide text-base-content/60">
                  {gettext("Sow status")}
                </h3>
                <dl class="mt-1 space-y-0.5 text-sm">
                  <.link
                    :for={{key, status, count} <- sow_statuses_for_display(@snapshot.sow_status)}
                    navigate={~p"/farms/#{@current_scope.farm.slug}/animals?stage=sow&status=#{key}"}
                    class="group flex items-center justify-between rounded px-2 py-1 -mx-1 bg-base-200/40 hover:bg-primary/10 cursor-pointer transition-colors"
                  >
                    <dt class="flex items-center gap-1 text-primary underline underline-offset-2 decoration-dotted">
                      {status}
                      <.icon
                        name="hero-arrow-right-micro"
                        class="size-3 opacity-100 transition-transform group-hover:translate-x-0.5"
                      />
                    </dt>
                    <dd class="tabular-nums font-medium">{count}</dd>
                  </.link>
                </dl>
              </div>
            </div>

            <div class="mt-4 border-t border-base-200 pt-3">
              <h3 class="text-xs uppercase tracking-wide text-base-content/60">
                {gettext("Pens")}
              </h3>
              <p class="mt-1 text-sm">
                {gettext("%{u} utilisation · %{e} empty · %{o} over capacity",
                  u: format_pct(@snapshot.pen_stats.avg_utilization),
                  e: @snapshot.pen_stats.empty,
                  o: @snapshot.pen_stats.overcapacity
                )}
              </p>
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  # ── Slots ──────────────────────────────────────────────────────────

  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :href, :string, required: true
  attr :tone, :string, default: "neutral"

  defp action_row(assigns) do
    ~H"""
    <li>
      <.link
        navigate={@href}
        class="group flex items-center justify-between gap-2 py-2 px-2 -mx-2 rounded hover:bg-primary/10 transition-colors"
      >
        <span class="flex items-center gap-2 text-sm">
          <.icon
            name={@icon}
            class={["size-4", @tone == "warn" && "text-warning"]}
          />
          {@label}
        </span>
        <span class="flex items-center gap-1.5">
          <span class={[
            "rounded-full px-2 py-0.5 text-xs font-semibold tabular-nums",
            @tone == "warn" && "bg-warning/20 text-warning",
            @tone != "warn" && "bg-base-200"
          ]}>
            {@count}
          </span>
          <.icon
            name="hero-chevron-right-micro"
            class="size-4 text-base-content/40 transition-transform group-hover:translate-x-0.5"
          />
        </span>
      </.link>
    </li>
    """
  end

  # ── Lifecycle ──────────────────────────────────────────────────────

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     socket
     |> assign(:today, FarmClock.today(scope))
     |> assign(:wean_due_days, Breeding.wean_due_days(scope))
     |> assign(:snapshot, Reports.herd_snapshot(scope))
     |> assign(:actions, Reports.action_list(scope))}
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp stages_for_display(by_stage) do
    @stage_labels
    |> Enum.map(fn {key, label} -> {key, label, Map.get(by_stage, key, 0) || 0} end)
    |> Enum.reject(fn {_key, _label, count} -> count == 0 end)
  end

  defp sow_statuses_for_display(sow_status) do
    @sow_status_labels
    |> Enum.map(fn {key, label} -> {key, label, Map.get(sow_status, key, 0) || 0} end)
  end

  defp format_pct(nil), do: "—"
  defp format_pct(v) when is_number(v), do: :erlang.float_to_binary(v * 100, decimals: 1) <> "%"
end
