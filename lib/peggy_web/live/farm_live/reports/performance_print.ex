defmodule PeggyWeb.FarmLive.Reports.PerformancePrint do
  @moduledoc """
  Print-friendly A4 view of the Performance Analysis report. Mounts with
  the same `from`/`to` query params as the Performance page, builds the
  full matrix, and auto-opens the browser print preview.
  """
  use PeggyWeb, :live_view

  alias Peggy.Reports
  alias PeggyWeb.FarmLive.Reports.Performance

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.print flash={@flash} title={gettext("Performance Analysis")}>
      <header class="print-mono mb-2 pb-1">
        <div class="flex items-baseline justify-between gap-4">
          <div>
            <h1 class="text-xl font-semibold">{gettext("Performance Analysis")}</h1>
            <p class="text-xs">
              {@current_scope.farm.name} · {@range.from} → {@range.to}
            </p>
          </div>
        </div>
      </header>

      <table class="print-mono w-full border-collapse table-fixed tracking-tighter">
        <thead>
          <tr class="text-center">
            <th class="p-1 border-1 text-left">{gettext("Metric")}</th>
            <th :for={p <- @report.periods} class="p-1 border-1 text-right">{p.label}</th>
            <th class="p-1 border-1 text-right font-bold">{gettext("ACUM")}</th>
          </tr>
        </thead>
        <tbody>
          <%= for section <- @report.sections do %>
            <tr class="bg-base-200">
              <td class="p-1 border-1 font-semibold" colspan={length(@report.periods) + 2}>
                {section.title}
              </td>
            </tr>
            <tr :for={row <- section.rows} class="align-top break-inside-avoid">
              <td class="p-1 border-1">{row.label}</td>
              <td :for={v <- row.values} class="p-1 border-1 text-right tabular-nums">
                {Performance.fmt(v, row.format)}
              </td>
              <td class="p-1 border-1 text-right tabular-nums font-semibold">
                {Performance.fmt(row.acum, row.format)}
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>

      <footer class="print-mono mt-6 text-xs flex justify-between">
        <span>{gettext("Generated")}: {DateTime.utc_now() |> DateTime.truncate(:second)}</span>
        <span>{@current_scope.farm.slug}</span>
      </footer>

      <div id="auto-print" phx-hook=".AutoPrint" class="hidden"></div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".AutoPrint">
        export default {
          mounted() {
            this.timer = setTimeout(() => window.print(), 250)
          },
          destroyed() {
            clearTimeout(this.timer)
          }
        }
      </script>
    </Layouts.print>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    scope = socket.assigns.current_scope
    default = Reports.default_range(scope)

    range = %{
      from: parse_date(params["from"]) || Date.new!(default.to.year, 1, 1),
      to: parse_date(params["to"]) || Date.new!(default.to.year, 12, 31)
    }

    {:noreply,
     socket
     |> assign(:page_title, gettext("Print — Performance Analysis"))
     |> assign(:range, range)
     |> assign(:report, Reports.performance_analysis(scope, range))}
  end

  defp parse_date(nil), do: nil

  defp parse_date(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> d
      _ -> nil
    end
  end
end
