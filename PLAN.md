# Peggy Implementation Plan

Desktop-first. Phone PWA (`/m/:farm_slug`) is deferred to Phase 10+ — every schema, context, and policy below is designed so the phone UI can later reuse them unchanged.

Conventions:
- All tenant-scoped tables carry `farm_id` (non-null FK, indexed). Every query goes through a context function that takes `%Scope{}` and filters on `scope.farm_id`.
- All money stored as integer cents; all weights in grams; unit conversion happens at the view layer.
- Every mutating context function writes an `AuditLog` row in the same transaction.
- Soft-delete only where traceability requires it (animals, movements, treatments); hard-delete elsewhere.

---

## Animal status model (cross-cutting reference)

Status is a single source of truth on `animals.animals.status`. It changes **only through domain events** (service, farrowing, weaning, movement, treatment) — never through direct edit. The full set:

| Status | Applies to | Description (shown in UI tooltips) |
|---|---|---|
| `active` | all | Present and healthy; no current reproductive cycle. Default for new animals and for non-breeding stock. |
| `served` | sow / gilt | Sow has been serviced (AI or natural) and is presumed gestating. |
| `open` | sow / gilt | Pregnancy check negative or sow returned to heat; ready to re-serve. |
| `lactating` | sow | Sow has farrowed and is currently nursing piglets. |
| `dry` | sow | Piglets weaned; sow resting before next heat. |
| `under_treatment` | all | Receiving medication; withdrawal period active. Blocks sale/slaughter. |
| `culled` | all | Marked for culling (decision made) but not yet sold/slaughtered. Final disposition pending. |
| `sold` | all | Departed via sale. Terminal. |
| `slaughtered` | all | Departed via slaughter. Terminal. |
| `deceased` | all | Died on farm. Terminal. |
| `transferred` | all | Moved to another farm/entity. Terminal. |

**Groupings (centralized in `Animal`):**
- `present_statuses` — `active · served · open · lactating · dry · under_treatment · culled`
- `departed_statuses` — `sold · slaughtered · deceased · transferred`
- `breeding_active_statuses` — `served · lactating` (counted in active breeding inventory)
- `serviceable_statuses` — `active · open · dry` (eligible for new service)

**Sow lifecycle transitions:**
```
active ──service──▶ served ──farrowing──▶ lactating ──weaning──▶ dry ──service──▶ served
                       │                       │                   │
                       └──preg-check fail──▶ open ──service──▶ served
                       │
                       └──abortion──▶ open
```
Any present status → `under_treatment` ↔ previous status (on treatment start / withdrawal clear).
Any present status → `culled` → `sold`/`slaughtered`/`deceased` (terminal).

**Validation rules** (enforced in `Animal.changeset` + context functions):
- `served · open · lactating · dry` are valid only when `stage in [:sow, :gilt]`.
- Transitions are validated by `Animal.valid_transition?(from, to)`; invalid transitions return a changeset error.
- `status` is **read-only** in the animal edit form. Corrections are made by undoing the originating event (`Animals.undo_last_movement/2`, future `Breeding.undo_*`).

**Status descriptions** are exposed via `Animal.status_description/1` and a `Animal.statuses_with_descriptions/0` helper, used by HEEx tooltips and the `<.status_badge>` core component.

**Status history** is reconstructed from the audit log (Phase 2) — every status change is logged with `from`, `to`, `source_type`, `source_id`. No separate history table.

---

## Phase 0 — Repo hygiene (½ day)

- `mix format` config, `.credo.exs` (optional), `.tool-versions`
- CI workflow: `mix precommit` on push
- Seed script skeleton in `priv/repo/seeds.exs` that creates a demo farm + owner for dev
- Dev mailbox route (`/dev/mailbox`) already provided by Swoosh — confirm wired in router

## Phase 1 — Auth, tenancy, scope (3–4 days)

**Goal:** a logged-in user can create a farm, invite others, and land on `/farms/:slug`.

### Schemas
- `accounts.users` — email, hashed_password, confirmed_at, locale, timezone
- `accounts.user_tokens` — session/reset/confirm/invite
- `farms.farms` — slug (unique), name, timezone, unit_system (`:metric`|`:imperial`), plan, seat_limit, `deleted_at`, `deleted_by_id`
- `farms.memberships` — `user_id`, `farm_id`, `role` (`:owner`|`:manager`|`:worker`|`:vet`), `invited_by_id`, `accepted_at`
- `farms.invitations` — email, farm_id, role, token, expires_at

### Contexts
- `Peggy.Accounts` — register / log in / confirm / reset (use `mix phx.gen.auth` as base, then rework to include membership bootstrap)
- `Peggy.Farms` — `create_farm/2` (creator becomes owner), `list_farms_for_user/1`, `get_farm_by_slug!/1`, `invite/3`, `accept_invitation/2`, `change_role/3`, `remove_member/2`, `archive_farm/2` (soft delete: sets `deleted_at`, revokes pending invitations, keeps memberships), `restore_farm/1`
- All queries (`list_farms_for_user`, `get_farm_by_slug`, `FarmScope`) filter `is_nil(deleted_at)` — archived farms are invisible except in the "Archived" section of `/farms`

### Scope
- `Peggy.Scope` struct: `%{user: %User{}, farm: %Farm{} | nil, membership: %Membership{} | nil, role: atom()}`
- Plug `Peggy.FarmScope` — resolves `:farm_slug` path param, loads membership, 404s if user not a member, assigns `current_scope`
- `on_mount {PeggyWeb.FarmScope, :require_member}` for all live_sessions under `/farms/:slug`
- Policy module `Peggy.Policy` — `can?(scope, :action, resource)` keyed on role; every LiveView `handle_event` calls it

### Routes / UI
- `/` — if logged in, redirect to last farm or farm picker; else marketing stub + login
- `/login`, `/register`, `/reset`, `/confirm/:token`, `/invitations/:token`
- `/farms` — farm picker / create farm
- `/farms/:slug` — dashboard shell (empty for now)
- `/farms/:slug/settings` — farm profile, members, invitations (owner/manager only)
- Archive farm: owner-only section on `/farms/:slug/settings`. Typed-slug confirmation (not a plain y/n modal). Redirects to `/farms` on success. `/farms` shows an "Archived" section with restore button for 30 days

### Tests
- Registration + confirm + login happy path
- Membership isolation: user A cannot GET `/farms/<user-B-farm>/...` (assert 404, not 403, to avoid leaking existence)
- Role policy matrix (property-style if feasible)
- Archive: owner archives a farm → it disappears from members' `/farms` lists and `/farms/:slug/*` 404s; restore within window brings it back with all memberships intact; non-owners cannot archive

### i18n / units plumbing (do now, translate later)
- Wrap every user-facing string in `gettext("...")` from day one — retrofitting in Phase 9 is a landslide
- `PeggyWeb.Locale` plug + `on_mount :default` hook reading `scope.user.locale`, wired into every live_session
- `en` / `ms` / `zh` locales scaffolded with empty `.po` files; actual translations deferred to Phase 9
- `Peggy.Units` stub with `format_weight/2` etc. branching on `farm.unit_system` — every new numeric display site goes through it

### Done when
Two users in two farms; neither can see the other's data; invitation flow works end-to-end.

---

## Phase 2 — Location hierarchy & audit log (2 days)

Foundation that every later domain depends on.

### Schemas
- `locations.houses` — farm_id, name, code (unique per farm), purpose (`:breeding`|`:gestation`|`:farrowing`|`:nursery`|`:grower`|`:finisher`|`:quarantine`|`:hospital`)
- `locations.pens` — farm_id, house_id, name, code (unique per house), capacity, status (`:active`|`:quarantine`|`:cleaning`|`:retired`)

Hierarchy is flat: **house → pen**. Barn tier was dropped during Phase 2 as unnecessary for the target farms. `purpose` lives on the house (all pens in a house share it); pens track only physical capacity and operational status.
- `audit.audit_logs` — farm_id, actor_user_id, action (string), entity_type, entity_id, changes (jsonb diff), inserted_at (immutable — no `updated_at`, no UPDATE privilege in migration)

### Contexts
- `Peggy.Locations` — CRUD with capacity validation
- `Peggy.Audit.log!/4` — called inside every mutating transaction via `Ecto.Multi`

### UI
- `/farms/:slug/locations` — tree view (houses → pens) with inline edit
- `/farms/:slug/audit` — filterable table (owner/manager), streamed

### Done when
Can build a farm map; every create/update/delete shows up in the audit log with a diff.

---

## Phase 3 — Animal registry (4–5 days)

### Schemas
- `animals.animals` — farm_id, tag (ear tag), rfid, sex (`:male`|`:female`), birth_date, stage (`:piglet`|`:weaner`|`:grower`|`:finisher`|`:gilt`|`:sow`|`:boar`), status (see **Animal status model** above — full set: `active · served · open · lactating · dry · under_treatment · culled · sold · slaughtered · deceased · transferred`), previous_status (nullable, restored when `under_treatment` clears), sire_id, dam_id, current_pen_id, entered_at, exited_at, exit_reason
- `animals.batches` — farm_id, code, current_pen_id, head_count, stage, opened_at, closed_at
- `animals.movements` — farm_id, animal_id **or** batch_id + head_count, from_pen_id, to_pen_id, reason (`:placement`|`:pen_transfer`|`:sale`|`:slaughter`|`:death`|`:farm_transfer`|`:foster_on`|`:foster_off`|`:adjustment_gain`|`:adjustment_loss`) — `foster_on`/`foster_off` are piglet-batch-only (piglet joining/leaving a dam's litter); each is a single-entry event, previous_status (captured for departure reasons so `undo_last_movement/2` can restore status cleanly), moved_at, notes, actor_user_id
- Unique index on `(farm_id, tag)` where tag not null; same for rfid

### Contexts
- `Peggy.Animals` — `create_animal`, `create_batch`, `move!/2`, `split_batch/3`, `merge_batches/2`, `mark_dead!/3`, `cull!/3`, `undo_last_movement/2`
- `move!/2` is the single chokepoint: updates `current_pen_id`, inserts `movements`, updates `batches.head_count`, validates pen capacity, audit-logs. Everything else (sales, mortality) calls it.
- `undo_last_movement/2` reverses **only the most recent** movement (individual or batch): restores `current_pen_id`, restores `status` from `movement.previous_status`, reopens any linked breeding service, decrements/upserts placements for batch cases, writes `movement.undone` audit entry.
- **Centralized query scopes** on `Animal` — `scope_present/1`, `scope_breeding_herd/1`, `scope_serviceable/1`, `scope_saleable/1` (excludes `under_treatment` and withdrawal-blocked). Every LiveView autocomplete and filter uses these; never inline `where: status == "active"`.

### UI (desktop)
- `/farms/:slug/animals` — spreadsheet grid: filter by stage/pen/status, bulk edit pen, paste-from-Excel for bulk register
- `/farms/:slug/animals/:id` — animal card with genealogy tree, movement timeline, upcoming vax/treatments (stubbed until Phase 5)
- `/farms/:slug/batches` — list + grid entry
- `/farms/:slug/movements` — log view, filterable

### Key UX
- Paste-from-Excel: `phx-hook` that intercepts paste on the grid, splits tsv rows, pushes to server for validation, renders per-row errors inline
- Keyboard nav (tab/enter/arrows) in grids — one `Grid` LiveComponent reused across phases
- `<.status_badge status={...} />` core component — colour-coded pill with hover tooltip from `Animal.status_description/1`; used everywhere status is shown
- Animal edit form: `status` field is **display-only** (badge, not input). A footnote links to the event log: "Status changes through service, farrowing, weaning, movement, or treatment."
- **Initial herd import wizard** (`/farms/:slug/onboarding/herd`) — CSV paste that accepts tag, sex, stage, initial status, birth date, last service date (if `served`), expected farrow date (if `served`), last farrowing date (if `lactating`); creates corresponding `services`/`gestations`/`farrowings` stub rows so breeding history starts coherent instead of everything collapsed to `active`

### Done when
Can register 500 piglets via CSV paste, move them between pens, and see a parentage tree for any animal.

---

## Phase 4 — Breeding & reproduction (4 days)

### Schemas
- `breeding.heats` — sow_id, detected_at, method (`:visual`|`:boar_exposure`|`:hormonal`)
- `breeding.services` — sow_id, boar_id (nullable if AI), service_type (`:ai`|`:natural`), served_at, technician_id
- `breeding.gestations` — service_id, expected_farrow_date (served_at + 114d), status (`:open`|`:confirmed`|`:aborted`|`:farrowed`), pregnancy_check_at, pregnancy_result
- `breeding.farrowings` — gestation_id, farrowed_at, born_alive, stillborn, mummified, total_birth_weight_g, notes
- `breeding.piglet_births` — farrowing_id → creates animal rows with `dam_id`/`sire_id` wired
- `breeding.weanings` — farrowing_id, weaned_at, weaned_count, avg_wean_weight_g

### Contexts
- `Peggy.Breeding` — heat → service → gestation auto-created; farrowing creates piglet animals in one transaction
- **Owns sow status transitions** (see Animal status model): `record_service` → `served`; `record_farrowing` → `lactating`; `record_weaning` → `dry`; pregnancy-check fail or abortion → `open`; death/cull during gestation → records departure movement with `previous_status` captured so it can be undone cleanly
- Service forms restrict sow autocomplete to `Animal.scope_serviceable/1` (`active · open · dry`); attempting to service a `served` or `lactating` sow returns a validation error, not a silent duplicate
- Derived: `wean_to_service_interval(sow)` (uses `dry → served` gap), `parity(sow)`, `farrowing_rate(farm, range)`, `return_to_service_rate(farm, range)` (uses `open` count), `non_productive_days(sow)`

### UI
- `/farms/:slug/breeding` — dashboard: sows due this week, open services, recent farrowings
- `/farms/:slug/breeding/calendar` — Gantt/calendar of gestations (library TBD — prefer a handwritten SVG/CSS calendar over a JS dep)
- `/farms/:slug/breeding/sows/:id` — reproductive history per sow
- Farrowing entry form — creates N piglet animals, assigns to farrowing pen

### Done when
A sow's full reproductive lifecycle is recordable; dashboard surfaces sows due in the next 7 days.

---

## Phase 5 — Health & veterinary (4 days)

### Schemas
- `health.drugs` — farm_id, name, active_ingredient, withdrawal_days_meat, withdrawal_days_milk (future), default_dose
- `health.vaccination_schedules` — farm_id, stage, drug_id, age_days (trigger)
- `health.treatments` — animal_id **or** batch_id + head_count, drug_id, dose, route, administered_at, administered_by_id, reason, withdrawal_clear_at (computed)
- `health.vaccinations` — same shape as treatments but linked to a schedule_id
- `health.mortalities` — animal_id **or** batch_id + head_count, died_at, cause, post_mortem_notes, photo_urls
- `health.outbreaks` — farm_id, disease, started_at, ended_at; plus `outbreak_pens` join

### Contexts
- `Peggy.Health` — `record_treatment!/2` (computes `withdrawal_clear_at`, stashes `animal.status` into `previous_status`, sets `status = under_treatment`), `clear_withdrawal!/1` (restores `previous_status` when `withdrawal_clear_at` passes — driven by the Phase 8 scheduler tick), `record_mortality!/2` (calls `Animals.mark_dead!`), `due_vaccinations(scope, date)`, `withdrawal_blocked?(animal_or_batch, date)`
- `Animal.scope_saleable/1` already excludes `under_treatment`, so sale forms and autocomplete naturally hide blocked animals; `withdrawal_blocked?/2` remains the hard guard at the write boundary
- Quarantine: marking a pen as `:quarantine` flags all animals in it for withdrawal-like checks

### Cross-cutting: withdrawal enforcement
- `Sales.create_sale` and `Animals.slaughter!` both call `Health.withdrawal_blocked?/2` and refuse if true
- Desktop UI surfaces the block with an overrideable dialog (owner-only, audit-logged)

### UI
- `/farms/:slug/health/schedules`
- `/farms/:slug/health/treatments` — grid entry
- `/farms/:slug/health/mortalities`
- `/farms/:slug/health/withdrawal` — live list of animals currently within withdrawal

### Done when
Attempting to sell an animal inside its withdrawal window is blocked; a vet user can read but not write treatments.

---

## Phase 6 — Feed & growth (3 days)

### Schemas
- `feed.rations` — farm_id, name, stage, ingredients (jsonb), cost_per_kg_cents
- `feed.feedings` — pen_id **or** batch_id, ration_id, quantity_kg_thousandths (store as integer grams), fed_at
- `feed.weights` — animal_id **or** batch_id + sample_size, avg_weight_g, weighed_at, method (`:manual`|`:scale`)
- `feed.inventory_items` — farm_id, name, sku, unit, reorder_point
- `feed.inventory_movements` — item_id, delta, reason (`:purchase`|`:feeding`|`:adjustment`|`:waste`), at

### Contexts
- `Peggy.Feed` — feedings auto-deduct inventory; weights compute ADG (avg daily gain) against previous weight; FCR per batch = feed_kg / weight_gain_kg
- `low_stock(scope)` returns items under reorder_point

### UI
- `/farms/:slug/feed/rations`
- `/farms/:slug/feed/daily` — pen × date grid for feeding entry
- `/farms/:slug/feed/weights` — batch weight entry
- `/farms/:slug/feed/inventory` — stock with low-stock badge
- Growth chart per batch on the batch detail page

### Done when
ADG and FCR display on batch detail; inventory goes down when feedings are logged.

---

## Phase 7 — Sales, purchases, basic finance (3 days)

### Schemas
- `finance.buyers` / `finance.suppliers` — contact records
- `finance.sales` — farm_id, buyer_id, sold_at, total_cents
- `finance.sale_lines` — sale_id, animal_id **or** batch_id + head_count, live_weight_g, price_per_kg_cents, line_total_cents
- `finance.purchases` — supplier_id, purchased_at, category (`:breeding_stock`|`:feed`|`:meds`|`:other`), total_cents
- `finance.purchase_lines` — polymorphic target (animals / inventory_items / drugs)

### Contexts
- `Peggy.Finance` — `record_sale!/2` checks withdrawal, marks animals `:sold`, calls `Animals.move!` with reason `:sale`
- P&L per batch = Σ sale_lines − (Σ feed cost + Σ treatment cost + purchase cost allocation)

### UI
- `/farms/:slug/sales` — list + create
- `/farms/:slug/purchases`
- `/farms/:slug/finance/pnl` — filter by batch / date range, CSV export

### Done when
Selling a batch closes it, writes movements, respects withdrawal, and shows up in P&L.

---

## Phase 8 — Reporting, KPIs, tasks (3 days)

### KPIs (computed, not stored)
- Pigs weaned / sow / year
- Farrowing rate (farrowings / services, rolling 12mo)
- Pre-wean mortality %
- ADG, FCR per stage
- Traceability: given an animal id, walk movements + treatments + feedings + parents

### Schemas
- `tasks.tasks` — farm_id, assignee_user_id, kind, ref_entity_type, ref_entity_id, due_at, completed_at, completed_by_id
- `tasks.notifications` — user_id, task_id, channel (`:in_app`|`:email`), sent_at, read_at

### Generation
- Oban-less for now: a `Peggy.Scheduler` `GenServer` ticks hourly, enqueues tasks (vax due today, sows to check, overdue). If this outgrows, swap in Oban.

### UI
- `/farms/:slug/dashboard` — today's mortality, sows due this week, vax due today, open tasks
- `/farms/:slug/reports` — pivot builder (stage × date bucket × metric), chart, PDF/CSV export
- `/farms/:slug/tasks` — assignee view + bulk complete
- Email via Swoosh; in-app via `Phoenix.PubSub` topic `"user:#{user_id}"`

### Done when
Dashboard answers "what needs my attention today" in one screen for an owner on desktop.

---

## Phase 8.5 — Legacy CSV importer (2–3 days)

Owner-only admin page for migrating an existing herd + breeding
history into a Peggy farm from another system's CSV export. Distinct
from Phase 3's `HerdImport` LiveView (a spreadsheet-style onboarding
grid) — this is a multi-file CSV upload + dry-run preview + commit
flow.

### Goals
- Import five CSV files in one run (locations, sows, services,
  farrowings, weanings) without writing a single migration script per
  source system.
- Two-phase: validate everything in memory first, render a per-file
  report, only commit on user confirm.
- Reuse existing context fns — `Animals.create_animal`,
  `Breeding.record_service_with_backfill`,
  `Breeding.record_farrowing_with_backfill`,
  `Breeding.record_weaning_with_backfill` — so the cascade that
  back-fills missing parents (sow auto-registered when only services
  exist; inferred service synthesized when farrowing has no parent)
  works the same for CSV-imported rows as for hand-entered ones.
- Tag every created row with `created_via: "csv_import:<run_id>"` so a
  later rollback task can find them.

### Non-goals
- Streaming gigabyte-size files — capped at 10k rows per file (split
  the export into chunks for larger histories).
- Schema migration — the CSV format is documented in
  [`IMPORT_LEGACY_DATA.md`](IMPORT_LEGACY_DATA.md); changing column
  names is a breaking change with a versioning bump.
- Live progress bar during commit — single transaction per file, fast
  enough to finish before the LV would render a meaningful update.

### CSV files

| File              | Required? | Purpose                                |
|-------------------|-----------|----------------------------------------|
| `locations.csv`   | optional  | Houses + pens (denormalized).          |
| `sows.csv`        | yes       | Breeding herd.                         |
| `services.csv`    | optional  | Mating / AI events.                    |
| `farrowings.csv`  | optional  | Birth events.                          |
| `weanings.csv`    | optional  | Weaning events.                        |

Full column specs, validation rules, and examples live in
[`IMPORT_LEGACY_DATA.md`](IMPORT_LEGACY_DATA.md). That doc is the
contract for both human operators and AI agents preparing CSVs.

### UX — 3-step LiveView

Route: `/farms/:slug/admin/import` (new), gated `:owner` only.
Linked from the Settings page (and the desktop farm-nav under
"Settings" submenu when added).

1. **Upload** — `allow_upload` slots for each file. Each slot links
   to a "Download template" returning a header-only CSV.
2. **Validation report** — per-file table with row counts + warnings
   + errors. **Commit** button disabled while errors > 0.
3. **Commit** — runs each file's transaction; success screen shows
   per-file outcome counts and a link to the audit `import.run`
   entry.

### Validation strategy

Two classes of issues per row:

- **Errors** block commit: missing required column, blank required
  field, bad date format, unknown enum value, duplicate keys within
  a file, negative integers in count fields.
- **Warnings** allow commit: unknown pen (sow lands without one),
  unknown sow ear-tag in services/farrowings/weanings (auto-backfill
  cascade kicks in, flagged `needs_review`).

Cross-file references resolve against a combined index: existing DB
rows + freshly-parsed rows from earlier files in the run. So a
`services.csv` row that references a sow only present in `sows.csv`
gets a clean ✓ rather than the unknown-sow warning.

### Commit semantics

- One transaction per file (`locations` → `sows` → `services` →
  `farrowings` → `weanings`). On any per-row failure inside a file,
  abort that file's transaction; earlier files keep their results.
- A single `import.run` audit event records the run-id + per-file
  counts. Each created row gets `created_via:
  "csv_import:#{run_id}"` so a later rollback task can delete them
  wholesale.
- Idempotency: re-importing the same `sows.csv` rejects duplicate
  ear_tags as errors (existing `unsafe_validate_unique`). For
  partial re-imports, the operator edits the CSV.

### Permission model

- `:owner` only initially. Add `:import_data` policy action so it
  can be selectively granted later (e.g. a migration consultant
  with manager role).
- Auto-route plug pass-through: the import page is desktop-only —
  no mobile equivalent. The audit log on each animal's Trace page
  is the read-only mobile counterpart.

### Build order

- [x] **`Peggy.Imports` schema + parsers** — column lists per file,
      `parse_and_validate/2`, helpers, NimbleCSV dep.
- [x] **Per-file validators** — sows / services / farrowings /
      weanings / locations. Errors-vs-warnings classification.
- [x] **Cross-file resolution** — sow_index combines existing DB +
      `sows.csv` pending; pen_index combines existing + `locations.csv`
      pending.
- [x] **Unit tests** — 30 cases covering happy paths, every error
      and warning kind, file-level errors, summary aggregation.
- [x] **`IMPORT_LEGACY_DATA.md`** — user/agent CSV-prep guide.
- [x] **`Peggy.Imports.commit/2`** — per-file transactions, tags
      rows with `created_via:"csv_import:<run_id>"`, single
      `import.run` audit event with per-file counts. 5 commit
      tests covering happy path + locations/sows ordering + audit.
- [x] **3-step LiveView** at `/farms/:slug/admin/import` — upload
      slots (5 files, 5 MB cap), validation report (summary +
      per-file warning/error blocks, 50-row cap with "+N more"),
      commit screen (run id + per-file outcomes + restart).
- [x] **Template downloads** — `DataImportController` serves
      header-only CSV per file from `/admin/import/template/:type`.
- [x] **Farm-nav entry** — "Import" link visible to anyone with
      `:import_data` (manager + owner). Policy action added.
- [x] **Rollback** — `Peggy.Imports.list_runs/1` and
      `Peggy.Imports.rollback/2` exposed via a "Past imports"
      section on the importer page (visible on the Upload step).
      Each row has a confirmed Rollback button that deletes
      animals + services + farrowings + weanings tagged with
      that run id, in dependency-safe order, inside one
      transaction. Logs an `import.rollback` audit row. FK
      violations from post-import dependencies surface as a flash
      and roll the whole rollback back.

---

## Phase 9 — Non-functional polish (2–3 days)

- i18n: translate the `ms` and `zh` `.po` files (plumbing landed in Phase 1 — `gettext` wrapping, `PeggyWeb.Locale` plug + `on_mount` hook reading `user.locale`, `en`/`ms`/`zh` locales configured); add a locale switcher in user settings
- Units: flesh out `Peggy.Units` with real conversion tables (stub landed in Phase 1); audit numeric display sites to route through it
- Timezone: all display via `DateTime.shift_zone!` using `farm.timezone`
- Backups: document pg_dump procedure; add a `mix peggy.export_farm <slug>` task that emits a zip of CSVs (satisfies GDPR-style export-on-request)
- Farm purge: `mix peggy.purge_archived_farms` (or scheduled job) hard-deletes farms archived > 30 days ago and cascades child data; records a `farm.purged` entry in a platform-level audit table (not farm-scoped, since the farm is gone). Offer "export before purge" tie-in with `export_farm`
- Rate limiting on auth endpoints

---

## Phase 10+ — Phone PWA (separate plan)

Not started until desktop covers Phases 1–8. Will cover: `PeggyWeb.Mobile` LiveView tree under `/m/:farm_slug`, service worker, IndexedDB write queue, device-based routing, WebHID/Bluetooth for scanners & scales, last-write-wins conflict resolution with per-domain overrides (mortality / farrowing never auto-merge — flag for human). Schemas above already include everything needed; no backend changes expected beyond a `client_uuid` idempotency column on every write-heavy table, which we'll add in Phase 1 proactively to avoid a later migration wave.

---

## Deferred / out of scope for MVP

Slaughterhouse ops · EBV / genetics calculations · IoT automation · buyer marketplace · LiveView Native app · accounting integrations (Xero, QuickBooks) · government traceability adapters.
