defmodule PeggyWeb.FarmLive.Breeding.GestatingPrint do
  @moduledoc """
  Print-friendly view of currently-filtered gestating sows. Mounts with
  the same query params as the Gestating tab, loads every matching row
  (no pagination), and auto-opens the browser print preview where the
  user can print to paper or save as PDF.
  """
  use PeggyWeb, :live_view

  alias Peggy.{Breeding, FarmClock}
  alias PeggyWeb.FarmLive.Breeding.Shared

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.print flash={@flash} title={gettext("Gestating sows")}>
      <header class="print-mono mb-2 pb-1">
        <div class="flex items-baseline justify-between gap-4">
          <div>
            <h1 class="text-xl font-semibold">
              {gettext("Gestating sows")}
            </h1>
            <p class="text-xs">
              {@current_scope.farm.name} · {gettext("Reference date")}: {@today}
            </p>
          </div>
          <div class="text-right text-xs">
            {gettext("Total")}: <span class="font-semibold">{@total}</span>
          </div>
        </div>
        <p :if={@filter_summary != ""} class="mt-1 text-xs">
          {gettext("Filters")}: {@filter_summary}
        </p>
      </header>

      <table class="print-mono w-full border-collapse table-fixed tracking-tighter">
        <colgroup>
          <col style="width: 16%" />
          <col style="width: 14%" />
          <col style="width: 8%" />
          <col style="width: 16%" />
          <col style="width: 10%" />
          <col style="width: 30%" />
        </colgroup>
        <thead>
          <tr class="text-center">
            <th class="p-2 border-1">{gettext("Sow")}</th>
            <th class="p-2 border-1">{gettext("Pen")}</th>
            <th class="p-2 border-1">{gettext("Prty")}</th>
            <th class="p-2 border-1">{gettext("Expected")}</th>
            <th class="p-2 border-1">{gettext("Left(d)")}</th>
            <th class="p-2 border-1">{gettext("DestPen")}</th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={entry <- @rows}
            class="align-top break-inside-avoid font-mono"
          >
            <td class="p-2 border-1 font-semibold">{entry.service.sow.ear_tag}</td>
            <td class="p-2 border-1">
              {sow_pen_label(entry.service.sow)}
            </td>
            <td class="p-2 border-1 text-center">{entry.parity}</td>
            <td class="p-2 border-1">{entry.expected_farrow_date}</td>
            <td class="p-2 border-1 text-center">
              {days_left(entry, @today)}
            </td>
            <td class="p-2 border-1"></td>
          </tr>
          <tr :if={@total == 0}>
            <td colspan="6" class="py-4 text-center">
              {gettext("No gestating sows match the filters.")}
            </td>
          </tr>
        </tbody>
      </table>

      <footer class="print-mono mt-6 text-xs flex justify-between">
        <span>{gettext("Generated")}: {@generated_at}</span>
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

    filters = %{
      q: params["q"] || "",
      window: Shared.param_window(params["window"]),
      service_type: Shared.param_service_type(params["service_type"]),
      pen_search: params["pen_search"] || "",
      min_parity: params["min_parity"] || "",
      max_parity: params["max_parity"] || ""
    }

    opts = [
      search: filters.q,
      due_window: filters.window,
      service_type: filters.service_type,
      pen_search: blank_to_nil(filters.pen_search),
      min_parity: blank_to_nil(filters.min_parity),
      max_parity: blank_to_nil(filters.max_parity),
      sort: sort_param(params["sort"]),
      dir: dir_param(params["dir"]),
      limit: :all
    ]

    rows = Breeding.list_gestating_sows(scope, opts) |> attach_parity(scope)

    {:noreply,
     assign(socket,
       page_title: gettext("Print — Gestating sows"),
       filters: filters,
       rows: rows,
       total: length(rows),
       today: FarmClock.today(scope),
       generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
       filter_summary: filter_summary(filters)
     )}
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp attach_parity(rows, scope) do
    sow_ids = Enum.map(rows, & &1.service.sow_id)
    parities = Breeding.parities_for(scope, sow_ids)
    Enum.map(rows, &Map.put(&1, :parity, Map.get(parities, &1.service.sow_id, 0)))
  end

  defp days_left(%{expected_farrow_date: efd}, today), do: Date.diff(efd, today)

  defp sow_pen_label(%{current_pen: %{code: code, house: %{code: hcode}}}),
    do: "#{hcode}-#{code}"

  defp sow_pen_label(%{current_pen: %{code: code}}), do: code
  defp sow_pen_label(_), do: "—"

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  @sort_columns ~w(tag pen parity served expected left)
  defp sort_param(s) when s in @sort_columns, do: s
  defp sort_param(_), do: "served"

  defp dir_param("desc"), do: "desc"
  defp dir_param(_), do: "asc"

  defp filter_summary(filters) do
    [
      filters.q != "" && gettext("tag~%{q}", q: filters.q),
      filters.window != "all" && gettext("window=%{w}", w: filters.window),
      filters.service_type != "all" && gettext("type=%{t}", t: filters.service_type),
      filters.pen_search != "" && gettext("pen~%{p}", p: filters.pen_search),
      filters.min_parity != "" && gettext("parity≥%{n}", n: filters.min_parity),
      filters.max_parity != "" && gettext("parity≤%{n}", n: filters.max_parity)
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end
end
