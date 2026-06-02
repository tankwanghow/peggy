defmodule PeggyWeb.FarmLive.Reports.Performance do
  use PeggyWeb, :live_view

  alias Peggy.Reports

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-full space-y-6">
        <div class="flex flex-wrap items-end justify-between gap-3">
          <div>
            <h1 class="text-2xl font-bold">{gettext("Performance Analysis")}</h1>
            <p class="text-sm text-base-content/60">
              {gettext("Monthly breeding KPIs across the date range, with an accumulated column.")}
            </p>
          </div>
          <.form for={@form} phx-change="range" class="flex items-end gap-2">
            <.input type="date" field={@form[:from]} label={gettext("From")} />
            <.input type="date" field={@form[:to]} label={gettext("To")} />
          </.form>
          <div class="flex gap-2">
            <.link
              href={
                ~p"/farms/#{@current_scope.farm.slug}/reports/export?#{[type: "performance", from: Date.to_iso8601(@range.from), to: Date.to_iso8601(@range.to)]}"
              }
              class="btn btn-sm btn-ghost"
            >
              <.icon name="hero-arrow-down-tray-micro" class="size-3" /> {gettext("CSV")}
            </.link>
            <.iframe_print_button
              id="performance-print-btn"
              url={
                ~p"/farms/#{@current_scope.farm.slug}/reports/performance/print?#{[from: Date.to_iso8601(@range.from), to: Date.to_iso8601(@range.to)]}"
              }
            />
          </div>
        </div>

        <div class="overflow-x-auto">
          <table class="table table-xs w-full whitespace-nowrap">
            <thead>
              <tr>
                <th class="sticky left-0 bg-base-100 z-10 text-left">{gettext("Metric")}</th>
                <th :for={p <- @report.periods} class="text-xs xtext-right tabular-nums">
                  {p.label}
                </th>
                <th class="text-right font-bold">{gettext("ACUM")}</th>
              </tr>
            </thead>
            <tbody>
              <%= for section <- @report.sections do %>
                <tr class="bg-base-200">
                  <td
                    class="sticky left-0 bg-base-200 z-10 font-semibold"
                    colspan={length(@report.periods) + 2}
                  >
                    {section.title}
                  </td>
                </tr>
                <tr :for={row <- section.rows}>
                  <td class="sticky left-0 bg-base-100 z-10">{row.label}</td>
                  <td :for={v <- row.values} class="text-right tabular-nums">{fmt(v, row.format)}</td>
                  <td class="text-right tabular-nums font-semibold">{fmt(row.acum, row.format)}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    range = Reports.default_range(socket.assigns.current_scope) |> calendar_year_default()
    {:ok, assign_report(socket, range)}
  end

  @impl true
  def handle_event("range", %{"from" => from, "to" => to}, socket) do
    range = %{
      from: parse_date(from) || socket.assigns.range.from,
      to: parse_date(to) || socket.assigns.range.to
    }

    {:noreply, assign_report(socket, range)}
  end

  defp assign_report(socket, range) do
    socket
    |> assign(:range, range)
    |> assign(
      :form,
      to_form(%{"from" => Date.to_iso8601(range.from), "to" => Date.to_iso8601(range.to)})
    )
    |> assign(:report, Reports.performance_analysis(socket.assigns.current_scope, range))
  end

  # default to the current calendar year
  defp calendar_year_default(%{to: to}) do
    %{from: Date.new!(to.year, 1, 1), to: Date.new!(to.year, 12, 31)}
  end

  defp parse_date(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  @doc false
  def fmt(nil, _), do: "—"
  def fmt(v, :int), do: Integer.to_string(round(v))
  def fmt(v, _), do: :erlang.float_to_binary(v / 1, decimals: 1)
end
