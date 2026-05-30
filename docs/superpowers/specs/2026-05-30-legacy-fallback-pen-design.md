# Legacy fallback pen for CSV import

**Date:** 2026-05-30
**Context:** `Peggy.Imports` — legacy CSV import.

## Problem

Some legacy rows have no resolvable pen, so commit-time validations reject them:

- **Farrowings** require `pen_id` (`Farrowing.changeset`). A farrowing with no
  `pen` column whose sow also has no `current_pen_id` (no `movements.csv`
  history) fails `pen_id can't be blank`.
- **Movements** to a house/pen not present in `locations.csv` or the DB are
  dropped at commit.
- **Sows** with no movement history land permanently pen-less.

These are real holes in legacy data, not importer bugs — the source system
simply didn't record a location for every animal/event.

## Solution

A single operator-supplied **fallback location** that absorbs every "location
unknown" case during import.

### Reserved location

House code `LEGACY`, pen code `LEGACY`, purpose `gestation`. The operator adds
one row to `locations.csv`:

```
house_code,house_purpose,pen_code,capacity,status
LEGACY,gestation,LEGACY,0,active
```

It commits like any other location (locations commit first), is tagged
`created_via` for rollback, and is resolved as `Map.get(pens, "LEGACY-LEGACY")`.
No auto-creation.

### Fallback touch-points (all resolve to the LEGACY pen)

1. **Farrowings** — `do_commit_farrowing` resolves
   `pen_id = row pen → sow.current_pen_id → LEGACY`. Computed in the importer
   and passed explicitly so LEGACY can never override a real `current_pen_id`.
2. **Unknown movements** — `do_commit_movement` re-homes a movement to LEGACY
   when its house/pen isn't found, instead of erroring/skipping.
3. **Pen-less sows** — a reconciliation pass *after* the event timeline sets
   `current_pen_id = LEGACY` for sows **created in this run** (`created_via ==
   via`) that are still pen-less. Pre-existing DB sows are never touched.

### Validation gate (blocking)

If the run includes `sows.csv`, `farrowings.csv`, or `movements.csv` and no
`LEGACY/LEGACY` pen is resolvable (neither in `locations.csv` nor already in the
DB), `parse_and_validate/2` adds **one blocking error** directing the operator
to add the `LEGACY,gestation,LEGACY` row. This replaces today's cryptic
per-row `pen_id can't be blank` with a single upfront, actionable message, and
guarantees the fallback exists before any touch-point needs it.

### Rollback

The LEGACY pen and the placements pointing at it carry `created_via`, so import
rollback removes them via the existing mechanism.

## Components touched

- `imports.ex`
  - constants `@fallback_house_code`/`@fallback_pen_code`, helpers
    `fallback_pen_key/0`, `fallback_pen_id/1`.
  - `parse_and_validate/2` — fallback-present check + blocking error.
  - `do_commit_farrowing/4` — pen resolution chain.
  - `do_commit_movement/3` — fallback re-home.
  - `commit/2` — pen-less-sow reconciliation pass after `commit_events`,
    before `commit_culls`.

No `Breeding`/schema changes.

## Tests

- Farrowing with no pen + pen-less sow → lands in LEGACY.
- A real row pen / `current_pen_id` still wins over LEGACY.
- Unknown movement → re-homed to LEGACY.
- Pen-less sow → `current_pen_id` = LEGACY after commit; pre-existing pen-less
  sow untouched.
- Validation blocks when LEGACY pen absent and event/sow/movement files present.

## Decisions

- Fallback resolved from DB **or** `locations.csv` (re-runs don't need to
  re-list it); the error message still points at `locations.csv`.
- Reconciliation scoped to `created_via == via` so pre-existing sows are left
  alone.
- Gate is blocking, per operator's explicit-control preference.
