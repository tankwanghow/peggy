defmodule PeggyWeb.FarmLive.Reports do
  use PeggyWeb, :live_view

  alias Peggy.Policy
  alias Peggy.Reports

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-5xl">
        <.header>
          {gettext("Reports & KPIs")}
          <:subtitle>
            {gettext("Breeding performance across a date range.")}
          </:subtitle>
        </.header>

        <form phx-change="range" class="mt-4 flex flex-wrap items-end gap-3">
          <.input
            type="date"
            name="from"
            value={@range.from}
            label={gettext("From")}
          />
          <.input
            type="date"
            name="to"
            value={@range.to}
            label={gettext("To")}
          />
          <span class="text-sm text-base-content/60 pb-2">
            {gettext("%{n} services · %{f} farrowings · %{w} weanings",
              n: @summary.services_count,
              f: @summary.farrowings_count,
              w: @summary.weanings_count
            )}
          </span>
        </form>

        <div class="mt-3 flex flex-wrap gap-2 items-center">
          <span class="text-xs uppercase tracking-wide text-base-content/50">
            {gettext("Download CSV")}
          </span>
          <.link
            href={
              ~p"/farms/#{@current_scope.farm.slug}/reports/export?#{[type: "services", from: Date.to_iso8601(@range.from), to: Date.to_iso8601(@range.to)]}"
            }
            class="btn btn-outline btn-xs"
          >
            <.icon name="hero-arrow-down-tray-micro" class="size-3" /> {gettext("Services")}
          </.link>
          <.link
            href={
              ~p"/farms/#{@current_scope.farm.slug}/reports/export?#{[type: "farrowings", from: Date.to_iso8601(@range.from), to: Date.to_iso8601(@range.to)]}"
            }
            class="btn btn-outline btn-xs"
          >
            <.icon name="hero-arrow-down-tray-micro" class="size-3" /> {gettext("Farrowings")}
          </.link>
          <.link
            href={
              ~p"/farms/#{@current_scope.farm.slug}/reports/export?#{[type: "weanings", from: Date.to_iso8601(@range.from), to: Date.to_iso8601(@range.to)]}"
            }
            class="btn btn-outline btn-xs"
          >
            <.icon name="hero-arrow-down-tray-micro" class="size-3" /> {gettext("Weanings")}
          </.link>
        </div>

        <dl class="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <.kpi
            label={gettext("Farrowing rate")}
            value={format_pct(@summary.farrowing_rate)}
            hint={gettext("Closed services resulting in farrowing.")}
          />
          <.kpi
            label={gettext("Pre-wean mortality")}
            value={format_pct(@summary.pre_wean_mortality)}
            hint={gettext("(Born alive − weaned) ÷ born alive, across paired farrow/wean events.")}
          />
          <.kpi
            label={gettext("Pigs weaned / sow / year")}
            value={format_num(@summary.pigs_weaned_per_sow_year, 1)}
            hint={gettext("Annualised from weanings in range ÷ current breeding-herd sow count.")}
          />
          <.kpi
            label={gettext("Avg born alive")}
            value={format_num(@summary.avg_born_alive, 2)}
          />
          <.kpi
            label={gettext("Avg stillborn")}
            value={format_num(@summary.avg_stillborn, 2)}
          />
          <.kpi
            label={gettext("Avg mummified")}
            value={format_num(@summary.avg_mummified, 2)}
          />
          <.kpi
            label={gettext("Avg weaned / litter")}
            value={format_num(@summary.avg_weaned, 2)}
          />
          <.kpi
            label={gettext("Wean-to-service (days)")}
            value={format_num(@summary.avg_wean_to_service_days, 1)}
            hint={gettext("Avg days from wean to next service landing in range.")}
          />
        </dl>

        <%!-- Pivot builder + chart --%>
        <section class="mt-10">
          <h2 class="text-lg font-semibold">{gettext("Pivot")}</h2>
          <p class="text-sm text-base-content/60 mb-3">
            {gettext("Time-bucketed aggregate over the active date range.")}
          </p>

          <form phx-change="pivot" class="flex flex-wrap items-end gap-3">
            <.input
              name="source"
              type="select"
              label={gettext("Source")}
              value={to_string(@pivot_source)}
              class="select select-sm"
              options={[
                {gettext("Services"), "services"},
                {gettext("Farrowings"), "farrowings"},
                {gettext("Weanings"), "weanings"}
              ]}
            />
            <.input
              name="metric"
              type="select"
              label={gettext("Metric")}
              value={to_string(@pivot_metric)}
              class="select select-sm"
              options={metric_options(@pivot_source)}
            />
            <.input
              name="bucket"
              type="select"
              label={gettext("Bucket")}
              value={to_string(@pivot_bucket)}
              class="select select-sm"
              options={[
                {gettext("Week"), "week"},
                {gettext("Month"), "month"}
              ]}
            />
          </form>

          <.bar_chart
            data={@pivot_data}
            label={metric_label(@pivot_source, @pivot_metric)}
            bucket={@pivot_bucket}
          />

          <%!-- Backing table --%>
          <div :if={@pivot_data != []} class="mt-4 overflow-x-auto">
            <table class="table table-sm w-full text-sm">
              <thead class="text-left text-base-content/60">
                <tr>
                  <th class="py-2">{gettext("Bucket")}</th>
                  <th class="py-2 text-right">{metric_label(@pivot_source, @pivot_metric)}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @pivot_data} class="border-t border-base-200">
                  <td class="py-2 font-mono">{format_bucket(row.bucket, @pivot_bucket)}</td>
                  <td class="py-2 text-right font-mono">{row.value}</td>
                </tr>
                <tr class="border-t border-base-300 font-semibold">
                  <td class="py-2">{gettext("Total")}</td>
                  <td class="py-2 text-right font-mono">
                    {Enum.reduce(@pivot_data, 0, &(&1.value + &2))}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :data, :list, required: true
  attr :label, :string, required: true
  attr :bucket, :atom, required: true

  defp bar_chart(%{data: []} = assigns) do
    ~H"""
    <p class="mt-4 text-sm text-base-content/60">{gettext("No data in range.")}</p>
    """
  end

  defp bar_chart(assigns) do
    max = assigns.data |> Enum.map(& &1.value) |> Enum.max(fn -> 1 end) |> max(1)
    bar_w = 28
    gap = 8
    chart_w = length(assigns.data) * (bar_w + gap)
    chart_h = 180

    bars =
      assigns.data
      |> Enum.with_index()
      |> Enum.map(fn {row, i} ->
        height = row.value / max * (chart_h - 30)
        x = i * (bar_w + gap)
        y = chart_h - 20 - height

        %{
          x: x,
          y: y,
          width: bar_w,
          height: height,
          value: row.value,
          label: format_bucket(row.bucket, assigns.bucket)
        }
      end)

    assigns = assign(assigns, bars: bars, chart_w: chart_w, chart_h: chart_h)

    ~H"""
    <div class="mt-4 overflow-x-auto">
      <svg
        viewBox={"0 0 #{@chart_w} #{@chart_h}"}
        width={@chart_w}
        height={@chart_h}
        class="text-primary"
      >
        <g
          :for={bar <- @bars}
          class="hover:opacity-80"
        >
          <rect
            x={bar.x}
            y={bar.y}
            width={bar.width}
            height={bar.height}
            fill="currentColor"
            rx="2"
          />
          <text
            :if={bar.value > 0}
            x={bar.x + bar.width / 2}
            y={bar.y - 4}
            text-anchor="middle"
            class="fill-base-content text-[10px] font-mono"
          >
            {bar.value}
          </text>
          <text
            x={bar.x + bar.width / 2}
            y={@chart_h - 4}
            text-anchor="middle"
            class="fill-base-content/60 text-[9px] font-mono"
          >
            {bar.label}
          </text>
        </g>
      </svg>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :hint, :string, default: nil

  defp kpi(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-200 bg-base-100 p-4">
      <dt class="text-sm text-base-content/60">{@label}</dt>
      <dd class="mt-1 text-2xl font-semibold tabular-nums">{@value}</dd>
      <p :if={@hint} class="mt-1 text-xs text-base-content/50">{@hint}</p>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if Policy.can?(socket.assigns.current_scope, :view_reports) do
      scope = socket.assigns.current_scope
      range = Reports.default_range(scope)
      summary = Reports.summary(scope, range)

      pivot_source = :farrowings
      pivot_metric = :count
      pivot_bucket = :month

      pivot_data =
        Reports.pivot(scope,
          source: pivot_source,
          metric: pivot_metric,
          bucket: pivot_bucket,
          range: range
        )

      {:ok,
       socket
       |> assign(
         range: range,
         summary: summary,
         pivot_source: pivot_source,
         pivot_metric: pivot_metric,
         pivot_bucket: pivot_bucket,
         pivot_data: pivot_data
       )
       |> assign(:page_title, gettext("Reports"))}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("You do not have access to reports."))
       |> redirect(to: ~p"/farms/#{socket.assigns.current_scope.farm.slug}")}
    end
  end

  @impl true
  def handle_event("range", params, socket) do
    range = parse_range(params, socket.assigns.range)
    scope = socket.assigns.current_scope
    summary = Reports.summary(scope, range)
    pivot_data = compute_pivot(scope, socket.assigns, range)
    {:noreply, assign(socket, range: range, summary: summary, pivot_data: pivot_data)}
  end

  def handle_event("pivot", params, socket) do
    new_source = parse_source(params["source"], socket.assigns.pivot_source)

    # Switching source may invalidate the current metric — fall back to count.
    new_metric =
      params["metric"]
      |> parse_metric(new_source, socket.assigns.pivot_metric)

    new_bucket = parse_bucket(params["bucket"], socket.assigns.pivot_bucket)
    scope = socket.assigns.current_scope

    pivot_data =
      Reports.pivot(scope,
        source: new_source,
        metric: new_metric,
        bucket: new_bucket,
        range: socket.assigns.range
      )

    {:noreply,
     assign(socket,
       pivot_source: new_source,
       pivot_metric: new_metric,
       pivot_bucket: new_bucket,
       pivot_data: pivot_data
     )}
  end

  defp compute_pivot(scope, assigns, range) do
    Reports.pivot(scope,
      source: assigns.pivot_source,
      metric: assigns.pivot_metric,
      bucket: assigns.pivot_bucket,
      range: range
    )
  end

  defp parse_range(%{"from" => from_s, "to" => to_s}, fallback) do
    %{from: parse_date(from_s, fallback.from), to: parse_date(to_s, fallback.to)}
  end

  defp parse_date(s, fallback) do
    case Date.from_iso8601(s) do
      {:ok, d} -> d
      _ -> fallback
    end
  end

  defp format_pct(nil), do: "—"
  defp format_pct(v) when is_number(v), do: :erlang.float_to_binary(v * 100, decimals: 1) <> "%"

  defp format_num(nil, _), do: "—"
  defp format_num(v, d) when is_number(v), do: :erlang.float_to_binary(v * 1.0, decimals: d)

  # ── Pivot helpers ─────────────────────────────────────────────────

  defp parse_source("services", _), do: :services
  defp parse_source("farrowings", _), do: :farrowings
  defp parse_source("weanings", _), do: :weanings
  defp parse_source(_, fallback), do: fallback

  defp parse_bucket("week", _), do: :week
  defp parse_bucket("month", _), do: :month
  defp parse_bucket(_, fallback), do: fallback

  defp parse_metric(s, source, fallback) do
    metric =
      case s do
        "count" -> :count
        "sum_born_alive" -> :sum_born_alive
        "sum_stillborn" -> :sum_stillborn
        "sum_mummified" -> :sum_mummified
        "sum_weaned" -> :sum_weaned
        _ -> fallback
      end

    if metric in valid_metrics(source), do: metric, else: :count
  end

  defp valid_metrics(:services), do: [:count]

  defp valid_metrics(:farrowings),
    do: [:count, :sum_born_alive, :sum_stillborn, :sum_mummified]

  defp valid_metrics(:weanings), do: [:count, :sum_weaned]

  defp metric_options(:services), do: [{gettext("Count"), "count"}]

  defp metric_options(:farrowings),
    do: [
      {gettext("Count"), "count"},
      {gettext("Born alive (sum)"), "sum_born_alive"},
      {gettext("Stillborn (sum)"), "sum_stillborn"},
      {gettext("Mummified (sum)"), "sum_mummified"}
    ]

  defp metric_options(:weanings),
    do: [
      {gettext("Count"), "count"},
      {gettext("Weaned (sum)"), "sum_weaned"}
    ]

  defp metric_label(:services, :count), do: gettext("Services")
  defp metric_label(:farrowings, :count), do: gettext("Farrowings")
  defp metric_label(:farrowings, :sum_born_alive), do: gettext("Born alive")
  defp metric_label(:farrowings, :sum_stillborn), do: gettext("Stillborn")
  defp metric_label(:farrowings, :sum_mummified), do: gettext("Mummified")
  defp metric_label(:weanings, :count), do: gettext("Weanings")
  defp metric_label(:weanings, :sum_weaned), do: gettext("Weaned")
  defp metric_label(_, _), do: ""

  # Compact x-axis labels: months as "MMM YY", weeks as "MM-DD".
  defp format_bucket(%Date{} = d, :month), do: Calendar.strftime(d, "%b %y")
  defp format_bucket(%Date{} = d, :week), do: Calendar.strftime(d, "%m-%d")
  defp format_bucket(d, _), do: to_string(d)
end
