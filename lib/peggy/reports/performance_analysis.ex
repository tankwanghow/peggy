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
      services: services, farrowings: farrowings, weanings: weanings,
      abortions: abortions, litter_events: litter_events,
      denom: denom, range_days: days, from: from, to: to,
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
      where: s.farm_id == ^farm_id and is_nil(s.deleted_at) and
               s.served_at >= ^from and s.served_at <= ^to,
      select: %{sow_id: s.sow_id, served_at: s.served_at, result: s.result,
                service_type: s.service_type, mounting_count: s.mounting_count}
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
      left_join: s in "breeding_services", on: s.id == f.service_id,
      where: f.farm_id == ^farm_id and is_nil(f.deleted_at) and
               f.farrowed_at >= ^from and f.farrowed_at <= ^to,
      select: %{sow_id: f.sow_id, farrowed_at: f.farrowed_at, born_alive: f.born_alive,
                stillborn: f.stillborn, mummified: f.mummified,
                total_birth_weight_g: f.total_birth_weight_g, served_at: s.served_at}
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
      join: f in "breeding_farrowings", on: f.id == w.farrowing_id,
      where: w.farm_id == ^farm_id and is_nil(w.deleted_at) and
               w.weaned_at >= ^from and w.weaned_at <= ^to,
      select: %{sow_id: f.sow_id, weaned_at: w.weaned_at, weaned_count: w.weaned_count,
                avg_wean_weight_g: w.avg_wean_weight_g, born_alive: f.born_alive,
                farrowed_at: f.farrowed_at}
    )
    |> Repo.all()
  end

  defp fetch_abortions(farm_id, from, to) do
    from(s in "breeding_services",
      where: s.farm_id == ^farm_id and is_nil(s.deleted_at) and
               s.result == "abortion" and not is_nil(s.result_at) and
               s.result_at >= ^from and s.result_at <= ^to,
      select: %{result_at: s.result_at}
    )
    |> Repo.all()
  end

  defp fetch_litter_events(farm_id, from, to) do
    from(e in "breeding_litter_events",
      where: e.farm_id == ^farm_id and is_nil(e.deleted_at) and
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

      last_wean = prior_by_date(Map.get(weanings_by_sow, s.sow_id, []), s.served_at, & &1.weaned_at)
      last_farrow = prior_by_date(Map.get(farrowings_by_sow, s.sow_id, []), s.served_at, & &1.farrowed_at)
      after_weaning? = classification == :first and not is_nil(last_wean)
      after_entry? = classification == :first and is_nil(last_farrow) and is_nil(last_wean)

      %{
        sow_id: s.sow_id, served_at: s.served_at, result: s.result,
        service_type: s.service_type, mounting_count: s.mounting_count || 1,
        classification: classification,
        after_weaning?: after_weaning?,
        wean_to_service_days: after_weaning? && Date.diff(s.served_at, last_wean.weaned_at),
        after_entry?: after_entry?,
        entry_to_service_days:
          after_entry? && (entries[s.sow_id] && Date.diff(s.served_at, entries[s.sow_id]))
      }
    end)
  end

  defp fetch_weanings_all(sow_ids) do
    from(w in "breeding_weanings",
      join: f in "breeding_farrowings", on: f.id == w.farrowing_id,
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
        sow_id: f.sow_id, farrowed_at: f.farrowed_at, born_alive: f.born_alive,
        stillborn: f.stillborn || 0, mummified: f.mummified || 0,
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
      next_svc = next_by_date(Map.get(services_by_sow, w.sow_id, []), w.weaned_at, & &1.served_at)
      bred_7d? = next_svc && Date.diff(next_svc.served_at, w.weaned_at) in 0..7

      %{
        sow_id: w.sow_id, weaned_at: w.weaned_at, weaned_count: w.weaned_count,
        avg_wean_weight_g: w.avg_wean_weight_g, born_alive: w.born_alive,
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

  # earliest row strictly after `date`
  defp next_by_date(rows, date, getter) do
    rows
    |> Enum.filter(fn r -> Date.compare(getter.(r), date) == :gt end)
    |> Enum.min_by(getter, Date, fn -> nil end)
  end

  defp active_sow_denominator(services, farrowings) do
    ids = Enum.map(services, & &1.sow_id) ++ Enum.map(farrowings, & &1.sow_id)
    ids |> Enum.uniq() |> length()
  end

  # Section builders are added in Tasks 3–5. Temporary stubs so build/2
  # compiles now:
  defp service_section(_ctx, _periods), do: %{key: :service, title: "Service performance", rows: []}
  defp farrowing_section(_ctx, _periods), do: %{key: :farrowing, title: "Farrowing performance", rows: []}
  defp weaning_section(_ctx, _periods), do: %{key: :weaning, title: "Weaning performance", rows: []}
end
