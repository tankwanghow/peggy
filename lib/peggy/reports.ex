defmodule Peggy.Reports do
  @moduledoc """
  Reporting & KPI queries. Read-only, farm-scoped aggregates over
  `Animals` and `Breeding` data.

  Every public function takes a `Peggy.Accounts.Scope` (for `farm_id`
  isolation) and a `%{from: Date.t(), to: Date.t()}` range. Ranges are
  inclusive of both endpoints.

  Feed/health/sales KPIs (FCR, ADG, withdrawal, revenue) are deferred
  with §5/6/7 of REQUIREMENTS.md and intentionally absent here.
  """

  import Ecto.Query
  alias Peggy.{FarmClock, Repo}
  alias Peggy.Accounts.Scope

  @type range :: %{from: Date.t(), to: Date.t()}
  @type kpi_summary :: %{
          farrowing_rate: float() | nil,
          avg_born_alive: float() | nil,
          avg_stillborn: float() | nil,
          avg_mummified: float() | nil,
          pre_wean_mortality: float() | nil,
          avg_weaned: float() | nil,
          avg_wean_to_service_days: float() | nil,
          pigs_weaned_per_sow_year: float() | nil,
          services_count: non_neg_integer(),
          farrowings_count: non_neg_integer(),
          weanings_count: non_neg_integer()
        }

  @doc """
  Default range: the last 12 months ending today.

  Accepts an optional `Scope` so the farm's simulated date is used when
  set. Without a scope (legacy callers / tests), falls back to the
  system date.
  """
  @spec default_range(Scope.t() | nil) :: range
  def default_range(scope \\ nil) do
    today = FarmClock.today(scope)
    %{from: Date.add(today, -365), to: today}
  end

  # ── Dashboard aggregates ───────────────────────────────────────────

  @doc """
  Herd snapshot: counts of present animals grouped by stage and (for
  sows) by reproductive status, plus pen occupancy stats.

  Pre-wean piglets are NOT animal rows — they live as counts on
  `breeding_farrowings.born_alive` and are surfaced via
  `nursing_piglets` below.
  """
  @spec herd_snapshot(Scope.t()) :: map()
  def herd_snapshot(%Scope{farm: %{id: farm_id}}) do
    stage_rows =
      from(a in "animals",
        where: a.farm_id == ^farm_id and a.status in ~w(active served open lactating dry culled),
        group_by: a.stage,
        select: {a.stage, sum(a.quantity)}
      )
      |> Repo.all()
      |> Map.new()

    sow_status_rows =
      from(a in "animals",
        where:
          a.farm_id == ^farm_id and a.stage == "sow" and
            a.status in ~w(active open served lactating dry),
        group_by: a.status,
        select: {a.status, count(a.id)}
      )
      |> Repo.all()
      |> Map.new()

    nursing_piglets =
      from(f in "breeding_farrowings",
        left_join: w in "breeding_weanings",
        on: w.farrowing_id == f.id and is_nil(w.deleted_at),
        where: f.farm_id == ^farm_id and is_nil(f.deleted_at) and is_nil(w.id),
        select: sum(f.born_alive)
      )
      |> Repo.one()

    present_total = stage_rows |> Map.values() |> Enum.sum()

    %{
      present_total: present_total,
      nursing_piglets: nursing_piglets || 0,
      by_stage: stage_rows,
      sow_status: sow_status_rows,
      pen_stats: pen_stats(farm_id)
    }
  end

  defp pen_stats(farm_id) do
    pen_rows =
      from(p in "pens",
        left_join: a in "animals",
        on:
          a.current_pen_id == p.id and
            a.status in ~w(active served open lactating dry culled),
        where: p.farm_id == ^farm_id and p.status == "active",
        group_by: [p.id, p.capacity],
        select: {p.capacity, sum(coalesce(a.quantity, 0))}
      )
      |> Repo.all()

    total = length(pen_rows)

    {empty, over, used_sum, cap_sum} =
      Enum.reduce(pen_rows, {0, 0, 0, 0}, fn {cap, used}, {e, o, u, c} ->
        used = used || 0
        cap = cap || 0

        {
          if(used == 0, do: e + 1, else: e),
          if(cap > 0 and used > cap, do: o + 1, else: o),
          u + used,
          c + cap
        }
      end)

    %{
      total: total,
      empty: empty,
      overcapacity: over,
      avg_utilization: if(cap_sum > 0, do: used_sum / cap_sum, else: nil)
    }
  end

  @doc """
  Action list — rows the operator should act on this week. All counts
  are farm-scoped. `due_to_farrow` is a small sample list (up to 10)
  so the dashboard can render names; the rest are bare counts.
  """
  @spec action_list(Scope.t()) :: map()
  def action_list(%Scope{farm: %{id: farm_id}} = scope) do
    today = FarmClock.today(scope)
    gestation = Peggy.Breeding.gestation_days(scope)
    farrow_cutoff_7d = Date.add(today, 7 - gestation)
    farrow_cutoff_overdue = Date.add(today, -gestation)

    excluded_sow_statuses = ["culled" | Peggy.Animals.Animal.departed_statuses()]

    due_to_farrow =
      from(s in "breeding_services",
        join: a in "animals",
        on: a.id == s.sow_id,
        where:
          s.farm_id == ^farm_id and is_nil(s.result) and is_nil(s.deleted_at) and
            s.served_at <= ^farrow_cutoff_7d and a.status not in ^excluded_sow_statuses,
        order_by: [asc: s.served_at],
        limit: 10,
        select: %{
          sow_id: s.sow_id,
          sow_tag: a.ear_tag,
          served_at: s.served_at
        }
      )
      |> Repo.all()
      |> Enum.map(fn r ->
        %{
          sow_id: r.sow_id,
          sow_tag: r.sow_tag,
          expected_at: Date.add(r.served_at, gestation),
          overdue?: Date.compare(r.served_at, farrow_cutoff_overdue) != :gt
        }
      end)

    overdue_farrow_count =
      from(s in "breeding_services",
        join: a in "animals",
        on: a.id == s.sow_id,
        where:
          s.farm_id == ^farm_id and is_nil(s.result) and is_nil(s.deleted_at) and
            s.served_at <= ^farrow_cutoff_overdue and a.status not in ^excluded_sow_statuses,
        select: count(s.id)
      )
      |> Repo.one()

    # Lactating farrowings older than 21 days with no weaning yet.
    wean_cutoff = Date.add(today, -21)

    due_to_wean_count =
      from(f in "breeding_farrowings",
        left_join: w in "breeding_weanings",
        on: w.farrowing_id == f.id and is_nil(w.deleted_at),
        where:
          f.farm_id == ^farm_id and is_nil(f.deleted_at) and is_nil(w.id) and
            f.farrowed_at <= ^wean_cutoff,
        select: count(f.id)
      )
      |> Repo.one()

    sow_status_counts =
      from(a in "animals",
        where:
          a.farm_id == ^farm_id and a.stage == "sow" and
            a.status in ~w(active dry open),
        group_by: a.status,
        select: {a.status, count(a.id)}
      )
      |> Repo.all()
      |> Map.new()

    active_sow_count = Map.get(sow_status_counts, "active", 0)
    dry_sow_count = Map.get(sow_status_counts, "dry", 0)
    open_sow_count = Map.get(sow_status_counts, "open", 0)

    needs_review_count =
      from(a in "animals",
        where:
          a.farm_id == ^farm_id and a.needs_review == true and
            a.status in ~w(active served open lactating dry culled),
        select: count(a.id)
      )
      |> Repo.one()

    %{
      due_to_farrow_7d: due_to_farrow,
      overdue_farrow_count: overdue_farrow_count,
      due_to_wean_count: due_to_wean_count,
      active_sow_count: active_sow_count,
      dry_sow_count: dry_sow_count,
      open_sow_count: open_sow_count,
      needs_review_count: needs_review_count,
      recent_kpis: summary(scope, %{from: Date.add(today, -90), to: today})
    }
  end

  @doc """
  Returns every KPI in a single map, computed from one read per
  underlying table. Values are `nil` when the denominator is zero.
  """
  @spec summary(Scope.t(), range) :: kpi_summary
  def summary(%Scope{farm: %{id: farm_id}}, %{from: from, to: to}) do
    services = services_in_range(farm_id, from, to)
    farrowings = farrowings_in_range(farm_id, from, to)
    weanings = weanings_in_range(farm_id, from, to)

    %{
      services_count: length(services),
      farrowings_count: length(farrowings),
      weanings_count: length(weanings),
      farrowing_rate: farrowing_rate(services),
      avg_born_alive: avg(farrowings, & &1.born_alive),
      avg_stillborn: avg(farrowings, & &1.stillborn),
      avg_mummified: avg(farrowings, & &1.mummified),
      avg_weaned: avg(weanings, & &1.weaned_count),
      pre_wean_mortality: pre_wean_mortality(farrowings, weanings),
      avg_wean_to_service_days: avg_wean_to_service_days(farm_id, from, to),
      pigs_weaned_per_sow_year: pigs_weaned_per_sow_year(farm_id, from, to, weanings)
    }
  end

  # ── Raw fetches ────────────────────────────────────────────────────

  defp services_in_range(farm_id, from, to) do
    from(s in "breeding_services",
      where:
        s.farm_id == ^farm_id and is_nil(s.deleted_at) and
          s.served_at >= ^from and s.served_at <= ^to,
      select: %{id: s.id, sow_id: s.sow_id, result: s.result, served_at: s.served_at}
    )
    |> Repo.all()
  end

  defp farrowings_in_range(farm_id, from, to) do
    from(f in "breeding_farrowings",
      where:
        f.farm_id == ^farm_id and is_nil(f.deleted_at) and
          f.farrowed_at >= ^from and f.farrowed_at <= ^to,
      select: %{
        id: f.id,
        sow_id: f.sow_id,
        farrowed_at: f.farrowed_at,
        born_alive: f.born_alive,
        stillborn: f.stillborn,
        mummified: f.mummified
      }
    )
    |> Repo.all()
  end

  defp weanings_in_range(farm_id, from, to) do
    from(w in "breeding_weanings",
      join: f in "breeding_farrowings",
      on: f.id == w.farrowing_id,
      where:
        w.farm_id == ^farm_id and is_nil(w.deleted_at) and
          w.weaned_at >= ^from and w.weaned_at <= ^to,
      select: %{
        id: w.id,
        farrowing_id: w.farrowing_id,
        weaned_at: w.weaned_at,
        weaned_count: w.weaned_count,
        born_alive: f.born_alive,
        sow_id: f.sow_id
      }
    )
    |> Repo.all()
  end

  # ── Derivations ────────────────────────────────────────────────────

  # Closed services only (result is set). A service is counted as a
  # success when result = "farrowing". Open services in the window are
  # excluded from the denominator — they haven't resolved yet.
  defp farrowing_rate(services) do
    closed = Enum.filter(services, &(&1.result != nil))

    case length(closed) do
      0 ->
        nil

      n ->
        succeeded = Enum.count(closed, &(&1.result == "farrowing"))
        succeeded / n
    end
  end

  defp avg([], _fun), do: nil

  defp avg(rows, fun) do
    values = rows |> Enum.map(fun) |> Enum.reject(&is_nil/1)

    case values do
      [] -> nil
      xs -> Enum.sum(xs) / length(xs)
    end
  end

  defp pre_wean_mortality(farrowings, weanings) do
    weaned_by_farrowing = Map.new(weanings, &{&1.farrowing_id, &1.weaned_count})

    paired =
      farrowings
      |> Enum.filter(&Map.has_key?(weaned_by_farrowing, &1.id))
      |> Enum.map(fn f -> {f.born_alive || 0, Map.fetch!(weaned_by_farrowing, f.id)} end)

    case paired do
      [] ->
        nil

      pairs ->
        {born, weaned} =
          Enum.reduce(pairs, {0, 0}, fn {b, w}, {bacc, wacc} -> {bacc + b, wacc + w} end)

        if born == 0, do: nil, else: (born - weaned) / born
    end
  end

  # For each sow with a wean followed by a service in the window, the
  # interval in days. Averaged across all such pairs (not per-sow).
  defp avg_wean_to_service_days(farm_id, from, to) do
    weanings =
      from(w in "breeding_weanings",
        join: f in "breeding_farrowings",
        on: f.id == w.farrowing_id,
        where: w.farm_id == ^farm_id and is_nil(w.deleted_at),
        select: %{sow_id: f.sow_id, weaned_at: w.weaned_at}
      )
      |> Repo.all()

    services =
      from(s in "breeding_services",
        where: s.farm_id == ^farm_id and is_nil(s.deleted_at),
        select: %{sow_id: s.sow_id, served_at: s.served_at}
      )
      |> Repo.all()

    services_by_sow =
      services
      |> Enum.group_by(& &1.sow_id, & &1.served_at)
      |> Map.new(fn {k, dates} -> {k, Enum.sort(dates, Date)} end)

    intervals =
      for w <- weanings,
          dates = Map.get(services_by_sow, w.sow_id, []),
          next = Enum.find(dates, &(Date.compare(&1, w.weaned_at) == :gt)),
          Date.compare(next, from) != :lt and Date.compare(next, to) != :gt do
        Date.diff(next, w.weaned_at)
      end

    case intervals do
      [] -> nil
      xs -> Enum.sum(xs) / length(xs)
    end
  end

  # Annualised: (piglets weaned in range) / (productive sow count)
  # × (365 / range_days). The productive denominator is every sow —
  # present *or* departed — that had at least one service or farrowing
  # inside the window. Using the snapshot of currently-present sows
  # would distort the rate whenever the herd has turned over inside
  # the window (culls + replacements).
  defp pigs_weaned_per_sow_year(farm_id, from, to, weanings) do
    service_sow_ids =
      from(s in "breeding_services",
        where:
          s.farm_id == ^farm_id and is_nil(s.deleted_at) and
            s.served_at >= ^from and s.served_at <= ^to,
        select: s.sow_id,
        distinct: true
      )
      |> Repo.all()

    farrowing_sow_ids =
      from(f in "breeding_farrowings",
        where:
          f.farm_id == ^farm_id and is_nil(f.deleted_at) and
            f.farrowed_at >= ^from and f.farrowed_at <= ^to,
        select: f.sow_id,
        distinct: true
      )
      |> Repo.all()

    sow_count = (service_sow_ids ++ farrowing_sow_ids) |> Enum.uniq() |> length()

    total_weaned = Enum.reduce(weanings, 0, &(&1.weaned_count + &2))
    days = Date.diff(to, from) + 1

    cond do
      sow_count == 0 -> nil
      days <= 0 -> nil
      true -> total_weaned / sow_count * (365 / days)
    end
  end

  # ── Pivot ──────────────────────────────────────────────────────────

  @doc """
  Builds a time-bucketed aggregate over services / farrowings /
  weanings. Returns a list of `%{bucket: Date.t(), value: number()}`
  rows (one per bucket in the range, including zeros for empty
  buckets so chart x-axes are continuous).

  Opts:
    * `:source` — `:services | :farrowings | :weanings` (required)
    * `:metric` — see below (required)
    * `:bucket` — `:week | :month` (default `:month`)
    * `:range` — `%{from: Date.t(), to: Date.t()}` (default last 12mo)

  Supported metrics by source:
    * `:services` → `:count`
    * `:farrowings` → `:count | :sum_born_alive | :sum_stillborn | :sum_mummified`
    * `:weanings` → `:count | :sum_weaned`
  """
  def pivot(%Scope{farm: %{id: farm_id}} = scope, opts) do
    source = Keyword.fetch!(opts, :source)
    metric = Keyword.fetch!(opts, :metric)
    bucket = Keyword.get(opts, :bucket, :month)
    range = Keyword.get(opts, :range) || default_range(scope)

    rows = pivot_query(farm_id, source, metric, bucket, range)
    by_bucket = Map.new(rows, fn {b, v} -> {b, v} end)

    fill_buckets(range, bucket)
    |> Enum.map(fn date -> %{bucket: date, value: Map.get(by_bucket, date, 0)} end)
  end

  # The pivot dispatch is closed over a small set of atoms that are
  # validated in `pivot/2` before reaching here, so it's safe to splice
  # the bucket / column / aggregation strings into raw SQL — no value
  # interpolation, only structural choices. Going via SQL avoids
  # Ecto's restriction against tuples inside dynamic select expressions.
  defp pivot_query(farm_id, source, metric, bucket, %{from: from, to: to}) do
    table = source_table(source)
    date_col = source_date_col(source)
    agg = metric_sql(metric)
    unit = bucket_unit(bucket)

    # Cast the date column to timestamp first so date_trunc returns a
    # TZ-naive timestamp, then cast back to date — keeps the bucket
    # aligned to the calendar day regardless of session timezone.
    sql = """
    SELECT date_trunc('#{unit}', "#{date_col}"::timestamp)::date AS bucket, #{agg}
    FROM "#{table}"
    WHERE farm_id = $1 AND deleted_at IS NULL
      AND "#{date_col}" >= $2 AND "#{date_col}" <= $3
    GROUP BY 1
    """

    %{rows: rows} = Repo.query!(sql, [farm_id, from, to])
    Enum.map(rows, fn [ts, n] -> {to_date(ts), n} end)
  end

  defp source_table(:services), do: "breeding_services"
  defp source_table(:farrowings), do: "breeding_farrowings"
  defp source_table(:weanings), do: "breeding_weanings"

  defp source_date_col(:services), do: "served_at"
  defp source_date_col(:farrowings), do: "farrowed_at"
  defp source_date_col(:weanings), do: "weaned_at"

  defp metric_sql(:count), do: "count(id)"
  defp metric_sql(:sum_born_alive), do: "coalesce(sum(born_alive), 0)"
  defp metric_sql(:sum_stillborn), do: "coalesce(sum(stillborn), 0)"
  defp metric_sql(:sum_mummified), do: "coalesce(sum(mummified), 0)"
  defp metric_sql(:sum_weaned), do: "coalesce(sum(weaned_count), 0)"

  defp bucket_unit(:week), do: "week"
  defp bucket_unit(:month), do: "month"

  defp to_date(%Date{} = d), do: d
  defp to_date(%DateTime{} = dt), do: DateTime.to_date(dt)
  defp to_date(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_date(ndt)
  defp to_date(other), do: other

  # Inclusive list of bucket-start dates covering the range.
  defp fill_buckets(%{from: from, to: to}, :week) do
    start = Date.add(from, -Date.day_of_week(from, :monday) + 1)
    fill(start, to, 7)
  end

  defp fill_buckets(%{from: from, to: to}, :month) do
    start = %{from | day: 1}
    fill_months(start, to, [])
  end

  defp fill(curr, to, step) when step > 0 do
    cond do
      Date.compare(curr, to) == :gt -> []
      true -> [curr | fill(Date.add(curr, step), to, step)]
    end
  end

  defp fill_months(curr, to, acc) do
    cond do
      Date.compare(curr, to) == :gt ->
        Enum.reverse(acc)

      true ->
        next_month_year =
          if curr.month == 12, do: {curr.year + 1, 1}, else: {curr.year, curr.month + 1}

        {y, m} = next_month_year
        next = Date.new!(y, m, 1)
        fill_months(next, to, [curr | acc])
    end
  end

  # ── CSV exports ────────────────────────────────────────────────────

  @doc """
  Exports services in range as CSV (iodata). Includes the sow & boar
  ear tags joined in for analyst-friendly output.
  """
  def services_csv(%Scope{farm: %{id: farm_id}}, %{from: from, to: to}) do
    rows =
      from(s in Peggy.Breeding.Service,
        left_join: sow in assoc(s, :sow),
        left_join: boar in assoc(s, :boar),
        where:
          s.farm_id == ^farm_id and is_nil(s.deleted_at) and
            s.served_at >= ^from and s.served_at <= ^to,
        order_by: [asc: s.served_at, asc: s.id],
        select: %{
          id: s.id,
          sow_tag: sow.ear_tag,
          boar_tag: boar.ear_tag,
          service_type: s.service_type,
          served_at: s.served_at,
          last_serviced_at: s.last_serviced_at,
          mounting_count: s.mounting_count,
          result: s.result,
          result_at: s.result_at,
          notes: s.notes
        }
      )
      |> Repo.all()

    headers = [
      "id",
      "sow_tag",
      "boar_tag",
      "service_type",
      "served_at",
      "last_serviced_at",
      "mounting_count",
      "result",
      "result_at",
      "notes"
    ]

    build_csv(headers, rows, fn r ->
      [
        r.id,
        r.sow_tag,
        r.boar_tag,
        r.service_type,
        r.served_at,
        r.last_serviced_at,
        r.mounting_count,
        r.result,
        r.result_at,
        r.notes
      ]
    end)
  end

  @doc """
  Exports farrowings in range as CSV.
  """
  def farrowings_csv(%Scope{farm: %{id: farm_id}}, %{from: from, to: to}) do
    rows =
      from(f in Peggy.Breeding.Farrowing,
        left_join: sow in assoc(f, :sow),
        where:
          f.farm_id == ^farm_id and is_nil(f.deleted_at) and
            f.farrowed_at >= ^from and f.farrowed_at <= ^to,
        order_by: [asc: f.farrowed_at, asc: f.id],
        select: %{
          id: f.id,
          sow_tag: sow.ear_tag,
          farrowed_at: f.farrowed_at,
          born_alive: f.born_alive,
          stillborn: f.stillborn,
          mummified: f.mummified,
          total_birth_weight_g: f.total_birth_weight_g,
          notes: f.notes
        }
      )
      |> Repo.all()

    headers = [
      "id",
      "sow_tag",
      "farrowed_at",
      "born_alive",
      "stillborn",
      "mummified",
      "total_birth_weight_g",
      "notes"
    ]

    build_csv(headers, rows, fn r ->
      [
        r.id,
        r.sow_tag,
        r.farrowed_at,
        r.born_alive,
        r.stillborn,
        r.mummified,
        r.total_birth_weight_g,
        r.notes
      ]
    end)
  end

  @doc """
  Exports weanings in range as CSV. Joins through the parent farrowing
  so analysts see the sow tag and farrowed_at without a second lookup.
  """
  def weanings_csv(%Scope{farm: %{id: farm_id}}, %{from: from, to: to}) do
    rows =
      from(w in Peggy.Breeding.Weaning,
        join: f in assoc(w, :farrowing),
        left_join: sow in assoc(f, :sow),
        where:
          w.farm_id == ^farm_id and is_nil(w.deleted_at) and
            w.weaned_at >= ^from and w.weaned_at <= ^to,
        order_by: [asc: w.weaned_at, asc: w.id],
        select: %{
          id: w.id,
          sow_tag: sow.ear_tag,
          farrowed_at: f.farrowed_at,
          weaned_at: w.weaned_at,
          born_alive: f.born_alive,
          weaned_count: w.weaned_count,
          avg_wean_weight_g: w.avg_wean_weight_g
        }
      )
      |> Repo.all()

    headers = [
      "id",
      "sow_tag",
      "farrowed_at",
      "weaned_at",
      "born_alive",
      "weaned_count",
      "avg_wean_weight_g",
      "pre_wean_mortality_pct"
    ]

    build_csv(headers, rows, fn r ->
      mortality =
        if r.born_alive in [nil, 0] do
          nil
        else
          Float.round((r.born_alive - r.weaned_count) * 100 / r.born_alive, 1)
        end

      [
        r.id,
        r.sow_tag,
        r.farrowed_at,
        r.weaned_at,
        r.born_alive,
        r.weaned_count,
        r.avg_wean_weight_g,
        mortality
      ]
    end)
  end

  # ── Inferred / backfilled rows audit ──────────────────────────────

  @doc """
  Lists every `inferred=true` service for the farm, with the related
  sow's ear-tag, the served_at date, the resolved result (if any), and
  the `created_via` tag so an operator can trace each row back to its
  import run. Used by the post-import audit page so the ~200 rows that
  the back-fill cascade synthesised can be eyeballed.

  Newest served_at first.
  """
  def list_inferred_services(%Scope{farm: %{id: farm_id}}) do
    from(s in Peggy.Breeding.Service,
      join: a in Peggy.Animals.Animal,
      on: a.id == s.sow_id,
      left_join: f in Peggy.Breeding.Farrowing,
      on: f.service_id == s.id and is_nil(f.deleted_at),
      where: s.farm_id == ^farm_id and s.inferred == true and is_nil(s.deleted_at),
      order_by: [desc: s.served_at, desc: s.id],
      select: %{
        id: s.id,
        sow_id: a.id,
        sow_ear_tag: a.ear_tag,
        served_at: s.served_at,
        service_type: s.service_type,
        result: s.result,
        result_at: s.result_at,
        created_via: s.created_via,
        farrowing_id: f.id,
        farrowed_at: f.farrowed_at
      }
    )
    |> Repo.all()
  end

  @doc """
  Lists sows registered via the inferred/back-fill path — i.e. animals
  the import auto-created when a service or farrowing referenced an
  unknown ear-tag. Filters by `inferred=true` (set by both the import
  pipeline and the back-fill cascade) and excludes departed rows.

  Newest first.
  """
  def list_inferred_sows(%Scope{farm: %{id: farm_id}}) do
    from(a in Peggy.Animals.Animal,
      where:
        a.farm_id == ^farm_id and a.stage == "sow" and a.inferred == true and
          a.status in ~w(active served open lactating dry),
      order_by: [desc: a.inserted_at, desc: a.id],
      select: %{
        id: a.id,
        ear_tag: a.ear_tag,
        status: a.status,
        breed: a.breed,
        dob: a.dob,
        needs_review: a.needs_review,
        created_via: a.created_via,
        inserted_at: a.inserted_at
      }
    )
    |> Repo.all()
  end

  # Tiny CSV builder. Quotes fields containing comma / quote / newline,
  # doubles internal quotes per RFC 4180. Returns iodata.
  defp build_csv(headers, rows, row_fn) do
    [encode_row(headers) | Enum.map(rows, fn row -> encode_row(row_fn.(row)) end)]
  end

  defp encode_row(cells) do
    [cells |> Enum.map(&csv_field/1) |> Enum.intersperse(?,), "\r\n"]
  end

  defp csv_field(nil), do: ""
  defp csv_field(%Date{} = d), do: Date.to_iso8601(d)
  defp csv_field(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp csv_field(v) when is_number(v), do: to_string(v)

  defp csv_field(v) when is_binary(v) do
    if String.contains?(v, [",", "\"", "\n", "\r"]) do
      [?", String.replace(v, "\"", "\"\""), ?"]
    else
      v
    end
  end

  defp csv_field(v), do: csv_field(to_string(v))
end
