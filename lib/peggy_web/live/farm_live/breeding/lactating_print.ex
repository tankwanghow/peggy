defmodule PeggyWeb.FarmLive.Breeding.LactatingPrint do
  @moduledoc """
  Print-friendly view of currently-filtered lactating sows. Mounts with
  the same query params as the Lactating tab, loads every matching row
  (no pagination), and auto-opens the browser print preview where the
  user can print to paper or save as PDF. DestPen and WeanAmt columns
  are intentionally blank for the operator to fill in at the barn.
  """
  use PeggyWeb, :live_view

  alias Peggy.{Breeding, FarmClock}
  alias PeggyWeb.FarmLive.Breeding.Shared

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.print flash={@flash} title={gettext("Lactating sows")}>
      <header class="print-mono mb-2 border-b border-black pb-1">
        <div class="flex items-baseline justify-between gap-4">
          <div>
            <h1 class="text-xl font-semibold">
              {gettext("Lactating sows")}
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

      <table class="print-mono w-full border-collapse table-fixed">
        <colgroup>
          <col style="width: 18%" />
          <col style="width: 14%" />
          <col style="width: 10%" />
          <col style="width: 16%" />
          <col style="width: 12%" />
          <col style="width: 8%" />
          <col style="width: 10%" />
          <col style="width: 10%" />
        </colgroup>
        <thead>
          <tr class="border-b-2 border-black text-[12px] uppercase leading-tight">
            <th class="py-0.5 pr-2 text-left">{gettext("Sow")}</th>
            <th class="py-0.5 pr-2 text-left">{gettext("Pen")}</th>
            <th class="py-0.5 pr-2 text-center">{gettext("Parity")}</th>
            <th class="py-0.5 pr-2 text-left">{gettext("Farrowed")}</th>
            <th class="py-0.5 pr-2 text-center">{gettext("Surviving")}</th>
            <th class="py-0.5 pr-2 text-center">{gettext("Days")}</th>
            <th class="py-0.5 pr-2 text-center">{gettext("DestPen")}</th>
            <th class="py-0.5 pr-2 text-center">{gettext("WeanAmt")}</th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={entry <- @rows}
            class="border-b border-black/40 align-top break-inside-avoid"
          >
            <td class="py-1.5 pr-2 font-mono font-semibold">{entry.farrowing.sow.ear_tag}</td>
            <td class="py-1.5 pr-2 font-mono">{pen_label(entry.farrowing.pen)}</td>
            <td class="py-1.5 pr-2 text-center font-mono">{entry.parity}</td>
            <td class="py-1.5 pr-2 font-mono">{entry.farrowing.farrowed_at}</td>
            <td class="py-1.5 pr-2 text-center font-mono">{entry.surviving}</td>
            <td class="py-1.5 pr-2 text-center font-mono">
              {Date.diff(@today, entry.farrowing.farrowed_at)}
            </td>
            <td class="py-1.5 pr-2"></td>
            <td class="py-1.5 pr-2"></td>
          </tr>
          <tr :if={@total == 0}>
            <td colspan="8" class="py-4 text-center">
              {gettext("No lactating sows match the filters.")}
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
      age: Shared.param_age(params["age"]),
      pen_id: params["pen_id"] || "",
      pen_search: params["pen_search"] || "",
      min_parity: params["min_parity"] || "",
      max_parity: params["max_parity"] || ""
    }

    opts = [
      search: filters.q,
      age_bucket: filters.age,
      pen_id: blank_to_nil(filters.pen_id),
      pen_search: blank_to_nil(filters.pen_search),
      min_parity: blank_to_nil(filters.min_parity),
      max_parity: blank_to_nil(filters.max_parity),
      sort: sort_param(params["sort"]),
      dir: dir_param(params["dir"]),
      limit: :all
    ]

    rows =
      Breeding.list_lactating_sows(scope, opts)
      |> Enum.map(fn f ->
        %{farrowing: f, surviving: Breeding.surviving_piglet_count(f)}
      end)
      |> attach_parity(scope)

    {:noreply,
     assign(socket,
       page_title: gettext("Print — Lactating sows"),
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
    sow_ids = Enum.map(rows, & &1.farrowing.sow_id)
    parities = Breeding.parities_for(scope, sow_ids)
    Enum.map(rows, &Map.put(&1, :parity, Map.get(parities, &1.farrowing.sow_id, 0)))
  end

  defp pen_label(%{code: code, house: %{code: hcode}}), do: "#{hcode}-#{code}"
  defp pen_label(%{code: code}), do: code
  defp pen_label(_), do: "—"

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  @sort_columns ~w(tag pen parity farrowed days)
  defp sort_param(s) when s in @sort_columns, do: s
  defp sort_param(_), do: "farrowed"

  defp dir_param("desc"), do: "desc"
  defp dir_param(_), do: "asc"

  defp filter_summary(filters) do
    [
      filters.q != "" && gettext("tag~%{q}", q: filters.q),
      filters.age != "all" && gettext("age=%{a}", a: filters.age),
      filters.pen_search != "" && gettext("pen~%{p}", p: filters.pen_search),
      filters.min_parity != "" && gettext("parity≥%{n}", n: filters.min_parity),
      filters.max_parity != "" && gettext("parity≤%{n}", n: filters.max_parity)
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end
end
