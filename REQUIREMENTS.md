# Peggy — Swine Farm Management App

Initial Requirements

---

## 1. Tenancy & Users
- Multi-farm SaaS; one user can belong to multiple farms
- Roles: owner, manager, worker, veterinarian (external, read-mostly)
- Per-farm invitations, seat limits, subscription plan
- Farm identity in URL (`/farms/:slug/...`)
- Per-farm data isolation via `farm_id` row scoping

## 2. Dual Interface
- **Phone UI** (`/m/:farm_slug`) — barn-floor data entry, scanning, task lists, simple reports; offline-first, PWA, large touch targets
- **Desktop UI** (`/farms/:farm_slug`) — batch/grid data entry, complex reports, charts, farm setup, finance; keyboard-driven
- Shared backend contexts and schemas; separate LiveViews, layouts, and JS bundles
- Auto-route by device, with manual override

## 3. Animal Registry
- Individual pigs (ear tag / RFID) and batch-level tracking
- Lifecycle stages: piglet, weaner, grower, finisher, sow, boar, cull
- Parentage (sire/dam), genealogy view
- House → pen hierarchy with capacity limits
- Movement log (pen-to-pen, farm-to-farm, sale, slaughter, death)
- Stage promotion (weaner → grower → finisher) is operator-confirmed,
  not auto. The "Promote batch animals" triage screen lists batches whose
  age has crossed per-farm thresholds and offers bulk promotion. A third
  bucket flags overdue finishers (still on farm past the configured
  age) for departure.

## 4. Breeding & Reproduction
- Heat detection log
- Service records (AI / natural), boar tracking
- Gestation calendar with farrowing forecast (~114 days)
- Farrowing entry: born alive, stillborn, mummified, birth weights
- Weaning event, wean-to-service interval, parity per sow
- Culling decisions based on performance

## 5. Health & Veterinary
- Vaccination schedules per stage with auto-generated reminders
- Treatment logs with drug, dose, withdrawal period
- Mortality log with cause, post-mortem notes
- Disease outbreak flagging / quarantine pen marker
- Withdrawal enforcement before sale/slaughter

## 6. Feed & Growth
- Feed ration library per stage
- Daily feed consumption per pen/batch
- Weight records (manual or scale integration)
- Auto-computed ADG and FCR
- Feed inventory with low-stock alerts

## 7. Sales & Finance (light)
- Sale records (live weight, price, buyer)
- Purchase records (breeding stock, feed, meds)
- Basic P&L per batch / per farm
- CSV export; accounting integration later

## 8. Reporting & KPIs
- **Phone:** single-screen reports — today's mortality, sows due this week, vax due today
- **Desktop:** filterable pivots, charts, date ranges, exportable PDF/CSV
- KPIs: pigs weaned/sow/year, farrowing rate, pre-wean mortality, FCR, ADG
- Traceability report per animal/batch

## 9. Offline-First (Phone UI)
- PWA installable on tablets/phones
- Works fully offline for scanning, data entry, viewing today's tasks, viewing cached animal/pen cards
- IndexedDB write queue, syncs on reconnect
- Per-farm offline cache, namespaced by `farm_id`
- Conflict resolution: last-write-wins with per-domain overrides
- Desktop UI: online-mostly, offline read-cache only

## 10. Barn-Floor UX (Phone)
- Barcode / QR / RFID scanning for animal and pen IDs
- Large touch targets, glove-friendly, one-handed operation
- Voice notes and photo attachments for health events
- Minimal typing; pick lists and scans preferred

## 11. Batch Entry UX (Desktop)
- Spreadsheet-like grids with paste-from-Excel
- Bulk edit, bulk import (CSV)
- Keyboard shortcuts (tab, enter, arrow navigation)
- Gantt/calendar views for gestation and vaccination planning

## 12. Notifications & Tasks
- Daily task list per worker (vaccinations due, sows to check, pens to weigh)
- Push notifications for farrowing alerts, overdue tasks
- In-app + email; SMS optional

## 13. Audit & Compliance
- Immutable audit log of who changed what, when
- Drug withdrawal enforcement before sale/slaughter
- Per-tenant data export on request

## 14. Non-Functional
- Localization (English + local languages, e.g., Bahasa, Chinese)
- Metric + imperial units toggle
- Timezone per farm
- Regular backups, per-farm restore
- Mobile bundle size kept small for rural connections

## 15. Integrations (future)
- Electronic weigh scales (Bluetooth / serial)
- RFID reader hardware (WebHID)
- Climate sensors (temp/humidity per barn)
- Accounting software (Xero, QuickBooks)
- Government traceability systems (country-specific)

## 16. Out of Scope for MVP
- Slaughterhouse operations
- Genetics / EBV calculations
- IoT sensor automation
- Marketplace / buyer portal
- Native mobile app (LiveView Native — revisit post-MVP)
