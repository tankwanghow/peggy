# Performance Analysis report — design

Date: 2026-06-01
Status: approved design, pre-implementation

## Goal

Reproduce the Porcitec **Performance Analysis** KPI report inside Peggy: a
matrix of breeding KPIs with **one column per calendar month** across a chosen
date range, plus an **ACUM** (whole-range total) column. This is the first
concrete deliverable of Phase 8 (Reporting & KPIs).

## Scope (V1)

Three of the four Porcitec sections — **Service**, **Farrowing**, **Weaning**.
Each section's rows are bucketed by their own event date (services by
`served_at`, farrowings by `farrowed_at`, weanings by `weaned_at`).

### Non-goals (explicitly deferred)

- **Population section** (ending/avg female inventory, average parity of the
  herd, replacement/culling/mortality rates, NPD, lifetime metrics). These
  require historical herd-inventory reconstruction / NPD modelling — a separate
  later project.
- **Tier-4 metrics with no data source**: heat-not-served / unmated,
  homospermic vs heterospermic, euthanized-vs-death split, transferred-in,
  age-at-first-service when `dob` is missing. Omitted (not shown as fake zeros).

## Architecture

**Fetch-once, bucket-in-Elixir, pure metric functions** — extends the existing
`Peggy.Reports.summary/2` style rather than SQL `GROUP BY`. Rationale: the
Tier-2 derivations (parity-at-farrowing, gestation length, farrowing interval,
1st-vs-repeat classification, wean→service intervals) need per-sow history and
cross-table joins that are painful/untestable in SQL and trivial in Elixir.
Data volume is small (≈5.5k services / 3.4k farrowings / 3.3k weanings per
year).

### Context API

`Peggy.Reports.performance_analysis(scope, %{from: Date.t(), to: Date.t()})`
returns:

```elixir
%{
  periods: [%{label: "01-01-25", from: ~D[2025-01-01], to: ~D[2025-01-31]}, ...],
  sections: [
    %{
      key: :service, title: "Service performance",
      rows: [
        %{key: :total_services, label: "Total services", format: :int,
          values: [500, 393, ...], acum: 5480},
        ...
      ]
    },
    %{key: :farrowing, ...},
    %{key: :weaning, ...}
  ]
}
```

- `periods` are the calendar months intersecting `[from, to]` (a partial first
  or last month is allowed and labelled by its clipped range). ACUM is computed
  over the full `[from, to]`, not by summing month columns (avoids rounding and
  double counting).
- `format` is one of `:int | :dec1 | :pct` and travels with each row so the
  on-screen table, CSV, and print view render identically.
- The builder fetches each source once for the full range with the joins/derived
  fields needed (below), groups rows into buckets, then evaluates each section's
  pure metric functions per bucket (and once for ACUM).

### Data fetched

- **Services**: `served_at, result, result_at, service_type, mounting_count,
  sow_id`. Plus, per sow, the chronological service sequence (to classify
  1st/repeat and conception) and the sow's prior weaning/farrowing dates and
  entry date.
- **Farrowings**: `farrowed_at, born_alive, stillborn, mummified,
  total_birth_weight_g, sow_id`, joined to `service.served_at` (gestation
  length) and the sow's prior farrowing date (farrowing interval). Parity:
  `legacy_parity + 1-based rank of this farrowing among the sow's farrowings by
  date`.
- **Weanings**: `weaned_at, weaned_count, avg_wean_weight_g, farrowing_id`,
  joined to `farrowing.farrowed_at` (lactation length) and `farrowing.born_alive`
  (pre-wean mortality), and the sow's next service within 7 days.
- **Litter events**: `kind, quantity, occurred_at` — `foster_in`/`foster_out`
  (net fostered) and `death` (recorded pre-weaned deaths).
- **Entry date** per sow = earliest `Movement.moved_at` (the `placement`
  movement) for that sow; used for the after-entry rows.

Reuse existing helpers where present: `farrowing_rate/1`, `avg/2`,
`pre_wean_mortality/2`, `avg_wean_to_service_days/3`.

## V1 metric rows and formulas

Counts are integers; intervals/averages are 1-decimal; rates are percentages
(1-decimal). Averages ignore nil contributors. A bucket with no contributing
rows shows `—` (nil), not 0, for averages/rates.

### Service (bucket by `served_at`)

| Row | Formula |
|---|---|
| Total services | count |
| Number 1st services | count where classification = `:first` |
| Number repeat services | count where classification = `:repeat` |
| Percent repeat services | repeat ÷ total × 100 |
| Number multiple matings | count where `mounting_count > 1` |
| Percent multiple matings | ÷ total × 100 |
| Matings per service | Σ`mounting_count` ÷ total |
| Number AI services | count `service_type = "ai"` |
| % AI services | ÷ total × 100 |
| Number natural services | count `service_type = "natural"` |
| % natural services | ÷ total × 100 |
| Served 1st service after weaning | count `:first` whose sow's most-recent prior event is a weaning |
| Weaning–1st service interval | avg(`served_at` − prior `weaned_at`) for those |
| Served 1st service after entry | count `:first` with no prior farrowing/weaning (gilt) |
| Entry to 1st service interval | avg(`served_at` − entry_date) for those |
| Conception rate | closed services with `result != "re_service"` ÷ closed services × 100 |
| Farrowing rate (service cohort) | closed services with `result = "farrowing"` ÷ closed services × 100 |

**1st vs repeat classification (confirmed):** order each sow's services by
`served_at`; a service is `:repeat` iff the sow's immediately prior service was
closed `result = "re_service"` (the sow returned and is being re-served);
otherwise `:first`.

**Conception rate (confirmed):** of *closed* services (result set) in the
bucket, the fraction that did **not** return to heat (`result != "re_service"`).

### Farrowing (bucket by `farrowed_at`)

| Row | Formula |
|---|---|
| Farrowings | count |
| % litters < 7 born alive | count(`born_alive < 7`) ÷ count × 100 |
| Avg parity farrowed | avg(parity_at_farrowing) |
| Total born per farrow | avg(`born_alive + stillborn + mummified`) |
| Liveborn per farrow | avg(`born_alive`) |
| Stillborn per farrow | avg(`stillborn`) |
| % Stillborn | Σstillborn ÷ Σtotal_born × 100 |
| Mummies per farrow | avg(`mummified`) |
| % Mummies | Σmummified ÷ Σtotal_born × 100 |
| Avg gestation length | avg(`farrowed_at` − matched `service.served_at`) |
| Birthweight / liveborn (g) | Σ`total_birth_weight_g` ÷ Σ`born_alive` over farrowings with weight recorded; `—` if none |
| Farrowing interval | avg(`farrowed_at` − sow's prior `farrowed_at`) |
| Abortions | count of services with `result = "abortion"` and `result_at` in bucket |
| Preweaning mortality (cohort) | `pre_wean_mortality/2` over paired farrow→wean, by farrow date |
| Litters / female / year | annualized farrowings ÷ active-sow denominator (see below) |
| Liveborn / female / year | annualized Σborn_alive ÷ active-sow denominator |

### Weaning (bucket by `weaned_at`)

| Row | Formula |
|---|---|
| Litters weaned | count |
| Pigs weaned (total) | Σ`weaned_count` |
| Pigs weaned per litter | avg(`weaned_count`) |
| Pigs weaned per female | Σ`weaned_count` ÷ distinct `sow_id` among weanings |
| Avg lactation length / weaning age | avg(`weaned_at` − `farrowing.farrowed_at`) |
| % weaned bred by 7 days | weanings whose sow is serviced within 7 days of `weaned_at` ÷ count × 100 |
| Net fostered | Σ`foster_in.quantity` − Σ`foster_out.quantity` (litter events by `occurred_at`) |
| Recorded preweaned deaths | Σ`death.quantity` (litter events by `occurred_at`) |
| Avg weight / weaned pig (g) | Σ(`avg_wean_weight_g` × `weaned_count`) ÷ Σ`weaned_count` over weanings with weight; `—` if none |
| Preweaning mortality (period) | `pre_wean_mortality/2`, bucketed by wean date |
| Weaned / female / year | annualized Σweaned_count ÷ active-sow denominator |

### Annualized "/ female / year" denominator (confirmed)

Historical inventory is deferred, so annualized rows use the **same denominator
the existing `pigs_weaned_per_sow_year` uses**: the count of **distinct sows
that had a service or farrowing within the full `[from, to]` range**. The same
range-wide denominator is used for every month column and ACUM, so monthly
annualized rates stay comparable. Annualization factor for a bucket =
`365 / days_in_bucket`. (This is a documented approximation; a true
avg-inventory denominator arrives with the Population phase.)

## Web layer

- **LiveView** `PeggyWeb.FarmLive.Reports.Performance` at
  `/farms/:slug/reports/performance`. Date-range form (`from`/`to`), defaulting
  to the current calendar year (Jan 1 – Dec 31 of `FarmClock.today`'s year).
  Renders the matrix: rows grouped by section header, columns = month labels +
  ACUM, with a sticky left metric-label column. daisyUI `table table-sm`.
  Numeric cells right-aligned, `tabular-nums`; `—` for nil. Linked from the
  existing Reports page.
- **CSV export**: `Reports.performance_analysis_csv/2` renders the same struct
  to CSV (first column = metric label, then one column per month + ACUM; section
  headers as label-only rows). Served via a controller action mirroring the
  existing `services_csv` download.
- **A4 print view**: `PeggyWeb.FarmLive.Reports.PerformancePrint` at
  `/farms/:slug/reports/performance/print`, modelled on
  `breeding/gestating_print.ex` (print CSS, auto-print colocated hook), rendering
  the same matrix.

## Testing strategy (TDD)

1. **Pure metric functions** — unit tests with small hand-built datasets and
   expected values (e.g. classification of a service chain, gestation length,
   parity-at-farrowing, net fostered, conception rate).
2. **Builder** — `performance_analysis/2` over a seeded fixture spanning ≥2
   months: assert period list, a representative value per section per month, and
   that ACUM equals the whole-range computation (not the column sum where
   rounding differs).
3. **LiveView** — render test: page loads for a member, shows the three section
   titles and a known seeded value; date-range change re-renders.
4. **CSV / print** — render/format tests: CSV has the expected header row and a
   known metric row; print view renders the matrix and includes the print hook.

All new/changed code via `mix precommit`.

## Future (out of scope here)

- **Population section** + historical inventory subsystem (ending/avg
  inventory at past month boundaries, average parity, annualized
  replacement/culling/mortality rates).
- **NPD** (non-productive days) and **lifetime** metrics.
- These become a second spec once V1 lands.
