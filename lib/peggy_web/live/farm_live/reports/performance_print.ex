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
    <Layouts.print flash={@flash} title={gettext("Performance Analysis")} orientation="landscape">
      <table
        :for={{section, idx} <- Enum.with_index(@report.sections)}
        class={[
          "mt-10 text-[10px] leading-tight print-mono w-full border-collapse table-fixed tracking-tighter break-inside-avoid",
          idx > 0 && "break-before-page"
        ]}
      >
        <colgroup>
          <col class="w-[46mm]" />
        </colgroup>
        <thead>
          <tr class="print-thead-spacer" aria-hidden="true">
            <td colspan={length(@report.periods) + 2}></td>
          </tr>
          <tr>
            <th colspan={length(@report.periods) + 2} class="px-1 pt-1 pb-2 text-left">
              <span class="text-base font-semibold">{gettext("Performance Analysis")}</span>
              <span class="ml-2 text-[10px] font-normal">
                {@current_scope.farm.name} · {@range.from} → {@range.to}
              </span>
            </th>
          </tr>
          <tr class="bg-base-200">
            <th
              colspan={length(@report.periods) + 2}
              class="px-1 py-0.5 border-1 text-left font-semibold"
            >
              {section.title}
            </th>
          </tr>
          <tr class="text-center">
            <th class="px-1 py-0.5 border-1 text-left">{gettext("Metric")}</th>
            <th :for={p <- @report.periods} class="px-1 py-0.5 border-1 text-right whitespace-nowrap">
              {p.label}
            </th>
            <th class="px-1 py-0.5 border-1 text-right font-bold whitespace-nowrap">
              {gettext("ACUM")}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- section.rows} class="align-top break-inside-avoid">
            <td class="px-1 py-0.5 border-1">{row.label}</td>
            <td
              :for={v <- row.values}
              class="px-1 py-0.5 border-1 text-right tabular-nums whitespace-nowrap"
            >
              {Performance.fmt(v, row.format)}
            </td>
            <td class="px-1 py-0.5 border-1 text-right tabular-nums font-semibold whitespace-nowrap">
              {Performance.fmt(row.acum, row.format)}
            </td>
          </tr>
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
