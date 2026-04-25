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
      </div>
    </Layouts.app>
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
      range = Reports.default_range(socket.assigns.current_scope)
      summary = Reports.summary(socket.assigns.current_scope, range)

      {:ok,
       socket
       |> assign(range: range, summary: summary)
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
    summary = Reports.summary(socket.assigns.current_scope, range)
    {:noreply, assign(socket, range: range, summary: summary)}
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
end
