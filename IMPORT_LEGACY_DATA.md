# Importing legacy farm data into Peggy

This guide describes how to prepare CSV files so the **Data Import**
tool (Settings → Data Import, owner-only) can ingest an existing herd
plus its breeding history into a Peggy farm.

The same spec also lets an AI agent or migration script generate the
files programmatically from another farm-management system's export.

---

## Overview

You can import up to seven CSV files in one run:

| File              | Required? | What it loads                                |
|-------------------|-----------|----------------------------------------------|
| `locations.csv`   | optional  | Houses + pens. Skip if pens already exist.   |
| `sows.csv`        | yes       | The breeding herd — sows (and boars).        |
| `services.csv`    | optional  | Mating / AI events.                          |
| `farrowings.csv`  | optional  | Birth events with litter counts.             |
| `weanings.csv`    | optional  | Weaning events.                              |
| `culls.csv`       | optional  | Sows departed (cull / death / sale / etc).   |
| `movements.csv`   | optional  | Per-sow chronological pen history.           |

The files are **dependent on each other**:

- A `services.csv` row references a sow by ear tag — the sow must
  already exist in `sows.csv` *or* in the destination farm's database.
- Same rule for `farrowings.csv` and `weanings.csv`.
- If a sow ear tag in a service / farrowing / weaning row is *unknown*,
  the importer can auto-backfill a sow record from the breeding row
  (and flag it `needs_review`). This is reported as a **warning**, not
  an error — useful for partial migrations.

The importer is a **two-phase** workflow:

1. **Validate** — uploads are parsed and checked. You see a per-file
   report listing OK rows, warnings, and errors. **Errors block
   committing**; warnings don't.
2. **Commit** — only after you click "Commit import". Each file is
   imported in its own transaction; if a row inside a file fails the
   whole file is rolled back, but earlier files keep their results.

Each successfully created row is tagged with
`created_via: "csv_import:<run_id>"` so a future rollback task can
remove the import wholesale.

---

## File 1 — `locations.csv` (optional)

Adds houses and pens to the farm. Skip this file if you already set
up the location structure manually before the import; the importer
will reuse existing pens by code.

The file is **denormalized**: one row per pen, with the parent
house's metadata repeated. The importer deduplicates houses by
`house_code` automatically — you can list the same house on every row
of its pens without creating duplicates.

### Columns

**Required:**

| Column          | Type   | Notes                                                                                  |
|-----------------|--------|----------------------------------------------------------------------------------------|
| `house_code`    | string | The house's identifier within the farm (e.g. `EB`, `HB`, `FA`). Case-insensitive.      |
| `house_purpose` | enum   | `breeding` · `gestation` · `farrowing` · `nursery` · `grower` · `finisher` · `quarantine` · `hospital`. |
| `pen_code`      | string | The pen's identifier within its house (e.g. `01`, `12`, `A1`). Case-insensitive.       |

**Optional:**

| Column      | Type    | Notes                                                                |
|-------------|---------|----------------------------------------------------------------------|
| `capacity`  | integer | Maximum head count the pen can hold. Defaults to `0` (uncapped).     |
| `status`    | enum    | `active` (default) · `quarantine` · `cleaning` · `retired`.          |
| `notes`     | string  | Free text.                                                           |

### Validation

**Errors** (block import):
- Missing required column or blank value.
- `house_purpose` not in the allowed enum.
- `status` not in the allowed enum.
- Negative `capacity`.
- Duplicate `(house_code, pen_code)` pair within the file (case-insensitive).

**Warnings**: none — pens are either valid or not.

### Why no auto-create from `sows.csv`?

If `sows.csv` references `EB-12` and the pen doesn't exist, the
importer leaves the sow without a pen and surfaces a warning rather
than fabricating the pen. A typo (`EB-122` instead of `EB-12`) would
otherwise silently create a phantom pen with no metadata. Use this
file to declare every pen up front; warnings on `sows.csv` then
genuinely indicate missing pens or typos.

### Example

```csv
house_code,house_purpose,pen_code,capacity,status
EB,gestation,01,18,active
EB,gestation,02,18,active
EB,gestation,12,18,active
FA,farrowing,01,1,active
FA,farrowing,02,1,active
DA,nursery,A1,40,active
DA,nursery,A2,40,active
HB,grower,1,80,active
```

---

## File 2 — `sows.csv`

Adds breeding-herd animals (sows and boars) to the farm.

### Columns

**Required:**

| Column     | Type    | Notes                                |
|------------|---------|--------------------------------------|
| `ear_tag`  | string  | Unique within the file *and* per the destination farm. |

**Optional:**

| Column          | Type    | Notes                                                      |
|-----------------|---------|------------------------------------------------------------|
| `breed`         | string  | Free text, e.g. "Landrace", "Yorkshire".                   |
| `dob`           | date    | `YYYY-MM-DD`. The animal's date of birth.                  |
| `status`        | enum    | `active` (default) · `open` · `served` · `lactating` · `dry` · `culled`. |
| `sire_tag`      | string  | Ear tag of the sire (must exist in DB or in this file).    |
| `dam_tag`       | string  | Ear tag of the dam.                                        |
| `legacy_parity` | integer | Parity prior to Peggy (≥ 0). Adds to in-system farrowing count when computing displayed parity. |
| `rfid`          | string  | RFID tag, if any.                                          |
| `notes`         | string  | Free text, kept on the animal.                             |

### Validation

**Errors** (block import):
- Missing `ear_tag` column.
- Blank `ear_tag` value.
- Duplicate `ear_tag` in the file.
- Bad `dob` format (must be `YYYY-MM-DD`).
- Unknown `status` value.
- Negative or non-integer `legacy_parity`.

The sow's pen is **not** set from `sows.csv` — every imported sow
starts pen-less. If `movements.csv` is uploaded in the same run, its
last per-sow row sets `current_pen_id`. Otherwise pens are assigned
through the regular UI.

### Stage assignment

The importer registers every row as `stage = "sow"` and
`tracking_type = "individual"`. Boars and batch animals (weaners /
growers / finishers) need to be created through the regular UI for
now — they have different lifecycle assumptions.

### Example

```csv
ear_tag,breed,dob,status,legacy_parity,notes
SOW1001,Landrace,2024-03-15,active,0,
SOW1002,Landrace,2023-08-01,served,4,Returned from culling pool
SOW1003,Yorkshire,2024-05-20,open,2,
SOW1004,Yorkshire,2022-11-10,lactating,6,
```

---

## File 3 — `services.csv`

Records services (matings / AIs).

### Columns

**Required:**

| Column          | Type    | Notes                                                 |
|-----------------|---------|-------------------------------------------------------|
| `sow_ear_tag`   | string  | Must exist in `sows.csv` or in the DB.                |
| `served_at`     | date    | `YYYY-MM-DD`.                                          |
| `service_type`  | enum    | `ai` · `natural`.                                     |

**Optional:**

| Column         | Type    | Notes                                                                   |
|----------------|---------|-------------------------------------------------------------------------|
| `boar_ear_tag` | string  | Required by farm policy when `service_type=natural`. If the boar tag isn't found, the service is stored with no boar (warning). |
| `result`       | enum    | `farrowing` · `abortion` · `re_service` · `death` · `cull`. Leave blank for an open service. **`farrowing` and `re_service` are treated as hints and dropped** — see "Outcome inference" below. |
| `result_at`    | date    | Date the result was recorded. Falls back to `served_at` when blank or earlier than `served_at`. |
| `notes`        | string  | Free text.                                                              |

### Validation

**Errors:**
- Blank `sow_ear_tag`, `served_at`, or `service_type`.
- Bad date format on `served_at` / `result_at`.
- Unknown enum value on `service_type` or `result`.

**Warnings:**
- `sow_ear_tag` not in `sows.csv` and not in the DB → the importer
  will auto-backfill a sow record (status `active`, no DOB, flagged
  `needs_review`) so the service has a parent. You can edit the sow
  later. Useful for "I just have services data, not the herd list."

### Outcome inference (services, farrowings, weanings)

The importer commits services / farrowings / weanings as a single
**per-sow chronological timeline** so the natural chain of events
closes itself:

- A **farrowings.csv** row whose sow has an open service in the
  gestation window (`served_at + 114 ± 3 days`) attaches to that
  service and closes it with `result = "farrowing"`.
- The **next service** for a sow with a still-open prior service
  closes the prior as `re_service` (or — within 7 days of the prior —
  collapses into it, bumping `mounting_count` and `last_serviced_at`).
  This matches the biological reality of one heat = one service event.
- A **weanings.csv** row attaches to the sow's most recent open
  farrowing.

Because of that, two `result` values in services.csv are redundant
and **dropped on import** as hints:

- `result = farrowing` — the matching farrowings.csv row will close
  the service with the correct `result_at = farrowed_at`. Setting it
  in services.csv would otherwise insert a pre-closed row that the
  farrowings.csv row can't attach to (causing a duplicate service).
- `result = re_service` — the next service in the timeline auto-closes
  the prior with the correct `result_at = next_served_at`.

The remaining outcomes — `abortion`, `death`, `cull` — aren't
inferable from the chain, so they **are** honored: the row is inserted
pre-closed with `result` and `result_at` as given. Legacy data with
`result_at` blank or earlier than `served_at` (a common quirk in
exports from older systems) silently falls back to `served_at`.

### Re-service collapse

If two services for the same sow land within 7 days of each other,
the importer **collapses** them into a single service row with an
incremented `mounting_count` and `last_serviced_at`. This matches the
biological reality of a sow naturally bred multiple times during one
heat cycle. Order rows by `served_at` ascending if you want
deterministic collapse behaviour.

### Example

```csv
sow_ear_tag,served_at,service_type,boar_ear_tag,result,result_at,notes
SOW1001,2026-01-10,ai,,farrowing,2026-05-04,
SOW1002,2026-02-14,natural,BOAR201,,,
SOW1003,2026-03-01,ai,,abortion,2026-04-10,
SOW1004,2026-01-15,ai,,,,
```

---

## File 4 — `farrowings.csv`

Records farrowing events.

### Columns

**Required:**

| Column         | Type    | Notes                                                                  |
|----------------|---------|------------------------------------------------------------------------|
| `sow_ear_tag`  | string  | Must exist in `sows.csv` or in the DB.                                 |
| `farrowed_at`  | date    | `YYYY-MM-DD`.                                                           |
| `born_alive`   | integer | ≥ 0. Live piglets at birth.                                             |

**Optional:**

| Column                 | Type    | Notes                                                          |
|------------------------|---------|----------------------------------------------------------------|
| `stillborn`            | integer | ≥ 0. Defaults to 0.                                            |
| `mummified`            | integer | ≥ 0. Defaults to 0.                                            |
| `total_birth_weight_g` | integer | Total birth weight of the litter in grams.                     |
| `pen`                  | string  | `HOUSE-PEN`. Where the sow farrowed. If omitted, the sow's `current_pen` from `sows.csv` (or the DB) is used. |
| `notes`                | string  | Free text.                                                     |

### Validation

**Errors:**
- Blank `sow_ear_tag`, `farrowed_at`, or `born_alive`.
- Negative integers in count fields.
- Bad `farrowed_at` date format.

**Warnings:**
- `sow_ear_tag` not in `sows.csv` or DB → sow auto-registered (as
  with services).
- A farrowing with no service in the gestation window will trigger
  `record_farrowing_with_backfill`, which silently inserts an inferred
  AI service dated `farrowed_at - 114 days` so the breeding chain is
  intact. The synthetic service is flagged `inferred = true`.

### Example

```csv
sow_ear_tag,farrowed_at,born_alive,stillborn,mummified,total_birth_weight_g,notes
SOW1001,2026-05-04,12,1,0,16800,
SOW1004,2026-04-19,10,2,1,14200,Hand-fed two runts
SOW1002,2026-06-10,11,0,0,15400,
```

---

## File 5 — `weanings.csv`

Records weaning events.

### Columns

**Required:**

| Column         | Type    | Notes                                                                            |
|----------------|---------|----------------------------------------------------------------------------------|
| `sow_ear_tag`  | string  | Must exist; the importer matches the sow's most recent open farrowing.           |
| `weaned_at`    | date    | `YYYY-MM-DD`.                                                                     |
| `weaned_count` | integer | ≥ 0. Number of piglets actually weaned.                                          |

**Optional:**

| Column              | Type    | Notes                                                                   |
|---------------------|---------|-------------------------------------------------------------------------|
| `avg_wean_weight_g` | integer | Average weaner weight at weaning, in grams.                             |
| `batch_tag`         | string  | Free-text id for the resulting weaner batch. Reusing the same `batch_tag` pools multiple weanings into one batch animal. Defaults to `W<weaned_at>` if omitted (e.g. `W2026-05-25`). |
| `notes`             | string  | Free text.                                                              |

The sow's post-wean pen is **not** set from `weanings.csv` — record
the transfer in `movements.csv` (the next-dated movement after
`weaned_at`) instead.

### Validation

**Errors:**
- Blank required fields.
- Bad `weaned_at` format.
- Negative or non-integer `weaned_count`.

**Warnings:**
- Sow not in `sows.csv` or DB.
- `weaned_count > born_alive` of the parent farrowing — possible if
  fostered piglets are weaned with the receiving sow. Allowed but
  surfaced for review.

### Example

```csv
sow_ear_tag,weaned_at,weaned_count,avg_wean_weight_g,batch_tag
SOW1001,2026-05-25,11,7300,W2026-05-25
SOW1004,2026-05-15,9,6800,W2026-05-15
```

---

## File 6 — `culls.csv` (optional)

Records sows no longer in the herd — culled, dead, sold, slaughtered,
or transferred. Processed **after** the event timeline, so it closes
any service that the chain left open.

### Columns

**Required:**

| Column        | Type   | Notes                                                  |
|---------------|--------|--------------------------------------------------------|
| `ear_tag`     | string | Must exist in `sows.csv` or in the DB.                 |
| `culled_at`   | date   | `YYYY-MM-DD`. Date the sow left the herd.              |

**Optional:**

| Column   | Type    | Notes                                                                      |
|----------|---------|----------------------------------------------------------------------------|
| `reason` | enum    | `cull` (default) · `slaughtered` · `sold` · `transferred` · `death`.       |
| `notes`  | string  | Free text.                                                                 |

### What it does at commit

For each row the importer:

1. Looks up the sow.
2. **Closes the sow's most recent open service** (if any) with:
   - `result = "death"` when `reason = death`,
   - `result = "cull"` for every other reason,
   - `result_at = culled_at` (or `served_at` if `culled_at < served_at`).
3. **Sets the sow's status** to the matching final state:
   - `cull` → `culled`
   - `slaughtered` → `slaughtered`
   - `sold` → `sold`
   - `transferred` → `transferred`
   - `death` → `deceased`
4. Audits the change as `animal.removed`.

This is what fixes the "open services that should be closed" issue
for legacy data: services left dangling because the sow has since
been removed are closed by the cull row.

### Validation

**Errors:**
- Blank `ear_tag` or `culled_at`.
- Bad `culled_at` format.
- Unknown `reason` value.
- Duplicate `ear_tag` within `culls.csv`.

**Warnings:**
- Sow not in `sows.csv` or DB → cull skipped at commit (row counts as
  failed in the outcome).

### Example

```csv
ear_tag,culled_at,reason,notes
SOW1001,2026-06-12,sold,
SOW1004,2026-04-18,death,respiratory illness
SOW1010,2026-05-05,slaughtered,
```

---

## File 7 — `movements.csv` (optional)

Records the per-sow pen-change history extracted from the legacy
system, **and is the only way to set each sow's pen** (sows.csv no
longer carries a pen field). Each row is one move: ear tag, the date
it happened, and the destination `(house_code, pen_code)`. The
importer chains them chronologically per sow so each row's
`from_pen_id` is the previous row's `to_pen_id` (and the first row
gets `from_pen_id = nil`). After all of a sow's rows are inserted,
the **last** row's `to_pen_id` is written back to her
`current_pen_id`.

If you skip `movements.csv` entirely, sows are imported without a
pen and you assign them through the Locations UI.

### Columns

**Required:**

| Column        | Type   | Notes                                                          |
|---------------|--------|----------------------------------------------------------------|
| `ear_tag`     | string | Must exist in `sows.csv` or in the DB.                         |
| `moved_at`    | date   | `YYYY-MM-DD`. The date the sow arrived at this pen.            |
| `house_code`  | string | Destination house. Case-insensitive.                           |
| `pen_code`    | string | Destination pen. Case-insensitive.                             |

**Optional:**

| Column   | Type    | Notes        |
|----------|---------|--------------|
| `notes`  | string  | Free text.   |

### Validation

**Errors:**
- Blank `ear_tag`, `moved_at`, `house_code`, or `pen_code`.
- Bad `moved_at` format.

**Warnings:**
- `ear_tag` not in `sows.csv` or DB → all of that sow's movement rows
  are skipped at commit (no auto-backfill — a movement is meaningless
  without an animal).
- `(house_code, pen_code)` not found among existing pens or
  `locations.csv` → that single row is skipped at commit. Tip: if
  you're importing legacy movements, regenerate `locations.csv`
  first so every pen referenced by a movement exists.

### What it does at commit

For each sow, rows are grouped, sorted by `moved_at` ascending, then
inserted as `Movement` records:

- Row 1 → `reason = "placement"`, `from_pen_id = nil`,
  `to_pen_id = <looked-up pen>`, `quantity = 1`.
- Row 2..N → `reason = "pen_transfer"`,
  `from_pen_id = <prev row's to_pen_id>`,
  `to_pen_id = <looked-up pen>`.

After processing all rows for a sow, `Animal.current_pen_id` is set
to the last successful row's `to_pen_id`. The sow's `status` is not
touched here — that's set by `sows.csv` (and adjusted by `culls.csv`
for departed sows).

### Example

```csv
ear_tag,moved_at,house_code,pen_code,notes
SOW1001,2024-02-09,1U,69,arrival
SOW1001,2024-05-22,DB,37,
SOW1001,2024-06-24,4I,47,after farrow
SOW1001,2024-07-11,2U,31,
SOW1001,2024-10-04,HA,41,re-bred
```

---

## How the files relate

```
locations.csv      ─▶  creates houses + pens
                       │
sows.csv           ─▶  creates animals (no pen — assigned by movements)
                       │
services.csv       ─▶  attached to a sow by ear_tag
                       │
farrowings.csv     ─▶  closes the matching open service (within 114±3d)
                       │
weanings.csv       ─▶  closes the matching open farrowing (≥ ~21d old)
                       │
culls.csv          ─▶  closes any leftover open service + departs the sow
                       │
movements.csv      ─▶  per-sow pen history; last row sets current_pen_id
                       │
                       ▼
              breeding KPIs + downstream lifecycle
```

If any link is missing, the importer's `with_backfill` cascade fills
in the gap with an inferred record so the chain stays intact. Inferred
rows are flagged `needs_review` so you can audit them later via the
animal's Trace page.

---

## General CSV rules

- **Encoding**: UTF-8.
- **Line endings**: `\n` or `\r\n` both fine.
- **Headers**: case-insensitive, leading/trailing whitespace ignored
  (so `Ear_Tag`, `ear_tag `, ` ear_tag` all work).
- **Empty cells**: treated as `nil` (omitted). Don't put `null` /
  `none` / `na` — those are taken as literal strings.
- **Quoting**: use double quotes around any cell containing a comma,
  newline, or quote. Inside a quoted cell, escape a literal `"` as
  `""` (RFC 4180).
- **Date format**: ISO 8601 only — `YYYY-MM-DD`. Other formats are
  errors.
- **Limits**: max 100,000 rows per file in one import run. Split into
  multiple runs for larger histories.

---

## Validation report

After upload you'll see something like:

```
sows.csv         42 rows  ✅ 38 ok   ⚠ 3 warnings   ✗ 1 error
   row 11  ✗ ear_tag is required
   row 23  ⚠ pen "EB-99" not found — animal will land with no pen
   row 34  ⚠ dob in the future — sow will be flagged needs_review

services.csv     91 rows  ✅ 88 ok   ⚠ 3 warnings   ✗ 0 errors
   row 12  ⚠ sow "8221KRCS" not in sows.csv — will be auto-registered
   ...
```

The **Commit import** button is greyed out until errors == 0. Fix the
flagged rows (re-export from your source system or hand-edit the CSV)
and re-upload.

---

## Tips for AI agents generating these files

If you're a script or LLM converting another system's export into the
Peggy import format:

1. **Generate `locations.csv` first** if the destination farm hasn't
   set up its houses and pens yet. Walk the source export's pen
   universe (any pen referenced by an animal or event) and emit one
   row per pen. Pick a sensible `house_purpose` based on the source
   system's house labels — when in doubt, `gestation` is a reasonable
   default for sow houses.
2. **Generate `sows.csv` next** with all known animals. Even if a
   sow has no DOB or breed, include the row — having an `ear_tag`
   stub there is cleaner than the auto-backfill flagging it for
   review later.
3. **Use the source system's identifier as `ear_tag`** if the farm
   doesn't have a separate physical tag. Peggy treats `ear_tag` as
   the stable per-farm key.
4. **Map source statuses** to Peggy's enum:
   - "in heat / serviced" → `served`
   - "pregnant / gestating" → `served`
   - "lactating / nursing" → `lactating`
   - "weaned / dry / waiting" → `dry`
   - "open / available for service" → `open` (or `active`)
   - "removed / culled / retired" → `culled`
5. **Don't fabricate dates**. If the source system has no `dob`,
   leave the cell blank — auto-backfill defaults to a plausible value.
6. **Order `services.csv` chronologically** by `served_at` for stable
   re-service collapse behaviour.
7. **Pair farrowings with services** if both files have the data:
   match on sow + a `served_at` within `farrowed_at - 110` to
   `farrowed_at - 117`. Otherwise let the backfill cascade infer the
   service.
8. **Round numerics** before writing — `12.0` won't parse as an
   integer where `12` will. Born-alive / stillborn / mummified are
   integers (head count); birth weight is grams (integer).
9. **Validate before delivering**: run a small sample (5–10 rows per
   file) through the importer first. Fix anything flagged before
   uploading the full set.

---

## Common pitfalls

- **"sow X not in sows.csv"** for every service: you split the export
  into separate files but forgot to include the sow list. Either add
  `sows.csv` or accept the auto-backfill warnings.
- **Date "2025/05/04" rejected**: must be `YYYY-MM-DD` with dashes.
- **Pen warning for every row**: pen codes are
  `HOUSE_CODE-PEN_CODE` (e.g. `EB-12`). If your source uses
  `H1/P12`, transform before uploading. If you also forgot to upload
  `locations.csv` and the destination farm hasn't created its pens
  yet, every row will warn — add `locations.csv` to declare them.
- **`house_purpose` rejected**: must be one of `breeding | gestation
  | farrowing | nursery | grower | finisher | quarantine | hospital`.
  When in doubt, `gestation` is the safest default for sow housing
  and can be edited later through the Locations UI.
- **Duplicate ear_tag in the same file**: usually means the source
  exported each event of the sow as a separate row. Deduplicate to
  one row per sow before uploading.
- **CSV opens fine in Excel but fails to parse**: Excel sometimes
  inserts a UTF-8 BOM. Save as "CSV UTF-8 (Comma delimited)" and
  the importer will tolerate it.

---

## Versioning

This guide describes the importer for the schema as of Phase 8. If
new columns become required (e.g. when Phase 5 lands health/treatment
import), this file will be updated and the version bumped at the top.
