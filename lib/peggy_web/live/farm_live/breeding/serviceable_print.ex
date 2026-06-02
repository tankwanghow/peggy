defmodule PeggyWeb.FarmLive.Breeding.ServiceablePrint do
  @moduledoc """
  Print-friendly view of currently-filtered serviceable females. Mounts
  with the same query params as the Serviceable tab, loads every matching
  row (no pagination), and auto-opens the browser print preview where the
  user can print to paper or save as PDF.
  """
  use PeggyWeb, :live_view

  alias Peggy.{Breeding, FarmClock}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.print flash={@flash} title={gettext("Serviceable")}>
      <header class="print-mono mb-2 pb-1">
        <div class="flex items-baseline justify-between gap-4">
          <div>
            <h1 class="text-xl font-semibold">
              {gettext("Serviceable")}
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
          <col style="width: 12%" />
          <col style="width: 8%" />
          <col style="width: 22%" />
          <col style="width: 10%" />
          <col style="width: 18%" />
        </colgroup>
        <thead>
          <tr class="print-thead-spacer" aria-hidden="true">
            <td colspan="7"></td>
          </tr>
          <tr class="text-center">
            <th class="p-2 border-1">{gettext("Sow")}</th>
            <th class="p-2 border-1">{gettext("Status")}</th>
            <th class="p-2 border-1">{gettext("Pen")}</th>
            <th class="p-2 border-1">{gettext("Prty")}</th>
            <th class="p-2 border-1">{gettext("Last event")}</th>
            <th class="p-2 border-1">{gettext("Idle(d)")}</th>
            <th class="p-2 border-1">{gettext("Note")}</th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={e <- @rows}
            class="align-top break-inside-avoid font-mono"
          >
            <td class="p-2 border-1 font-semibold">{e.animal.ear_tag}</td>
            <td class="p-2 border-1 uppercase">
              {e.animal.status}<span :if={e.animal.status == "served"}> ({gettext("in heat")})</span>
            </td>
            <td class="p-2 border-1">{sow_pen_label(e.animal)}</td>
            <td class="p-2 border-1 text-center">{e.parity}</td>
            <td class="p-2 border-1 whitespace-nowrap">{last_event_label(e)}</td>
            <td class="p-2 border-1 text-center">{idle_text(e.days_idle)}</td>
            <td class="p-2 border-1"></td>
          </tr>
          <tr :if={@total == 0}>
            <td colspan="7" class="py-4 text-center">
              {gettext("No serviceable females match the filters.")}
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
      status: status_param(params["status"]),
      pen_search: params["pen_search"] || "",
      min_parity: params["min_parity"] || "",
      max_parity: params["max_parity"] || ""
    }

    opts = [
      search: filters.q,
      status: filters.status,
      pen_search: blank_to_nil(filters.pen_search),
      min_parity: blank_to_nil(filters.min_parity),
      max_parity: blank_to_nil(filters.max_parity),
      sort: serviceable_sort_param(params["sort"]),
      dir: dir_param(params["dir"]),
      limit: :all
    ]

    rows = Breeding.list_serviceable(scope, opts)

    {:noreply,
     assign(socket,
       page_title: gettext("Print — Serviceable"),
       filters: filters,
       rows: rows,
       total: length(rows),
       today: FarmClock.today(scope),
       generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
       filter_summary: filter_summary(filters)
     )}
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp sow_pen_label(%{current_pen: %{code: code, house: %{code: hcode}}}),
    do: "#{hcode}-#{code}"

  defp sow_pen_label(%{current_pen: %{code: code}}), do: code
  defp sow_pen_label(_), do: "—"

  defp idle_text(nil), do: "—"
  defp idle_text(d), do: Integer.to_string(d)

  # Last-event label only (no date) so the column never wraps.
  defp last_event_label(%{last_event_kind: :served} = e),
    do: gettext("Mnt") <> "-" <> Integer.to_string(e.mounting_count || 1)

  defp last_event_label(%{last_event_kind: :weaned}), do: gettext("Weaned")
  defp last_event_label(%{last_event_kind: :farrowed}), do: gettext("Farrowed")
  defp last_event_label(%{last_event_kind: :aborted}), do: gettext("Aborted/Failed")
  defp last_event_label(_), do: "—"

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  @sort_columns ~w(tag pen parity idle status)
  defp serviceable_sort_param(s) when s in @sort_columns, do: s
  defp serviceable_sort_param(_), do: "idle"

  defp dir_param("asc"), do: "asc"
  defp dir_param(_), do: "desc"

  defp status_param(s) when s in ~w(open dry active served_outside_window), do: s
  defp status_param(_), do: "all"

  defp filter_summary(filters) do
    [
      filters.q != "" && gettext("tag~%{q}", q: filters.q),
      filters.status != "all" && gettext("status=%{s}", s: filters.status),
      filters.pen_search != "" && gettext("pen~%{p}", p: filters.pen_search),
      filters.min_parity != "" && gettext("parity≥%{n}", n: filters.min_parity),
      filters.max_parity != "" && gettext("parity≤%{n}", n: filters.max_parity)
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end
end
