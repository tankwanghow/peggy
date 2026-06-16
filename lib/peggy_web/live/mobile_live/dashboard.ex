defmodule PeggyWeb.MobileLive.Dashboard do
  @moduledoc """
  Mobile dashboard. Glance-readable KPIs at the top, then quick-access
  cards into the workflows that mobile actually supports today.
  """
  use PeggyWeb, :live_view

  alias Peggy.{Breeding, FarmClock}

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
      <section class="px-3 grid grid-cols-3 gap-3">
        <.kpi_tile
          label={gettext("Serviceable")}
          value={@kpi.serviceable}
          tone={:accent}
          to={~p"/m/#{@current_scope.farm.slug}/breeding/serviceable"}
        />
        <.kpi_tile
          label={gettext("Gestating")}
          value={@kpi.gestating}
          tone={:info}
          to={~p"/m/#{@current_scope.farm.slug}/breeding/gestating"}
        />
        <.kpi_tile
          label={gettext("Lactating")}
          value={@kpi.lactating}
          tone={:success}
          to={~p"/m/#{@current_scope.farm.slug}/breeding/lactating"}
        />
        <.kpi_tile
          label={gettext("Wean due (this wk)")}
          value={@kpi.wean_due}
          tone={tone_for_count(@kpi.wean_due)}
          to={~p"/m/#{@current_scope.farm.slug}/breeding/lactating?#{[age: "wean_due"]}"}
        />
        <.kpi_tile
          label={gettext("Farrow due (≤7d)")}
          value={@kpi.farrow_due}
          tone={tone_for_count(@kpi.farrow_due)}
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
            icon="hero-sparkles"
            label={gettext("Serviceable sows")}
            sub={gettext("Sows ready for a new service")}
            to={~p"/m/#{@current_scope.farm.slug}/breeding/serviceable"}
          />
          <.workflow_link
            icon="hero-clipboard-document-list"
            label={gettext("Gestating sows")}
            sub={gettext("Record farrowings, close failed services")}
            to={~p"/m/#{@current_scope.farm.slug}/breeding/gestating"}
          />
          <.workflow_link
            icon="hero-heart"
            label={gettext("Lactating sows")}
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
      class="rounded-xl border border-base-300 bg-base-100 p-4 active:bg-base-200
             flex flex-col gap-1"
    >
      <span class={[
        "text-3xl font-mono font-bold leading-none",
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

  attr :icon, :string, required: true
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
        <.icon name={@icon} class="size-6 text-primary" />
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

    kpi = %{
      serviceable: Breeding.count_serviceable(scope),
      lactating: Breeding.count_lactating_sows(scope),
      gestating: Breeding.count_gestating_sows(scope),
      wean_due: Breeding.count_lactating_sows(scope, age_bucket: "wean_due"),
      farrow_due: Breeding.count_gestating_sows(scope, due_window: "7")
    }

    {:ok, assign(socket, today: today, kpi: kpi, page_title: gettext("Dashboard"))}
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp tone_for_count(0), do: :neutral
  defp tone_for_count(n) when n > 0, do: :warning
end
