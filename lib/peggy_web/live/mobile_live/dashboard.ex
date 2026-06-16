defmodule PeggyWeb.MobileLive.Dashboard do
  @moduledoc """
  Mobile dashboard. Glance-readable KPIs at the top, then quick-access
  cards into the workflows that mobile actually supports today.
  """
  use PeggyWeb, :live_view

  alias Peggy.{Animals, Breeding, FarmClock, Reports}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_app flash={@flash} current_scope={@current_scope} active={:home}>
      <header class="px-4 pt-4 pb-2">
        <h1 class="text-2xl font-bold leading-tight">{@current_scope.farm.slug}</h1>
        <p class="text-xs text-base-content/60 font-mono">
          {gettext("Reference date")}: {@today}
        </p>
      </header>

      <%!-- KPI tiles --%>
      <section class="px-4 grid grid-cols-3 gap-1">
        <.kpi_tile
          label={gettext("Piglets")}
          value={@kpi.piglets}
          to={~p"/m/#{@current_scope.farm.slug}/breeding/lactating"}
        />
        <.kpi_tile
          label={gettext("Weaners")}
          value={@kpi.weaner}
          tone={tone_for_promotion_ready(@kpi.weaner_promote)}
          to={~p"/m/#{@current_scope.farm.slug}/animals?#{[stage: "weaner"]}"}
        />
        <.kpi_tile
          label={gettext("Growers")}
          value={@kpi.grower}
          tone={tone_for_promotion_ready(@kpi.grower_promote)}
          to={~p"/m/#{@current_scope.farm.slug}/animals?#{[stage: "grower"]}"}
        />
        <.kpi_tile
          label={gettext("Finishers")}
          value={@kpi.finisher}
          tone={tone_for_overdue(@kpi.finisher_overdue)}
          to={~p"/m/#{@current_scope.farm.slug}/animals?#{[stage: "finisher"]}"}
        />
        <.kpi_tile
          label={gettext("Dry sows")}
          value={@kpi.dry_sow}
          tone={tone_for_opportunity(@kpi.dry_sow)}
          to={~p"/m/#{@current_scope.farm.slug}/animals?#{[stage: "sow", status: "dry"]}"}
        />
        <.kpi_tile
          label={gettext("Open sows")}
          value={@kpi.open_sow}
          tone={tone_for_due(@kpi.open_sow)}
          to={~p"/m/#{@current_scope.farm.slug}/animals?#{[stage: "sow", status: "open"]}"}
        />
        <.kpi_tile
          label={gettext("Total sows")}
          value={@kpi.total_sows}
          to={~p"/m/#{@current_scope.farm.slug}/animals?#{[stage: "sow"]}"}
        />
        <.kpi_tile
          label={gettext("Wean due (this wk)")}
          value={@kpi.wean_due}
          tone={tone_for_due(@kpi.wean_due)}
          to={~p"/m/#{@current_scope.farm.slug}/breeding/lactating?#{[age: "wean_due"]}"}
        />
        <.kpi_tile
          label={gettext("Farrow due (≤7d)")}
          value={@kpi.farrow_due}
          tone={tone_for_due(@kpi.farrow_due)}
          to={~p"/m/#{@current_scope.farm.slug}/breeding/gestating?#{[window: "7"]}"}
        />
      </section>

      <%!-- Quick actions --%>
      <section class="px-4 pt-6">
        <h2 class="text-xs uppercase tracking-wide text-base-content/50 mb-2">
          {gettext("Workflows")}
        </h2>
        <ul class="space-y-2">
          <.workflow_link
            emoji="💓"
            label={gettext("Serviceable sows") <> " (#{Integer.to_string(@kpi.serviceable)})"}
            sub={gettext("Sows ready for a new service")}
            to={~p"/m/#{@current_scope.farm.slug}/breeding/serviceable"}
          />
          <.workflow_link
            emoji="🤰"
            label={gettext("Gestating sows") <> " (#{Integer.to_string(@kpi.gestating)})"}
            sub={gettext("Record farrowings, close failed services")}
            to={~p"/m/#{@current_scope.farm.slug}/breeding/gestating"}
          />
          <.workflow_link
            emoji="🤱"
            label={gettext("Lactating sows") <> " (#{Integer.to_string(@kpi.lactating)})"}
            sub={gettext("Wean, foster, record deaths")}
            to={~p"/m/#{@current_scope.farm.slug}/breeding/lactating"}
          />
        </ul>
      </section>
    </Layouts.mobile_app>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :tone, :atom, default: :neutral
  attr :to, :string, required: true

  defp kpi_tile(assigns) do
    ~H"""
    <.link
      navigate={@to}
      class="rounded-xl border border-base-300 bg-base-100 p-2 active:bg-base-200
             flex flex-col gap-1"
    >
      <span class={[
        "text-xl font-mono font-bold leading-none",
        @tone == :success && "text-success",
        @tone == :info && "text-info",
        @tone == :warning && "text-warning",
        @tone == :error && "text-error",
        @tone == :accent && "text-accent",
        @tone == :neutral && "text-base-content"
      ]}>
        {@value}
      </span>
      <span class="text-xs text-base-content/60">{@label}</span>
    </.link>
    """
  end

  attr :emoji, :string, required: true
  attr :label, :string, required: true
  attr :sub, :string, required: true
  attr :to, :string, required: true

  defp workflow_link(assigns) do
    ~H"""
    <li>
      <.link
        navigate={@to}
        class="flex items-center gap-3 p-4 rounded-xl border border-base-300 bg-base-100
               active:bg-base-200"
      >
        <span class="text-4xl text-primary">{@emoji}</span>
        <div class="flex-1">
          <div class="font-semibold">{@label}</div>
          <div class="text-xs text-base-content/60">{@sub}</div>
        </div>
        <.icon name="hero-chevron-right-micro" class="size-4 text-base-content/40" />
      </.link>
    </li>
    """
  end

  # ── Mount ──────────────────────────────────────────────────────────

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    today = FarmClock.today(scope)
    snapshot = Reports.herd_snapshot(scope)
    promotions = Animals.suggest_promotions(scope)

    kpi = %{
      piglets: snapshot.nursing_piglets,
      weaner: stage_count(snapshot, "weaner"),
      grower: stage_count(snapshot, "grower"),
      finisher: stage_count(snapshot, "finisher"),
      weaner_promote: promotion_head(promotions, :weaner_to_grower),
      grower_promote: promotion_head(promotions, :grower_to_finisher),
      finisher_overdue: promotion_head(promotions, :finisher_overdue),
      dry_sow: sow_status_count(snapshot, "dry"),
      open_sow: sow_status_count(snapshot, "open"),
      total_sows: stage_count(snapshot, "sow"),
      serviceable: Breeding.count_serviceable(scope),
      lactating: Breeding.count_lactating_sows(scope),
      gestating: Breeding.count_gestating_sows(scope),
      wean_due: Breeding.count_lactating_sows(scope, age_bucket: "wean_due"),
      farrow_due: Breeding.count_gestating_sows(scope, due_window: "7")
    }

    {:ok, assign(socket, today: today, kpi: kpi, page_title: gettext("Dashboard"))}
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp stage_count(%{by_stage: by_stage}, stage),
    do: Map.get(by_stage, stage, 0) || 0

  defp sow_status_count(%{sow_status: sow_status}, status),
    do: Map.get(sow_status, status, 0) || 0

  defp promotion_head(buckets, key) do
    buckets
    |> Map.get(key, [])
    |> Enum.reduce(0, fn %{animal: a}, acc -> acc + (a.quantity || 0) end)
  end

  defp tone_for_due(0), do: :neutral
  defp tone_for_due(_), do: :warning

  defp tone_for_opportunity(0), do: :neutral
  defp tone_for_opportunity(_), do: :accent

  defp tone_for_promotion_ready(0), do: :neutral
  defp tone_for_promotion_ready(_), do: :info

  defp tone_for_overdue(0), do: :neutral
  defp tone_for_overdue(_), do: :warning
end
