defmodule Peggy.Reports.PerformanceAnalysis do
  @moduledoc """
  Builds the Porcitec-style Performance Analysis matrix (Service /
  Farrowing / Weaning sections) for a date range, broken into calendar
  months plus an ACUM (whole-range) column. See
  `docs/superpowers/specs/2026-06-01-performance-analysis-report-design.md`.
  """
  import Ecto.Query

  alias Peggy.Accounts.Scope
  alias Peggy.Repo

  @doc "Calendar-month buckets intersecting `[from, to]`, partial months clipped."
  def calendar_months(%Date{} = from, %Date{} = to) do
    from
    |> Date.beginning_of_month()
    |> Stream.iterate(fn d -> d |> Date.end_of_month() |> Date.add(1) end)
    |> Enum.take_while(fn d -> Date.compare(d, to) != :gt end)
    |> Enum.map(fn month_start ->
      p_from = later(month_start, from)
      p_to = earlier(Date.end_of_month(month_start), to)
      %{label: Calendar.strftime(p_from, "%d-%m-%y"), from: p_from, to: p_to}
    end)
  end

  defp later(a, b), do: if(Date.compare(a, b) == :lt, do: b, else: a)
  defp earlier(a, b), do: if(Date.compare(a, b) == :gt, do: b, else: a)

  @doc "Builds the full report struct: `%{periods: [...], sections: [...]}`."
  def build(%Scope{farm: %{id: farm_id}}, %{from: %Date{} = from, to: %Date{} = to}) do
    periods = calendar_months(from, to)

    services = farm_id |> fetch_services(from, to) |> normalize_services()
    farrowings = farm_id |> fetch_farrowings(from, to) |> normalize_farrowings()
    weanings = farm_id |> fetch_weanings(from, to) |> normalize_weanings()
    abortions = fetch_abortions(farm_id, from, to)
    litter_events = fetch_litter_events(farm_id, from, to)
    denom = active_sow_denominator(services, farrowings)
    days = Date.diff(to, from) + 1

    ctx = %{
      services: services,
      farrowings: farrowings,
      weanings: weanings,
      abortions: abortions,
      litter_events: litter_events,
      denom: denom,
      range_days: days,
      from: from,
      to: to,
      farm_id: farm_id
    }

    %{
      periods: periods,
      sections: [
        service_section(ctx, periods),
        farrowing_section(ctx, periods),
        weaning_section(ctx, periods)
      ]
    }
  end

  # ── Fetch (full range; bucketed later in Elixir) ──────────────────

  defp fetch_services(farm_id, from, to) do
    from(s in "breeding_services",
      where:
        s.farm_id == ^farm_id and is_nil(s.deleted_at) and
          s.served_at >= ^from and s.served_at <= ^to,
      select: %{
        sow_id: s.sow_id,
        served_at: s.served_at,
        result: s.result,
        service_type: s.service_type,
        mounting_count: s.mounting_count
      }
    )
    |> Repo.all()
  end

  # All of a sow's services/farrowings/weanings (any date) — needed to
  # classify 1st/repeat and to compute "after weaning / after entry".
  defp fetch_services_all(sow_ids) do
    from(s in "breeding_services",
      where: s.sow_id in ^sow_ids and is_nil(s.deleted_at),
      select: %{sow_id: s.sow_id, served_at: s.served_at, result: s.result},
      order_by: [asc: s.served_at, asc: s.id]
    )
    |> Repo.all()
  end

  defp fetch_farrowings(farm_id, from, to) do
    from(f in "breeding_farrowings",
      left_join: s in "breeding_services",
      on: s.id == f.service_id and is_nil(s.deleted_at),
      where:
        f.farm_id == ^farm_id and is_nil(f.deleted_at) and
          f.farrowed_at >= ^from and f.farrowed_at <= ^to,
      select: %{
        sow_id: f.sow_id,
        farrowed_at: f.farrowed_at,
        born_alive: f.born_alive,
        stillborn: f.stillborn,
        mummified: f.mummified,
        total_birth_weight_g: f.total_birth_weight_g,
        served_at: s.served_at
      }
    )
    |> Repo.all()
  end

  defp fetch_farrowings_all(sow_ids) do
    from(f in "breeding_farrowings",
      where: f.sow_id in ^sow_ids and is_nil(f.deleted_at),
      select: %{sow_id: f.sow_id, farrowed_at: f.farrowed_at},
      order_by: [asc: f.farrowed_at, asc: f.id]
    )
    |> Repo.all()
  end

  defp fetch_weanings(farm_id, from, to) do
    from(w in "breeding_weanings",
      join: f in "breeding_farrowings",
      on: f.id == w.farrowing_id and is_nil(f.deleted_at),
      where:
        w.farm_id == ^farm_id and is_nil(w.deleted_at) and
          w.weaned_at >= ^from and w.weaned_at <= ^to,
      select: %{
        sow_id: f.sow_id,
        weaned_at: w.weaned_at,
        weaned_count: w.weaned_count,
        avg_wean_weight_g: w.avg_wean_weight_g,
        born_alive: f.born_alive,
        farrowed_at: f.farrowed_at
      }
    )
    |> Repo.all()
  end

  defp fetch_abortions(farm_id, from, to) do
    from(s in "breeding_services",
      where:
        s.farm_id == ^farm_id and is_nil(s.deleted_at) and
          s.result == "abortion" and not is_nil(s.result_at) and
          s.result_at >= ^from and s.result_at <= ^to,
      select: %{result_at: s.result_at}
    )
    |> Repo.all()
  end

  defp fetch_litter_events(farm_id, from, to) do
    from(e in "breeding_litter_events",
      where:
        e.farm_id == ^farm_id and is_nil(e.deleted_at) and
          e.occurred_at >= ^from and e.occurred_at <= ^to,
      select: %{kind: e.kind, quantity: e.quantity, occurred_at: e.occurred_at}
    )
    |> Repo.all()
  end

  defp entry_dates(sow_ids) do
    from(m in "movements",
      where: m.animal_id in ^sow_ids and m.reason == "placement",
      group_by: m.animal_id,
      select: {m.animal_id, min(m.moved_at)}
    )
    |> Repo.all()
    |> Map.new()
  end

  # ── Normalization ─────────────────────────────────────────────────

  defp normalize_services([]), do: []

  defp normalize_services(services) do
    sow_ids = services |> Enum.map(& &1.sow_id) |> Enum.uniq()
    history = fetch_services_all(sow_ids) |> Enum.group_by(& &1.sow_id)
    farrowings_by_sow = fetch_farrowings_all(sow_ids) |> Enum.group_by(& &1.sow_id)
    weanings_by_sow = fetch_weanings_all(sow_ids)
    entries = entry_dates(sow_ids)

    Enum.map(services, fn s ->
      seq = Map.get(history, s.sow_id, [])
      prior = prior_by_date(seq, s.served_at, & &1.served_at)
      classification = if prior && prior.result == "re_service", do: :repeat, else: :first

      last_wean =
        prior_by_date(Map.get(weanings_by_sow, s.sow_id, []), s.served_at, & &1.weaned_at)

      last_farrow =
        prior_by_date(Map.get(farrowings_by_sow, s.sow_id, []), s.served_at, & &1.farrowed_at)

      after_weaning? = classification == :first and not is_nil(last_wean)
      after_entry? = classification == :first and is_nil(last_farrow) and is_nil(last_wean)

      %{
        sow_id: s.sow_id,
        served_at: s.served_at,
        result: s.result,
        service_type: s.service_type,
        mounting_count: s.mounting_count || 1,
        classification: classification,
        after_weaning?: after_weaning?,
        wean_to_service_days:
          if(after_weaning?, do: Date.diff(s.served_at, last_wean.weaned_at), else: nil),
        after_entry?: after_entry?,
        entry_to_service_days:
          if(after_entry? and entries[s.sow_id],
            do: Date.diff(s.served_at, entries[s.sow_id]),
            else: nil
          )
      }
    end)
  end

  defp fetch_weanings_all(sow_ids) do
    from(w in "breeding_weanings",
      join: f in "breeding_farrowings",
      on: f.id == w.farrowing_id and is_nil(f.deleted_at),
      where: f.sow_id in ^sow_ids and is_nil(w.deleted_at),
      select: %{sow_id: f.sow_id, weaned_at: w.weaned_at}
    )
    |> Repo.all()
    |> Enum.group_by(& &1.sow_id)
  end

  defp normalize_farrowings([]), do: []

  defp normalize_farrowings(farrowings) do
    sow_ids = farrowings |> Enum.map(& &1.sow_id) |> Enum.uniq()
    legacy = legacy_parity(sow_ids)
    all = fetch_farrowings_all(sow_ids) |> Enum.group_by(& &1.sow_id)

    Enum.map(farrowings, fn f ->
      seq = Map.get(all, f.sow_id, [])
      rank = Enum.count(seq, fn x -> Date.compare(x.farrowed_at, f.farrowed_at) != :gt end)
      prior = prior_by_date(seq, f.farrowed_at, & &1.farrowed_at)

      %{
        sow_id: f.sow_id,
        farrowed_at: f.farrowed_at,
        born_alive: f.born_alive,
        stillborn: f.stillborn || 0,
        mummified: f.mummified || 0,
        total_birth_weight_g: f.total_birth_weight_g,
        parity: Map.get(legacy, f.sow_id, 0) + rank,
        gestation_days: f.served_at && Date.diff(f.farrowed_at, f.served_at),
        interval_days: prior && Date.diff(f.farrowed_at, prior.farrowed_at)
      }
    end)
  end

  defp legacy_parity(sow_ids) do
    from(a in "animals", where: a.id in ^sow_ids, select: {a.id, a.legacy_parity})
    |> Repo.all()
    |> Map.new()
  end

  defp normalize_weanings([]), do: []

  defp normalize_weanings(weanings) do
    sow_ids = weanings |> Enum.map(& &1.sow_id) |> Enum.uniq()
    services_by_sow = fetch_services_all(sow_ids) |> Enum.group_by(& &1.sow_id)

    Enum.map(weanings, fn w ->
      svcs = Map.get(services_by_sow, w.sow_id, [])
      bred_7d? = Enum.any?(svcs, fn s -> Date.diff(s.served_at, w.weaned_at) in 0..7 end)

      %{
        sow_id: w.sow_id,
        weaned_at: w.weaned_at,
        weaned_count: w.weaned_count,
        avg_wean_weight_g: w.avg_wean_weight_g,
        born_alive: w.born_alive,
        lactation_days: w.farrowed_at && Date.diff(w.weaned_at, w.farrowed_at),
        bred_within_7d?: !!bred_7d?
      }
    end)
  end

  # latest row strictly before `date`; `getter` extracts the row's date
  defp prior_by_date(rows, date, getter) do
    rows
    |> Enum.filter(fn r -> Date.compare(getter.(r), date) == :lt end)
    |> Enum.max_by(getter, Date, fn -> nil end)
  end

  defp active_sow_denominator(services, farrowings) do
    ids = Enum.map(services, & &1.sow_id) ++ Enum.map(farrowings, & &1.sow_id)
    ids |> Enum.uniq() |> length()
  end

  # ── Service metric functions (public for unit tests) ──────────────

  def m_total(s), do: length(s)
  def m_count_class(s, class), do: Enum.count(s, &(&1.classification == class))
  def m_pct_repeat(s), do: pct(m_count_class(s, :repeat), length(s))
  def m_multiple_matings(s), do: Enum.count(s, &((&1.mounting_count || 1) > 1))
  def m_pct_multiple(s), do: pct(m_multiple_matings(s), length(s))
  def m_matings_per_service([]), do: nil
  def m_matings_per_service(s), do: Enum.sum(Enum.map(s, &(&1.mounting_count || 1))) / length(s)
  def m_count_type(s, t), do: Enum.count(s, &(&1.service_type == t))
  def m_pct_type(s, t), do: pct(m_count_type(s, t), length(s))

  def m_count_after_weaning(s), do: Enum.count(s, & &1.after_weaning?)
  def m_wean_to_service(s), do: avg_vals(s, &(&1.after_weaning? && &1.wean_to_service_days))
  def m_count_after_entry(s), do: Enum.count(s, & &1.after_entry?)
  def m_entry_to_service(s), do: avg_vals(s, &(&1.after_entry? && &1.entry_to_service_days))

  defp closed(s), do: Enum.filter(s, &(&1.result != nil))

  def m_conception_rate(s) do
    c = closed(s)
    pct(Enum.count(c, &(&1.result != "re_service")), length(c))
  end

  def m_farrowing_rate(s) do
    c = closed(s)
    pct(Enum.count(c, &(&1.result == "farrowing")), length(c))
  end

  # ── shared helpers ────────────────────────────────────────────────

  defp pct(_n, 0), do: nil
  defp pct(n, d), do: n / d * 100

  # avg over rows where `getter` returns a number; falsy/nil are skipped
  defp avg_vals(rows, getter) do
    vals = rows |> Enum.map(getter) |> Enum.filter(&is_number/1)

    case vals do
      [] -> nil
      xs -> Enum.sum(xs) / length(xs)
    end
  end

  defp in_range(rows, date_key, from, to) do
    Enum.filter(rows, fn r ->
      d = Map.fetch!(r, date_key)
      Date.compare(d, from) != :lt and Date.compare(d, to) != :gt
    end)
  end

  # builds one matrix row: applies `fun` to the rows of `source` in each
  # period bucket (filtered by `date_key`) and to the whole range (ACUM)
  defp metric_row(key, label, format, source, date_key, ctx, periods, fun) do
    values = Enum.map(periods, fn p -> fun.(in_range(source, date_key, p.from, p.to)) end)
    acum = fun.(in_range(source, date_key, ctx.from, ctx.to))
    %{key: key, label: label, format: format, values: values, acum: acum}
  end

  # ── Service section ───────────────────────────────────────────────

  defp service_section(ctx, periods) do
    s = ctx.services

    r = fn key, label, fmt, fun ->
      metric_row(key, label, fmt, s, :served_at, ctx, periods, fun)
    end

    rows = [
      r.(:total_services, "Total services", :int, &m_total/1),
      r.(:first_services, "Number 1st services", :int, &m_count_class(&1, :first)),
      r.(:repeat_services, "Number repeat services", :int, &m_count_class(&1, :repeat)),
      r.(:pct_repeat, "Percent repeat services", :pct, &m_pct_repeat/1),
      r.(:multiple_matings, "Number multiple matings", :int, &m_multiple_matings/1),
      r.(:pct_multiple, "Percent multiple matings", :pct, &m_pct_multiple/1),
      r.(:matings_per_service, "Matings per service", :dec1, &m_matings_per_service/1),
      r.(:ai_services, "Number AI services", :int, &m_count_type(&1, "ai")),
      r.(:pct_ai, "% AI services", :pct, &m_pct_type(&1, "ai")),
      r.(:natural_services, "Number natural services", :int, &m_count_type(&1, "natural")),
      r.(:pct_natural, "% natural services", :pct, &m_pct_type(&1, "natural")),
      r.(:after_weaning, "Served 1st service after weaning", :int, &m_count_after_weaning/1),
      r.(:wean_to_service, "Weaning-1st service interval", :dec1, &m_wean_to_service/1),
      r.(:after_entry, "Served 1st service after entry", :int, &m_count_after_entry/1),
      r.(:entry_to_service, "Entry to 1st service interval", :dec1, &m_entry_to_service/1),
      r.(:conception_rate, "Conception rate", :pct, &m_conception_rate/1),
      r.(:farrowing_rate, "Farrowing rate (service cohort)", :pct, &m_farrowing_rate/1)
    ]

    %{key: :service, title: "Service performance", rows: rows}
  end

  # ── Farrowing metric functions ────────────────────────────────────

  def m_count(rows), do: length(rows)
  def m_avg(rows, field), do: avg_vals(rows, &Map.get(&1, field))

  def m_pct_small_litter(fs), do: pct(Enum.count(fs, &(&1.born_alive < 7)), length(fs))
  def m_total_born(f), do: f.born_alive + (f.stillborn || 0) + (f.mummified || 0)
  def m_avg_total_born(fs), do: avg_vals(fs, &m_total_born/1)

  def m_pct_of_total_born(fs, field) do
    total = fs |> Enum.map(&m_total_born/1) |> Enum.sum()
    pct(fs |> Enum.map(&Map.get(&1, field)) |> Enum.sum(), total)
  end

  def m_birthweight_per_liveborn(fs) do
    recorded = Enum.filter(fs, &(&1.total_birth_weight_g != nil))

    case recorded do
      [] ->
        nil

      rs ->
        w = rs |> Enum.map(& &1.total_birth_weight_g) |> Enum.sum()
        a = rs |> Enum.map(& &1.born_alive) |> Enum.sum()
        if a == 0, do: nil, else: w / a
    end
  end

  def m_count_abortions(abortions), do: length(abortions)

  # annualized: (bucket value / period days) * 365 / herd denominator
  def m_per_female_year(value, period_days, denom) do
    if denom in [0, nil] or period_days in [0, nil] or value in [nil],
      do: nil,
      else: value / period_days * 365 / denom
  end

  # pre-wean mortality over rows carrying born_alive + weaned_count
  def m_pre_wean_mortality(rows) do
    pairs = Enum.filter(rows, &(&1[:born_alive] && &1[:weaned_count]))
    born = pairs |> Enum.map(& &1.born_alive) |> Enum.sum()
    weaned = pairs |> Enum.map(& &1.weaned_count) |> Enum.sum()
    pct(born - weaned, born)
  end

  # ── Farrowing section ─────────────────────────────────────────────

  defp farrowing_section(ctx, periods) do
    f = ctx.farrowings

    r = fn key, label, fmt, fun ->
      metric_row(key, label, fmt, f, :farrowed_at, ctx, periods, fun)
    end

    # weanings keyed for cohort pre-wean mortality, attributed to the
    # FARROWING date (cohort), carrying born_alive + weaned_count.
    cohort = pair_cohort(ctx)

    cr = fn key, label, fmt, fun ->
      metric_row(key, label, fmt, cohort, :farrowed_at, ctx, periods, fun)
    end

    ann = fn key, label, source, value_fun ->
      values =
        Enum.map(periods, fn p ->
          v = value_fun.(in_range(source, :farrowed_at, p.from, p.to))
          m_per_female_year(v, Date.diff(p.to, p.from) + 1, ctx.denom)
        end)

      acum = m_per_female_year(value_fun.(source), ctx.range_days, ctx.denom)
      %{key: key, label: label, format: :dec1, values: values, acum: acum}
    end

    rows = [
      r.(:farrowings, "Farrowings", :int, &m_count/1),
      r.(:pct_small_litter, "% litters less than 7 born alive", :pct, &m_pct_small_litter/1),
      r.(:avg_parity, "Avg parity farrowed", :dec1, &m_avg(&1, :parity)),
      r.(:total_born, "Total born per farrow", :dec1, &m_avg_total_born/1),
      r.(:liveborn, "Liveborn per farrow", :dec1, &m_avg(&1, :born_alive)),
      r.(:stillborn, "Stillborn per farrow", :dec1, &m_avg(&1, :stillborn)),
      r.(:pct_stillborn, "% Stillborn", :pct, &m_pct_of_total_born(&1, :stillborn)),
      r.(:mummies, "Mummies per farrow", :dec1, &m_avg(&1, :mummified)),
      r.(:pct_mummies, "% Mummies", :pct, &m_pct_of_total_born(&1, :mummified)),
      r.(:gestation, "Avg gestation length", :dec1, &m_avg(&1, :gestation_days)),
      r.(:birthweight, "Birthweight / liveborn (g)", :dec1, &m_birthweight_per_liveborn/1),
      r.(:interval, "Farrowing interval", :dec1, &m_avg(&1, :interval_days)),
      metric_row(
        :abortions,
        "Abortions",
        :int,
        ctx.abortions,
        :result_at,
        ctx,
        periods,
        &m_count_abortions/1
      ),
      cr.(:pre_wean_cohort, "Preweaning mortality rate (cohort)", :pct, &m_pre_wean_mortality/1),
      ann.(:litters_per_female_year, "Litters / female / year", f, &m_count/1),
      ann.(:liveborn_per_female_year, "Live born / female / year", f, fn rows ->
        Enum.sum(Enum.map(rows, & &1.born_alive))
      end)
    ]

    %{key: :farrowing, title: "Farrowing performance", rows: rows}
  end

  # For each farrowing in range, attach its weaning's weaned_count (if any).
  # Attributed to farrowed_at so the cohort metric buckets by farrow date.
  defp pair_cohort(ctx) do
    %{from: from, to: to} = ctx

    Repo.all(
      from(f in "breeding_farrowings",
        join: w in "breeding_weanings",
        on: w.farrowing_id == f.id and is_nil(w.deleted_at),
        where:
          f.farm_id == ^ctx.farm_id and is_nil(f.deleted_at) and
            f.farrowed_at >= ^from and f.farrowed_at <= ^to,
        select: %{
          farrowed_at: f.farrowed_at,
          born_alive: f.born_alive,
          weaned_count: w.weaned_count
        }
      )
    )
  end

  # ── Weaning metric functions ──────────────────────────────────────

  def m_sum(rows, field),
    do: rows |> Enum.map(&Map.get(&1, field)) |> Enum.reject(&is_nil/1) |> Enum.sum()

  def m_per_female([]), do: nil

  def m_per_female(ws) do
    sows = ws |> Enum.map(& &1.sow_id) |> Enum.uniq() |> length()
    if sows == 0, do: nil, else: m_sum(ws, :weaned_count) / sows
  end

  def m_pct_bred_7d(ws), do: pct(Enum.count(ws, & &1.bred_within_7d?), length(ws))

  def m_avg_wean_weight(ws) do
    recorded = Enum.filter(ws, &(&1.avg_wean_weight_g != nil))
    w = recorded |> Enum.map(&(&1.avg_wean_weight_g * &1.weaned_count)) |> Enum.sum()
    c = recorded |> Enum.map(& &1.weaned_count) |> Enum.sum()
    if c == 0, do: nil, else: w / c
  end

  def m_net_fostered(events) do
    sum = fn k ->
      events |> Enum.filter(&(&1.kind == k)) |> Enum.map(& &1.quantity) |> Enum.sum()
    end

    sum.("foster_in") - sum.("foster_out")
  end

  def m_recorded_deaths(events),
    do: events |> Enum.filter(&(&1.kind == "death")) |> Enum.map(& &1.quantity) |> Enum.sum()

  # ── CSV rendering ─────────────────────────────────────────────────

  @doc "Renders a built report to CSV iodata (metric rows × month columns + ACUM)."
  def to_csv(%{periods: periods, sections: sections}) do
    header = ["Metric" | Enum.map(periods, & &1.label)] ++ ["ACUM"]

    rows =
      Enum.flat_map(sections, fn section ->
        [[section.title]] ++
          Enum.map(section.rows, fn row ->
            [row.label | Enum.map(row.values, &fmt_csv(&1, row.format))] ++
              [fmt_csv(row.acum, row.format)]
          end)
      end)

    [header | rows]
    |> Enum.map(&csv_line/1)
    |> Enum.intersperse("\n")
  end

  defp csv_line(cells), do: cells |> Enum.map(&csv_cell/1) |> Enum.intersperse(",")

  defp csv_cell(s) do
    s = to_string(s)

    if String.contains?(s, [",", "\"", "\n"]),
      do: ~s("#{String.replace(s, "\"", "\"\"")}"),
      else: s
  end

  defp fmt_csv(nil, _), do: ""
  defp fmt_csv(v, :int), do: round(v) |> Integer.to_string()
  defp fmt_csv(v, :dec1), do: :erlang.float_to_binary(v / 1, decimals: 1)
  defp fmt_csv(v, :pct), do: :erlang.float_to_binary(v / 1, decimals: 1)

  # ── Weaning section ───────────────────────────────────────────────

  defp weaning_section(ctx, periods) do
    w = ctx.weanings

    r = fn key, label, fmt, fun ->
      metric_row(key, label, fmt, w, :weaned_at, ctx, periods, fun)
    end

    ev = fn key, label, fmt, fun ->
      metric_row(key, label, fmt, ctx.litter_events, :occurred_at, ctx, periods, fun)
    end

    ann_value = fn source, value_fun ->
      values =
        Enum.map(periods, fn p ->
          v = value_fun.(in_range(source, :weaned_at, p.from, p.to))
          m_per_female_year(v, Date.diff(p.to, p.from) + 1, ctx.denom)
        end)

      acum = m_per_female_year(value_fun.(source), ctx.range_days, ctx.denom)
      %{values: values, acum: acum}
    end

    weaned_year = ann_value.(w, &m_sum(&1, :weaned_count))

    rows = [
      r.(:litters_weaned, "Litters weaned", :int, &m_count/1),
      r.(:pigs_weaned, "Pigs weaned in period", :int, &m_sum(&1, :weaned_count)),
      r.(:per_litter, "Pigs weaned per litter", :dec1, &m_avg(&1, :weaned_count)),
      r.(:per_female, "Pigs weaned per female", :dec1, &m_per_female/1),
      r.(:lactation, "Avg lactation length / weaning age", :dec1, &m_avg(&1, :lactation_days)),
      r.(:bred_7d, "Percent of weaned bred by 7 days", :pct, &m_pct_bred_7d/1),
      ev.(:net_fostered, "Net fostered", :int, &m_net_fostered/1),
      ev.(:recorded_deaths, "Recorded preweaned deaths", :int, &m_recorded_deaths/1),
      r.(:wean_weight, "Avg weight / weaned pig (g)", :dec1, &m_avg_wean_weight/1),
      r.(:pre_wean_period, "Preweaning mortality rate (period)", :pct, &m_pre_wean_mortality/1),
      Map.merge(
        %{key: :weaned_per_female_year, label: "Weaned / female / year", format: :dec1},
        weaned_year
      )
    ]

    %{key: :weaning, title: "Weaning performance", rows: rows}
  end
end
