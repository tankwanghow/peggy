---
name: legacy-csv-import
description: Use when working on Peggy's CSV legacy import (Peggy.Imports), debugging import commit failures like "gestation out of range", "served at required", or "cannot service a sow with status ...", or when reconciling sows.csv/services.csv/farrowings.csv/weanings.csv/culls.csv against the breeding context.
---

# Legacy CSV Import (Peggy.Imports)

## Overview

`Peggy.Imports` replays a farm's historical breeding records from CSVs by
calling the *live* `Breeding` context functions. The non-obvious failures all
come from the same root: **live operational guards reject historical data when
the import doesn't reconstruct state in the right order or with the right
tolerances.** Validation (`parse_and_validate/2`) is permissive; the real
rejections happen at **commit time** and surface in the per-file `errors` list.

## The two rules that prevent mass failures

### 1. Seed sows at a serviceable baseline — never their final CSV status

`sows.csv` carries each sow's **final** status (`lactating`/`served`/`dry`).
`check_sow_serviceable` (`breeding.ex`) only allows `active/open/dry/served`,
so replaying a historical service against a sow written as `lactating` fails
with `cannot service a sow with status "..."`.

**Rule:** `commit_sows` seeds every sow `"active"`. The event timeline drives
status forward (service→served, farrowing→lactating, weaning→dry) and
`culls.csv` (processed *after* the timeline) applies the departures. The
final status is **reconstructed, not imposed**.

A `culled` status (or any disposition word) in `sows.csv` is **not** a
reproductive status — `animals.marked_cull` is the orthogonal on-farm flag,
set **only by the live action, never by import**. Disposition belongs in
`culls.csv`. Rather than reject these values, `check_sow_row` **tolerates
them with a warning** (`kind: :legacy_disposition_status`) and `commit_sows`
seeds the sow `"active"` like any other; the actual departure is reconstructed
from the matching `culls.csv` row. The tolerated set lives in
`@legacy_disposition_statuses` (`culled cull sold slaughtered transferred
death dead deceased`). Anything outside both that set and `@valid_statuses`
is still a hard `:bad_status` error (the column-alignment / typo guard). The
warning is a no-op if no `culls.csv` row exists — the status column alone
**never** culls a sow.

### 2. Match tolerance MUST equal validation tolerance

`find_open_service_for_farrowing` matches a farrowing to its open service with a
wide window (`import_gestation_tolerance/1` = `max(farm_tol, 14)` days). But
`record_farrowing` re-validates gestation. If validation uses the **narrow**
farm tolerance (default ±3 days, `@default_gestation_tolerance_days`), it
rejects a service the importer just matched — orphaning it and emitting
`gestation out of range`. Real pig gestation is 110–120 days, routinely outside
±3.

**Rule:** the importer passes `gestation_tolerance: import_gestation_tolerance(scope)`
into both `Breeding.record_farrowing/3,4` and `record_farrowing_with_backfill/3,4`
so matching and validation always agree. Both functions take an optional `opts`
keyword; default is the farm tolerance (live paths unchanged).

## LEGACY fallback pen (required)

Legacy rows often have no resolvable pen. The importer requires an
operator-supplied catch-all pen — house `LEGACY`, pen `LEGACY`, purpose
`gestation` — added as one row to `locations.csv`:

```
house_code,house_purpose,pen_code,capacity,status
LEGACY,gestation,LEGACY,0,active
```

`parse_and_validate/2` **blocks the run** (`kind: :missing_fallback_pen` on the
locations file) if `sows`/`farrowings`/`weanings`/`movements` are present and no
`LEGACY/LEGACY` pen is resolvable from `locations.csv` **or** the DB. At commit
the pen absorbs three orphan cases (all resolve to `fallback_pen_id/1`):

1. **Farrowing pen** — `do_commit_farrowing` resolves `row pen → sow.current_pen_id → LEGACY`. Computed in the importer and passed explicitly so LEGACY never overrides a real `current_pen_id`.
2. **Unknown movement** — `do_commit_movement` re-homes to LEGACY instead of dropping.
3. **Pen-less sows** — `place_penless_sows_in_fallback/3` runs after the timeline, parking sows **created this run** (`created_via == via`) that are still pen-less. Pre-existing sows are never touched.

Consequence for tests: any import test that commits events needs a `LEGACY/LEGACY`
pen (provision it in `setup`); a sows-only run now leaves sows in LEGACY, not
pen-less.

## Pen codes are matched zero-insensitively

Legacy exports zero-pad pen codes inconsistently — `movements.csv` has `AB-01`
while `locations.csv` has `AB-1`. All pen keys funnel through `location_key/2`
(and `combined_pen_key/1` for the farrowings `pen` column), which upcases and
**strips leading zeros on purely-numeric segments** (`"01" → "1"`, `"0" → "0"`,
alphanumeric like `"A1"` untouched). This applies uniformly: the DB pen index,
`locations.csv` rows, movement lookups, the farrowing `pen` column, and the
in-`commit_locations` dedup. Consequence: `AB-1` and `AB-01` are the **same**
pen everywhere — never build a pen key with a bare `String.upcase` again.

## Failure cascade — diagnose farrowings first

A failed farrowing leaves no open farrowing for its weaning, so the weaning
falls to `record_weaning_with_backfill → record_farrowing_with_backfill`, which
needs a `served_at` that `weanings.csv` doesn't have → `served at required`.
**Most "served at required" weaning failures are downstream of farrowing
failures.** Confirm by correlating the two failure files' sow tags before
chasing the weaning path itself.

## Diagnosing a failures CSV

Failure files are `line,reason` where `line` is the **source CSV** line number.
Aggregate reasons first:

```bash
tail -n +2 some_failures.csv | cut -d, -f2- | sort | uniq -c | sort -rn
```

Then map a failure line back to its sow:

```bash
awk -F, 'NR==FNR{if(FNR>1)want[$1]=1;next}{if(FNR>1&&(FNR in want))print $1}' \
  some_failures.csv source.csv | sort -u
```

## Litter-size caps

`Farrowing.born_alive ≤ 25`, `Weaning.weaned_count ≤ 20` (raised from 20/15 for
hyperprolific genetics). Values above are genuine data outliers, not import
bugs. `farrowing.ex` / `weaning.ex` changesets; `litter_caps_test.exs`.

## Commit order (build_event_timeline → commit_events → commit_culls)

Per sow, events are sorted by date then `kind_rank` (movement < service <
farrowing < weaning) so same-day events apply in the right sequence. Culls run
last: each `culls.csv` row records **one departure movement** (`sold`/blank/
generic → `sale`, plus `slaughtered`/`transferred`/`death`), and the movement
closes any still-open gestation service as a side-effect (`death` → service
result `death`, else `removed`). A sow the timeline left `lactating` with
surviving piglets is **auto-weaned** at the cull date first (so the departure
guard passes). Don't reorder without re-checking these guards.

## Common mistakes

- Trusting `sows.csv` status at commit — re-introduces rule #1 failures.
- Widening the *farm's* `gestation_tolerance_days` to fix imports — changes live
  batch entry / serviceable lists. Keep the widening import-scoped (rule #2).
- Treating weaning "served at required" as a weaning bug — it's usually a
  farrowing cascade.
