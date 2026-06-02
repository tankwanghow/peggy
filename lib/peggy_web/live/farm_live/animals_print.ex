defmodule PeggyWeb.FarmLive.AnimalsPrint do
  @moduledoc """
  Print-friendly view of currently-filtered animals. Mounts with the
  same query params as the Animals tab, loads every matching row (no
  pagination), and auto-opens the browser print preview where the user
  can print to paper or save as PDF.
  """
  use PeggyWeb, :live_view

  alias Peggy.{Animals, Breeding, FarmClock}
  alias Peggy.Animals.Animal

  @batch_stages ~w(weaner grower finisher)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.print flash={@flash} title={gettext("Animals")}>
      <header class="print-mono pb-1">
        <div class="flex items-baseline justify-between gap-4">
          <div>
            <h1 class="text-xl font-semibold">{gettext("Animals")}</h1>
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
          <col style="width: 20%" />
          <col style="width: 20%" />
          <col style="width: 14%" />
          <col style="width: 16%" />
          <col :if={@show_days} style="width: 10%" />
          <col style="width: 20%" />
        </colgroup>
        <thead>
          <tr class="print-thead-spacer" aria-hidden="true">
            <td colspan={if(@show_days, do: 7, else: 6)}></td>
          </tr>
          <tr class="text-center">
            <th class="p-2 border-1">{gettext("Tag / ID")}</th>
            <th class="p-2 border-1">{gettext("Stage")}</th>
            <th class="p-2 border-1">{gettext("Pen")}</th>
            <th class="p-2 border-1">{gettext("Status")}</th>
            <th :if={@show_days} class="p-2 border-1">{gettext("Days")}</th>
            <th class="p-2 border-1">{gettext("Action")}</th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={a <- @rows}
            class="align-top break-inside-avoid font-mono"
          >
            <td class="p-2 border-1 font-semibold">{a.ear_tag || "##{a.id}"}</td>
            <td class="p-2 border-1">
              {String.capitalize(a.stage)}{stage_suffix(a, @parity_map, @avg_wean_age, @today)}
            </td>
            <td class="p-2 border-1">{pen_label(a)}</td>
            <td class="p-2 border-1 text-center">{Animal.status_label(a.status)}</td>
            <td :if={@show_days} class="p-2 border-1 text-center">
              {days_in_status(a, @today)}
            </td>
            <td class="p-2 border-1"></td>
          </tr>
          <tr :if={@total == 0}>
            <td colspan={if(@show_days, do: 7, else: 6)} class="py-4 text-center">
              {gettext("No animals match the filters.")}
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
      stage: blank_to_nil(params["stage"]),
      status: status_param(params["status"]),
      pen_search: blank_to_nil(params["pen_search"]),
      tag_search: blank_to_nil(params["tag_search"]),
      min_age: parse_int(params["min_age"]),
      max_age: parse_int(params["max_age"]),
      min_parity: parse_int(params["min_parity"]),
      max_parity: parse_int(params["max_parity"]),
      needs_review: params["needs_review"] in ["1", "true"]
    }

    opts = [
      stage: filters.stage,
      status: filters.status,
      needs_review: filters.needs_review,
      pen_search: filters.pen_search,
      tag_search: filters.tag_search,
      min_age_days: filters.min_age,
      max_age_days: filters.max_age,
      min_parity: filters.min_parity,
      max_parity: filters.max_parity,
      sort: sort_param(params["sort"]),
      dir: dir_param(params["dir"])
    ]

    rows = Animals.list_animals(scope, opts)
    show_days = Enum.any?(rows, &(&1.stage == "sow"))

    {:noreply,
     assign(socket,
       page_title: gettext("Print — Animals"),
       filters: filters,
       rows: rows,
       total: length(rows),
       today: FarmClock.today(scope),
       generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
       parity_map: parity_map(scope, rows),
       avg_wean_age: Breeding.avg_weaning_age_days(scope),
       show_days: show_days,
       filter_summary: filter_summary(filters)
     )}
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp parity_map(scope, rows) do
    sow_ids =
      rows
      |> Enum.filter(&(&1.stage == "sow" and &1.tracking_type == "individual"))
      |> Enum.map(& &1.id)

    Breeding.parities_for(scope, sow_ids)
  end

  defp stage_suffix(%{stage: "sow", id: id}, parity_map, _avg, _today) do
    case Map.get(parity_map, id) do
      nil -> ""
      n -> "·P#{n}"
    end
  end

  defp stage_suffix(%{stage: stage} = a, _parity, avg_wean_age, today)
       when stage in @batch_stages do
    case batch_age_days(a, avg_wean_age, today) do
      nil -> ""
      d -> "·#{d}d"
    end
  end

  defp stage_suffix(_, _, _, _), do: ""

  defp batch_age_days(%{farrowing: %{weaning: %{weaned_at: weaned_at}}}, avg, today)
       when not is_nil(weaned_at) and is_integer(avg) do
    Date.diff(today, weaned_at) + avg
  end

  defp batch_age_days(%{dob: %Date{} = dob}, _avg, today) do
    Date.diff(today, dob)
  end

  defp batch_age_days(_, _, _), do: nil

  defp pen_label(%{tracking_type: "batch", placements: [_ | _] = placements}) do
    placements
    |> Enum.map_join(" · ", fn p -> "#{p.pen.house.code}-#{p.pen.code}×#{p.quantity}" end)
  end

  defp pen_label(%{current_pen: %{code: code, house: %{code: hcode}}}), do: "#{hcode}-#{code}"
  defp pen_label(%{current_pen: %{code: code}}), do: code
  defp pen_label(_), do: "—"

  defp days_in_status(
         %{stage: "sow", status: status, status_changed_at: %DateTime{} = ts},
         today
       )
       when is_binary(status) do
    if status in Animal.present_statuses() do
      Date.diff(today, DateTime.to_date(ts))
    else
      nil
    end
  end

  defp days_in_status(_, _), do: nil

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  @sort_columns ~w(tag stage pen status days)
  defp sort_param(s) when s in @sort_columns, do: s
  defp sort_param(_), do: "tag"

  defp dir_param("desc"), do: "desc"
  defp dir_param(_), do: "asc"

  defp status_param("present"), do: "present"
  defp status_param("departed"), do: "departed"
  defp status_param(""), do: nil
  defp status_param(nil), do: nil
  defp status_param(v) when is_binary(v), do: if(v in Animal.statuses(), do: v, else: nil)

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} when n >= 0 -> n
      _ -> nil
    end
  end

  defp parse_int(n) when is_integer(n) and n >= 0, do: n
  defp parse_int(_), do: nil

  defp filter_summary(filters) do
    [
      filters.stage && "stage=#{filters.stage}",
      filters.status && "status=#{filters.status}",
      filters.tag_search && "tag~#{filters.tag_search}",
      filters.pen_search && "pen~#{filters.pen_search}",
      filters.min_age && "age≥#{filters.min_age}d",
      filters.max_age && "age≤#{filters.max_age}d",
      filters.min_parity && "parity≥#{filters.min_parity}",
      filters.max_parity && "parity≤#{filters.max_parity}",
      filters.needs_review && "needs_review"
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end
end
