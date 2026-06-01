# Performance Analysis Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Porcitec-style "Performance Analysis" report (Service / Farrowing / Weaning sections) as a monthly + ACUM matrix, with an on-screen table, CSV download, and A4 print view.

**Architecture:** A pure builder `Peggy.Reports.PerformanceAnalysis.build/2` fetches services/farrowings/weanings/litter-events for the range, normalizes each row into a plain map with derived fields (classification, parity, gestation/lactation/interval days), then computes each metric with small pure functions over the rows whose event-date falls in a calendar-month bucket (ACUM = whole range). A LiveView renders the matrix; a controller action streams CSV; a print LiveView renders an A4 layout.

**Tech Stack:** Elixir, Phoenix LiveView 1.1, Ecto, daisyUI 5, ExUnit.

Spec: `docs/superpowers/specs/2026-06-01-performance-analysis-report-design.md`.

---

## File Structure

- Create `lib/peggy/reports/performance_analysis.ex` — `Peggy.Reports.PerformanceAnalysis`: `build/2`, data fetch + normalization, calendar-month bucketing, all metric functions, and `to_csv/1`.
- Modify `lib/peggy/reports.ex` — add thin delegates `performance_analysis/2` and `performance_analysis_csv/2`.
- Create `lib/peggy_web/live/farm_live/reports/performance.ex` — `PeggyWeb.FarmLive.Reports.Performance` LiveView (date form + matrix + CSV/print links).
- Create `lib/peggy_web/live/farm_live/reports/performance_print.ex` — `PeggyWeb.FarmLive.Reports.PerformancePrint` (A4 print).
- Modify `lib/peggy_web/router.ex` — add the two `live` routes + extend the CSV `get` route type.
- Modify `lib/peggy_web/controllers/reports_controller.ex` — handle `type == "performance"`.
- Modify `lib/peggy_web/live/farm_live/reports.ex` — add a link to the new page.
- Create `test/peggy/reports/performance_analysis_test.exs` — metric/builder tests.
- Create `test/peggy_web/live/farm_live/reports/performance_test.exs` — LiveView/CSV/print tests.

Conventions: every code step is followed by `mix precommit` before commit. Pure metric functions take **plain maps** (no DB) so they unit-test without fixtures.

---

## Task 1: Module scaffold + calendar-month bucketing

**Files:**
- Create: `lib/peggy/reports/performance_analysis.ex`
- Test: `test/peggy/reports/performance_analysis_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule Peggy.Reports.PerformanceAnalysisTest do
  use Peggy.DataCase, async: true

  alias Peggy.Reports.PerformanceAnalysis, as: PA

  describe "calendar_months/2" do
    test "splits a full year into 12 labelled month buckets" do
      months = PA.calendar_months(~D[2025-01-01], ~D[2025-12-31])
      assert length(months) == 12
      assert hd(months) == %{label: "01-01-25", from: ~D[2025-01-01], to: ~D[2025-01-31]}
      assert List.last(months) == %{label: "01-12-25", from: ~D[2025-12-01], to: ~D[2025-12-31]}
    end

    test "clips partial first and last months to the range" do
      months = PA.calendar_months(~D[2025-01-15], ~D[2025-02-10])
      assert months == [
               %{label: "15-01-25", from: ~D[2025-01-15], to: ~D[2025-01-31]},
               %{label: "01-02-25", from: ~D[2025-02-01], to: ~D[2025-02-10]}
             ]
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/peggy/reports/performance_analysis_test.exs`
Expected: FAIL — `PerformanceAnalysis` is undefined.

- [ ] **Step 3: Write minimal implementation**

```elixir
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
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/peggy/reports/performance_analysis_test.exs`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/peggy/reports/performance_analysis.ex test/peggy/reports/performance_analysis_test.exs
git commit -m "Add PerformanceAnalysis module + calendar-month bucketing"
```

---

## Task 2: Fetch + normalize the dataset

Adds the DB fetches and per-sow normalization that all metrics consume. Normalized shapes:

- service: `%{sow_id, served_at, result, service_type, mounting_count, classification, after_weaning?, wean_to_service_days, after_entry?, entry_to_service_days}`
- farrowing: `%{sow_id, farrowed_at, born_alive, stillborn, mummified, total_birth_weight_g, parity, gestation_days, interval_days}`
- weaning: `%{sow_id, weaned_at, weaned_count, avg_wean_weight_g, born_alive, lactation_days, bred_within_7d?}`
- abortion: `%{result_at}` ; litter event: `%{kind, quantity, occurred_at}`

**Files:**
- Modify: `lib/peggy/reports/performance_analysis.ex`
- Test: `test/peggy/reports/performance_analysis_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
  describe "build/2 dataset" do
    setup do
      user = Peggy.AccountsFixtures.user_fixture()
      farm = Peggy.FarmsFixtures.farm_fixture(user)
      scope = Peggy.FarmsFixtures.scope_for(user, farm)
      house = Peggy.LocationsFixtures.house_fixture(scope, code: "H1")
      pen = Peggy.LocationsFixtures.pen_fixture(scope, house, code: "P1", capacity: 50)
      sow = Peggy.AnimalsFixtures.animal_fixture(scope, ear_tag: "S1", stage: "sow", current_pen_id: pen.id)
      %{scope: scope, sow: sow}
    end

    test "normalizes a service into a bucketed row", %{scope: scope, sow: sow} do
      Peggy.BreedingFixtures.service_fixture(scope, sow, served_at: ~D[2025-03-10], service_type: "ai")
      result = PerformanceAnalysis_build(scope)
      svc_total = row_value(result, :service, :total_services)
      assert Enum.at(svc_total.values, 2) == 1   # March column
      assert svc_total.acum == 1
    end
  end

  # helpers used by build tests
  defp PerformanceAnalysis_build(scope),
    do: Peggy.Reports.PerformanceAnalysis.build(scope, %{from: ~D[2025-01-01], to: ~D[2025-12-31]})

  defp row_value(result, section_key, row_key) do
    section = Enum.find(result.sections, &(&1.key == section_key))
    Enum.find(section.rows, &(&1.key == row_key))
  end
```

NOTE: Elixir function names can't start uppercase; rename the helper to `build_year/1`. Use:

```elixir
  defp build_year(scope),
    do: Peggy.Reports.PerformanceAnalysis.build(scope, %{from: ~D[2025-01-01], to: ~D[2025-12-31]})
```

and call `build_year(scope)` in the test.

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/peggy/reports/performance_analysis_test.exs`
Expected: FAIL — `build/2` undefined.

- [ ] **Step 3: Write minimal implementation**

Add to `Peggy.Reports.PerformanceAnalysis`:

```elixir
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
      denom: denom, range_days: days, from: from, to: to
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
  defp service_section(_ctx, periods), do: %{key: :service, title: "Service performance", rows: empty_rows(periods)}
  defp farrowing_section(_ctx, periods), do: %{key: :farrowing, title: "Farrowing performance", rows: empty_rows(periods)}
  defp weaning_section(_ctx, periods), do: %{key: :weaning, title: "Weaning performance", rows: empty_rows(periods)}
  defp empty_rows(_periods), do: []
```

The first build-dataset test asserts a `:total_services` row that the stub doesn't produce yet, so it stays red until Task 3. To keep Task 2 green on its own, replace that test body temporarily with a dataset assertion:

```elixir
    test "build/2 returns periods and three sections", %{scope: scope, sow: sow} do
      Peggy.BreedingFixtures.service_fixture(scope, sow, served_at: ~D[2025-03-10])
      result = build_year(scope)
      assert length(result.periods) == 12
      assert Enum.map(result.sections, & &1.key) == [:service, :farrowing, :weaning]
    end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/peggy/reports/performance_analysis_test.exs`
Expected: PASS (Task 1 tests + the dataset test).

- [ ] **Step 5: Commit**

```bash
git add lib/peggy/reports/performance_analysis.ex test/peggy/reports/performance_analysis_test.exs
git commit -m "PerformanceAnalysis: fetch + normalize services/farrowings/weanings"
```

---

## Task 3: Service section metrics

**Files:**
- Modify: `lib/peggy/reports/performance_analysis.ex`
- Test: `test/peggy/reports/performance_analysis_test.exs`

- [ ] **Step 1: Write the failing test** (pure functions over plain maps + one integration check)

```elixir
  describe "service metrics (pure)" do
    alias Peggy.Reports.PerformanceAnalysis, as: PA

    test "repeat % and matings" do
      svcs = [
        %{result: nil, classification: :first, mounting_count: 1, service_type: "ai"},
        %{result: nil, classification: :repeat, mounting_count: 2, service_type: "ai"},
        %{result: nil, classification: :first, mounting_count: 1, service_type: "natural"}
      ]
      assert PA.m_total(svcs) == 3
      assert PA.m_count_class(svcs, :repeat) == 1
      assert_in_delta PA.m_pct_repeat(svcs), 33.3, 0.1
      assert PA.m_multiple_matings(svcs) == 1
      assert_in_delta PA.m_matings_per_service(svcs), 1.33, 0.01
      assert PA.m_count_type(svcs, "ai") == 2
      assert_in_delta PA.m_pct_type(svcs, "ai"), 66.7, 0.1
    end

    test "conception + farrowing rate over closed services" do
      svcs = [
        %{result: "farrowing"}, %{result: "farrowing"},
        %{result: "re_service"}, %{result: "abortion"}, %{result: nil}
      ]
      # closed = 4 (nil excluded); not-returned = 3 → 75%
      assert_in_delta PA.m_conception_rate(svcs), 75.0, 0.1
      # farrowing = 2 / 4 closed → 50%
      assert_in_delta PA.m_farrowing_rate(svcs), 50.0, 0.1
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/peggy/reports/performance_analysis_test.exs`
Expected: FAIL — `m_total/1` etc. undefined.

- [ ] **Step 3: Write implementation** — add public metric functions + the real `service_section/2`:

```elixir
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
    r = fn key, label, fmt, fun -> metric_row(key, label, fmt, s, :served_at, ctx, periods, fun) end

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
```

Remove the temporary `service_section/2` stub from Task 2.

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/peggy/reports/performance_analysis_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/peggy/reports/performance_analysis.ex test/peggy/reports/performance_analysis_test.exs
git commit -m "PerformanceAnalysis: Service section metrics"
```

---

## Task 4: Farrowing section metrics

**Files:**
- Modify: `lib/peggy/reports/performance_analysis.ex`
- Test: `test/peggy/reports/performance_analysis_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
  describe "farrowing metrics (pure)" do
    alias Peggy.Reports.PerformanceAnalysis, as: PA

    test "litter composition" do
      fs = [
        %{born_alive: 12, stillborn: 1, mummified: 0, total_birth_weight_g: nil, parity: 3, gestation_days: 115, interval_days: 150},
        %{born_alive: 6, stillborn: 3, mummified: 1, total_birth_weight_g: nil, parity: 5, gestation_days: 114, interval_days: 160}
      ]
      assert PA.m_count(fs) == 2
      assert_in_delta PA.m_pct_small_litter(fs), 50.0, 0.1   # one < 7 born alive
      assert_in_delta PA.m_avg(fs, :parity), 4.0, 0.01
      assert_in_delta PA.m_avg_total_born(fs), 11.5, 0.01     # (13 + 10)/2
      assert_in_delta PA.m_avg(fs, :born_alive), 9.0, 0.01
      assert_in_delta PA.m_pct_of_total_born(fs, :stillborn), 17.39, 0.1  # 4/23
      assert_in_delta PA.m_avg(fs, :gestation_days), 114.5, 0.01
    end

    test "birthweight per liveborn only over recorded rows" do
      fs = [
        %{born_alive: 10, total_birth_weight_g: 14_000},
        %{born_alive: 10, total_birth_weight_g: nil}
      ]
      assert PA.m_birthweight_per_liveborn(fs) == 1400.0
      assert PA.m_birthweight_per_liveborn([%{born_alive: 10, total_birth_weight_g: nil}]) == nil
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/peggy/reports/performance_analysis_test.exs`
Expected: FAIL — farrowing metric functions undefined.

- [ ] **Step 3: Write implementation**

```elixir
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
      [] -> nil
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
```

Add the real `farrowing_section/2` (replace the Task 2 stub). The two annualized rows and the cohort pre-wean-mortality need per-period day counts and joined weaning data, so compute them with bespoke closures:

```elixir
  defp farrowing_section(ctx, periods) do
    f = ctx.farrowings
    r = fn key, label, fmt, fun -> metric_row(key, label, fmt, f, :farrowed_at, ctx, periods, fun) end

    # weanings keyed for cohort pre-wean mortality, attributed to the
    # FARROWING date (cohort), carrying born_alive + weaned_count.
    cohort = cohort_rows(ctx)
    cr = fn key, label, fmt, fun -> metric_row(key, label, fmt, cohort, :farrowed_at, ctx, periods, fun) end

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
      metric_row(:abortions, "Abortions", :int, ctx.abortions, :result_at, ctx, periods, &m_count_abortions/1),
      cr.(:pre_wean_cohort, "Preweaning mortality rate (cohort)", :pct, &m_pre_wean_mortality/1),
      ann.(:litters_per_female_year, "Litters / female / year", f, &m_count/1),
      ann.(:liveborn_per_female_year, "Live born / female / year", f, fn rows -> Enum.sum(Enum.map(rows, & &1.born_alive)) end)
    ]

    %{key: :farrowing, title: "Farrowing performance", rows: rows}
  end

  # Farrowings joined to their weaning, attributed to the farrowing date,
  # for cohort pre-wean mortality. Re-query to pair them simply.
  defp cohort_rows(ctx) do
    %{farm: _} = ctx_farm = ctx
    _ = ctx_farm
    farrowed = Map.new(ctx.farrowings, &{{&1.sow_id, &1.farrowed_at}, &1})
    Enum.flat_map(ctx.weanings, fn w ->
      case Map.get(farrowed, {w.sow_id, w.weaned_at}) do
        _ -> []
      end
    end)
    |> case do
      _ -> pair_cohort(ctx)
    end
  end
```

NOTE: the cohort pairing above is intentionally rewritten cleanly in the next step — replace `cohort_rows/1` with this correct version that pairs each in-range farrowing to its weaning via a dedicated query:

```elixir
  # For each farrowing in range, attach its weaning's weaned_count (if any).
  # Attributed to farrowed_at so the cohort metric buckets by farrow date.
  defp pair_cohort(ctx) do
    %{from: from, to: to} = ctx
    Repo.all(
      from(f in "breeding_farrowings",
        join: w in "breeding_weanings", on: w.farrowing_id == f.id and is_nil(w.deleted_at),
        where: f.farm_id == ^ctx_farm_id(ctx) and is_nil(f.deleted_at) and
                 f.farrowed_at >= ^from and f.farrowed_at <= ^to,
        select: %{farrowed_at: f.farrowed_at, born_alive: f.born_alive, weaned_count: w.weaned_count}
      )
    )
  end
```

This needs the farm id in `ctx`. Update `build/2` to put `farm_id` into `ctx` (add `farm_id: farm_id` to the `ctx` map) and define `defp ctx_farm_id(ctx), do: ctx.farm_id`. Delete the broken `cohort_rows/1` body and call `pair_cohort(ctx)` directly in `farrowing_section/2`:

```elixir
    cohort = pair_cohort(ctx)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/peggy/reports/performance_analysis_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/peggy/reports/performance_analysis.ex test/peggy/reports/performance_analysis_test.exs
git commit -m "PerformanceAnalysis: Farrowing section metrics"
```

---

## Task 5: Weaning section metrics

**Files:**
- Modify: `lib/peggy/reports/performance_analysis.ex`
- Test: `test/peggy/reports/performance_analysis_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
  describe "weaning metrics (pure)" do
    alias Peggy.Reports.PerformanceAnalysis, as: PA

    test "weaning aggregates" do
      ws = [
        %{weaned_count: 11, avg_wean_weight_g: 6500, born_alive: 12, lactation_days: 24, bred_within_7d?: true, sow_id: 1},
        %{weaned_count: 9, avg_wean_weight_g: nil, born_alive: 10, lactation_days: 26, bred_within_7d?: false, sow_id: 1}
      ]
      assert PA.m_count(ws) == 2
      assert PA.m_sum(ws, :weaned_count) == 20
      assert_in_delta PA.m_avg(ws, :weaned_count), 10.0, 0.01
      assert_in_delta PA.m_per_female(ws), 20.0, 0.01   # 20 / 1 distinct sow
      assert_in_delta PA.m_avg(ws, :lactation_days), 25.0, 0.01
      assert_in_delta PA.m_pct_bred_7d(ws), 50.0, 0.1
      assert PA.m_avg_wean_weight(ws) == 6500.0          # only recorded row
    end

    test "net fostered and recorded deaths from litter events" do
      events = [
        %{kind: "foster_in", quantity: 5}, %{kind: "foster_out", quantity: 8}, %{kind: "death", quantity: 3}
      ]
      assert PA.m_net_fostered(events) == -3
      assert PA.m_recorded_deaths(events) == 3
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/peggy/reports/performance_analysis_test.exs`
Expected: FAIL — weaning metric functions undefined.

- [ ] **Step 3: Write implementation**

```elixir
  # ── Weaning metric functions ──────────────────────────────────────

  def m_sum(rows, field), do: rows |> Enum.map(&Map.get(&1, field)) |> Enum.reject(&is_nil/1) |> Enum.sum()

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
    sum = fn k -> events |> Enum.filter(&(&1.kind == k)) |> Enum.map(& &1.quantity) |> Enum.sum() end
    sum.("foster_in") - sum.("foster_out")
  end

  def m_recorded_deaths(events),
    do: events |> Enum.filter(&(&1.kind == "death")) |> Enum.map(& &1.quantity) |> Enum.sum()
```

Add the real `weaning_section/2` (replace the Task 2 stub):

```elixir
  defp weaning_section(ctx, periods) do
    w = ctx.weanings
    r = fn key, label, fmt, fun -> metric_row(key, label, fmt, w, :weaned_at, ctx, periods, fun) end
    ev = fn key, label, fmt, fun -> metric_row(key, label, fmt, ctx.litter_events, :occurred_at, ctx, periods, fun) end

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
      Map.merge(%{key: :weaned_per_female_year, label: "Weaned / female / year", format: :dec1}, weaned_year)
    ]

    %{key: :weaning, title: "Weaning performance", rows: rows}
  end
```

Note: `m_pre_wean_mortality/1` over weanings works because each normalized weaning carries `born_alive` and `weaned_count`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/peggy/reports/performance_analysis_test.exs`
Expected: PASS.

- [ ] **Step 5: Add an end-to-end builder test, then commit**

Append this test, run the file, then commit:

```elixir
  test "end-to-end: a March service + farrowing + weaning lands in the right columns", %{scope: scope, sow: sow} do
    f = Peggy.BreedingFixtures.farrowing_fixture(scope, sow, farrowed_at: ~D[2025-03-20], born_alive: 11)
    {:ok, _} = Peggy.Breeding.record_weaning(scope, f, %{weaned_at: ~D[2025-04-14], weaned_count: 10})

    result = build_year(scope)
    farrowings = Enum.find(result.sections, &(&1.key == :farrowing))
    far_count = Enum.find(farrowings.rows, &(&1.key == :farrowings))
    assert Enum.at(far_count.values, 2) == 1   # March
    assert far_count.acum == 1

    weanings = Enum.find(result.sections, &(&1.key == :weaning))
    pigs = Enum.find(weanings.rows, &(&1.key == :pigs_weaned))
    assert Enum.at(pigs.values, 3) == 10       # April
  end
```

Run: `mix test test/peggy/reports/performance_analysis_test.exs`
Expected: PASS.

```bash
git add lib/peggy/reports/performance_analysis.ex test/peggy/reports/performance_analysis_test.exs
git commit -m "PerformanceAnalysis: Weaning section + end-to-end builder test"
```

---

## Task 6: Reports delegates + CSV rendering

**Files:**
- Modify: `lib/peggy/reports/performance_analysis.ex` (add `to_csv/1`)
- Modify: `lib/peggy/reports.ex` (add delegates)
- Modify: `lib/peggy_web/controllers/reports_controller.ex` (handle `"performance"`)
- Modify: `lib/peggy_web/router.ex` (no change needed — `export` route already generic)
- Test: `test/peggy/reports/performance_analysis_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
  describe "to_csv/1" do
    alias Peggy.Reports.PerformanceAnalysis, as: PA

    test "emits a header row, section labels, and metric rows" do
      report = %{
        periods: [%{label: "01-03-25", from: ~D[2025-03-01], to: ~D[2025-03-31]}],
        sections: [
          %{key: :service, title: "Service performance",
            rows: [%{key: :total_services, label: "Total services", format: :int, values: [5], acum: 5}]}
        ]
      }
      csv = PA.to_csv(report) |> IO.iodata_to_binary()
      assert csv =~ "Metric,01-03-25,ACUM"
      assert csv =~ "Service performance"
      assert csv =~ "Total services,5,5"
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/peggy/reports/performance_analysis_test.exs`
Expected: FAIL — `to_csv/1` undefined.

- [ ] **Step 3: Write implementation** — add to `PerformanceAnalysis`:

```elixir
  @doc "Renders a built report to CSV iodata (metric rows × month columns + ACUM)."
  def to_csv(%{periods: periods, sections: sections}) do
    header = ["Metric" | Enum.map(periods, & &1.label)] ++ ["ACUM"]

    rows =
      Enum.flat_map(sections, fn section ->
        [[section.title]] ++
          Enum.map(section.rows, fn row ->
            [row.label | Enum.map(row.values, &fmt_csv(&1, row.format))] ++ [fmt_csv(row.acum, row.format)]
          end)
      end)

    [header | rows]
    |> Enum.map(&csv_line/1)
    |> Enum.intersperse("\n")
  end

  defp csv_line(cells), do: cells |> Enum.map(&csv_cell/1) |> Enum.intersperse(",")

  defp csv_cell(s) do
    s = to_string(s)
    if String.contains?(s, [",", "\"", "\n"]), do: ~s("#{String.replace(s, "\"", "\"\"")}"), else: s
  end

  defp fmt_csv(nil, _), do: ""
  defp fmt_csv(v, :int), do: round(v) |> Integer.to_string()
  defp fmt_csv(v, :dec1), do: :erlang.float_to_binary(v / 1, decimals: 1)
  defp fmt_csv(v, :pct), do: :erlang.float_to_binary(v / 1, decimals: 1)
```

- [ ] **Step 4: Add the context delegates** in `lib/peggy/reports.ex` (place near the other public report functions, e.g. after `summary/2`):

```elixir
  @doc "See `Peggy.Reports.PerformanceAnalysis.build/2`."
  defdelegate performance_analysis(scope, range), to: Peggy.Reports.PerformanceAnalysis, as: :build

  @doc "CSV iodata for the performance-analysis report over `range`."
  def performance_analysis_csv(scope, range) do
    scope |> Peggy.Reports.PerformanceAnalysis.build(range) |> Peggy.Reports.PerformanceAnalysis.to_csv()
  end
```

- [ ] **Step 5: Wire the controller** — in `lib/peggy_web/controllers/reports_controller.ex`:

Change the `@types` module attribute and add a `build_csv` clause:

```elixir
  @types ~w(services farrowings weanings performance)
```

```elixir
  defp build_csv(scope, "performance", range), do: Reports.performance_analysis_csv(scope, range)
```

- [ ] **Step 6: Run tests + full suite**

Run: `mix test test/peggy/reports/performance_analysis_test.exs && mix precommit`
Expected: PASS, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add lib/peggy/reports/performance_analysis.ex lib/peggy/reports.ex lib/peggy_web/controllers/reports_controller.ex test/peggy/reports/performance_analysis_test.exs
git commit -m "PerformanceAnalysis: CSV rendering + Reports delegates + controller"
```

---

## Task 7: Performance LiveView page + route + link

**Files:**
- Create: `lib/peggy_web/live/farm_live/reports/performance.ex`
- Modify: `lib/peggy_web/router.ex`
- Modify: `lib/peggy_web/live/farm_live/reports.ex`
- Test: `test/peggy_web/live/farm_live/reports/performance_test.exs`

- [ ] **Step 1: Add the route** in `lib/peggy_web/router.ex` immediately after the existing inferred route (line ~101):

```elixir
      live "/farms/:farm_slug/reports/performance", FarmLive.Reports.Performance, :index
      live "/farms/:farm_slug/reports/performance/print", FarmLive.Reports.PerformancePrint, :index
```

(The print LiveView module is created in Task 8; adding both routes now is fine — they compile once Task 8 lands. To keep this task self-contained, add only the first route now and the print route in Task 8.)

Add only:

```elixir
      live "/farms/:farm_slug/reports/performance", FarmLive.Reports.Performance, :index
```

- [ ] **Step 2: Write the failing LiveView test**

```elixir
defmodule PeggyWeb.FarmLive.Reports.PerformanceTest do
  use PeggyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Peggy.AccountsFixtures
  import Peggy.FarmsFixtures
  import Peggy.LocationsFixtures
  import Peggy.AnimalsFixtures
  import Peggy.BreedingFixtures

  setup %{conn: conn} do
    owner = user_fixture()
    farm = farm_fixture(owner)
    scope = scope_for(owner, farm)
    house = house_fixture(scope, code: "H1")
    pen = pen_fixture(scope, house, code: "P1", capacity: 50)
    sow = animal_fixture(scope, ear_tag: "S1", stage: "sow", current_pen_id: pen.id)
    farrowing_fixture(scope, sow, farrowed_at: Date.add(Date.utc_today(), -10), born_alive: 11)
    %{conn: log_in_user(conn, owner), farm: farm}
  end

  test "renders the three section titles and a value", %{conn: conn, farm: farm} do
    {:ok, _lv, html} = live(conn, ~p"/farms/#{farm.slug}/reports/performance")
    assert html =~ "Service performance"
    assert html =~ "Farrowing performance"
    assert html =~ "Weaning performance"
    assert html =~ "Total services"
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `mix test test/peggy_web/live/farm_live/reports/performance_test.exs`
Expected: FAIL — module/route not found.

- [ ] **Step 4: Write the LiveView**

```elixir
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
              href={~p"/farms/#{@current_scope.farm.slug}/reports/export?#{[type: "performance", from: @range.from, to: @range.to]}"}
              class="btn btn-sm btn-ghost"
            >
              <.icon name="hero-arrow-down-tray-micro" class="size-3" /> {gettext("CSV")}
            </.link>
            <.link
              navigate={~p"/farms/#{@current_scope.farm.slug}/reports/performance/print?#{[from: @range.from, to: @range.to]}"}
              class="btn btn-sm btn-ghost"
            >
              <.icon name="hero-printer-micro" class="size-3" /> {gettext("Print")}
            </.link>
          </div>
        </div>

        <div class="overflow-x-auto">
          <table class="table table-xs w-full whitespace-nowrap">
            <thead>
              <tr>
                <th class="sticky left-0 bg-base-100 z-10 text-left">{gettext("Metric")}</th>
                <th :for={p <- @report.periods} class="text-right tabular-nums">{p.label}</th>
                <th class="text-right font-bold">{gettext("ACUM")}</th>
              </tr>
            </thead>
            <tbody>
              <%= for section <- @report.sections do %>
                <tr class="bg-base-200">
                  <td class="sticky left-0 bg-base-200 z-10 font-semibold" colspan={length(@report.periods) + 2}>
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
    |> assign(:form, to_form(%{"from" => Date.to_iso8601(range.from), "to" => Date.to_iso8601(range.to)}))
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
```

- [ ] **Step 5: Run the test**

Run: `mix test test/peggy_web/live/farm_live/reports/performance_test.exs`
Expected: PASS.

- [ ] **Step 6: Add a link from the existing Reports page** — in `lib/peggy_web/live/farm_live/reports.ex`, next to the existing "Inferred rows" link (search for `reports/inferred`), add:

```elixir
          <.link
            navigate={~p"/farms/#{@current_scope.farm.slug}/reports/performance"}
            class="btn btn-sm btn-ghost"
          >
            <.icon name="hero-table-cells-micro" class="size-3" /> {gettext("Performance Analysis")}
          </.link>
```

- [ ] **Step 7: Full suite + commit**

Run: `mix precommit`
Expected: 0 failures.

```bash
git add lib/peggy_web/live/farm_live/reports/performance.ex lib/peggy_web/router.ex lib/peggy_web/live/farm_live/reports.ex test/peggy_web/live/farm_live/reports/performance_test.exs
git commit -m "Add Performance Analysis LiveView page, route, and Reports link"
```

---

## Task 8: A4 print view

**Files:**
- Create: `lib/peggy_web/live/farm_live/reports/performance_print.ex`
- Modify: `lib/peggy_web/router.ex`
- Test: `test/peggy_web/live/farm_live/reports/performance_test.exs`

- [ ] **Step 1: Add the route** in `lib/peggy_web/router.ex` after the performance route:

```elixir
      live "/farms/:farm_slug/reports/performance/print", FarmLive.Reports.PerformancePrint, :index
```

- [ ] **Step 2: Write the failing test** (append to `performance_test.exs`)

```elixir
  test "print view renders the matrix and an auto-print hook", %{conn: conn, farm: farm} do
    {:ok, _lv, html} = live(conn, ~p"/farms/#{farm.slug}/reports/performance/print")
    assert html =~ "Performance Analysis"
    assert html =~ "Service performance"
    assert html =~ "AutoPrint"
  end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `mix test test/peggy_web/live/farm_live/reports/performance_test.exs`
Expected: FAIL — print module/route missing.

- [ ] **Step 4: Write the print LiveView** (model on `lib/peggy_web/live/farm_live/breeding/gestating_print.ex`)

```elixir
defmodule PeggyWeb.FarmLive.Reports.PerformancePrint do
  use PeggyWeb, :live_view

  alias Peggy.Reports
  alias PeggyWeb.FarmLive.Reports.Performance

  @impl true
  def render(assigns) do
    ~H"""
    <div id="perf-print" phx-hook=".AutoPrint" class="p-4 text-[10px]">
      <h1 class="text-base font-bold mb-2">{gettext("Performance Analysis")}</h1>
      <p class="mb-3">{@range.from} → {@range.to}</p>
      <table class="w-full border-collapse">
        <thead>
          <tr>
            <th class="text-left border-b">{gettext("Metric")}</th>
            <th :for={p <- @report.periods} class="text-right border-b px-1">{p.label}</th>
            <th class="text-right border-b px-1 font-bold">{gettext("ACUM")}</th>
          </tr>
        </thead>
        <tbody>
          <%= for section <- @report.sections do %>
            <tr>
              <td class="font-semibold pt-2" colspan={length(@report.periods) + 2}>{section.title}</td>
            </tr>
            <tr :for={row <- section.rows}>
              <td>{row.label}</td>
              <td :for={v <- row.values} class="text-right px-1">{Performance.fmt(v, row.format)}</td>
              <td class="text-right px-1 font-semibold">{Performance.fmt(row.acum, row.format)}</td>
            </tr>
          <% end %>
        </tbody>
      </table>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".AutoPrint">
        export default {
          mounted() { window.setTimeout(() => window.print(), 300) }
        }
      </script>
    </div>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    scope = socket.assigns.current_scope
    default = Reports.default_range(scope)
    range = %{
      from: parse_date(params["from"]) || Date.new!(default.to.year, 1, 1),
      to: parse_date(params["to"]) || Date.new!(default.to.year, 12, 31)
    }

    {:ok,
     socket
     |> assign(:range, range)
     |> assign(:report, Reports.performance_analysis(scope, range)), layout: false}
  end

  defp parse_date(nil), do: nil
  defp parse_date(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> d
      _ -> nil
    end
  end
end
```

NOTE: confirm the `layout: false` option and bare-template (no `<Layouts.app>`) match `gestating_print.ex`'s approach; mirror whatever that file does for print chrome.

- [ ] **Step 5: Run the test**

Run: `mix test test/peggy_web/live/farm_live/reports/performance_test.exs`
Expected: PASS.

- [ ] **Step 6: Full suite + commit**

Run: `mix precommit`
Expected: 0 failures.

```bash
git add lib/peggy_web/live/farm_live/reports/performance_print.ex lib/peggy_web/router.ex test/peggy_web/live/farm_live/reports/performance_test.exs
git commit -m "Add Performance Analysis A4 print view"
```

---

## Self-Review

**Spec coverage:**
- Periods (monthly + ACUM, clipped) → Task 1. ✓
- Fetch-once/normalize architecture → Task 2. ✓
- Service rows (17) → Task 3. ✓
- Farrowing rows incl. annualized + cohort pre-wean → Task 4. ✓
- Weaning rows incl. net fostered, recorded deaths, annualized → Task 5. ✓
- `Reports.performance_analysis/2` + CSV + controller → Task 6. ✓
- LiveView page + route + Reports link → Task 7. ✓
- A4 print → Task 8. ✓
- Confirmed definitions (1st/repeat, conception, bred-by-7d, annualized denom) implemented in Tasks 2–5. ✓
- Non-goals (Population/NPD/Tier-4) — correctly absent. ✓

**Placeholder scan:** Task 4's `cohort_rows/1` was shown broken then explicitly replaced by `pair_cohort/1`; the executor must delete the broken version and add `farm_id` to `ctx`. This is called out inline. No other TBDs.

**Type consistency:** Metric functions named `m_*` used consistently. `metric_row/8` signature `(key, label, format, source, date_key, ctx, periods, fun)` used uniformly. `ctx` keys (`services/farrowings/weanings/abortions/litter_events/denom/range_days/from/to/farm_id`) referenced consistently; `farm_id` added to `ctx` in Task 4. Row struct (`key/label/format/values/acum`) consistent across builder, CSV, LiveView, print. `fmt/2` (LiveView) vs `fmt_csv/2` (CSV) distinct on purpose.

**Known executor watch-outs (verify against real APIs during TDD):**
- `record_farrowing/3` sets the matched service's `result` to `"farrowing"` (assumed); confirm so `m_farrowing_rate` counts it.
- `Date.beginning_of_month/1`, `Date.end_of_month/1`, `Enum.max_by/4` with `Date` module + default — confirm arities on the project's Elixir (1.19). If `Enum.max_by(_, _, Date, fn -> nil end)` errors, fall back to sorting and `List.last`.
- Print layout (`layout: false`) must mirror `gestating_print.ex`.
