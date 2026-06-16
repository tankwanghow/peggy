# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Skill Authoring Convention

When, during a session, you discover **reusable domain knowledge** that isn't yet captured
in a `.claude/skills/*.md` file — a non-obvious pattern, gotcha, workflow, schema/API contract,
or convention that future sessions would benefit from — proactively **draft a new skill** (or
extend the closest existing one) and **ask the user to confirm** before finalizing. Do not
auto-create silently and do not skip the confirmation.

- Skills live in `.claude/skills/` (project) or `~/.claude/skills/` (broadly reusable). Each is
  one markdown file with frontmatter (`name`, `description`); the `description` is the trigger
  text, so make it specific about *when* the skill applies.
- Prefer **extending an existing skill** over creating a near-duplicate.
- Use the `superpowers:writing-skills` skill for structure/verification when authoring.
- Keep skills in sync with the code they describe; flag drift when you notice it.

## Project

Peggy — a multi-tenant swine (pig) farm management Phoenix 1.8 / LiveView 1.1 SaaS app. See `REQUIREMENTS.md` for the full product scope. Project is in early scaffolding (no `lib/peggy/` contexts yet beyond the default Phoenix generator output).

## Commands

- `mix setup` — install deps, create DB, migrate, seed, install & build assets
- `mix phx.server` / `iex -S mix phx.server` — run dev server at `localhost:4000`
- `mix test` — runs `ecto.create --quiet` + `ecto.migrate --quiet` then tests. Single file: `mix test test/path/to_test.exs`. Re-run failures: `mix test --failed`
- `mix precommit` — **run before finishing changes**: `compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `test`
- `mix ecto.reset` — drop + recreate DB
- `mix ecto.gen.migration <name_with_underscores>` — always use this to create migrations

### Shared workspace assets & Docker deploy

esbuild, tailwindcss, and heroicons are pinned under `~/Projects/elixir/.global_assets`
and wired via `~/Projects/elixir/shared_config`. Run `.global_assets/setup.sh` once after
clone. Full details: `~/Projects/elixir/shared_config/WORKSPACE_ASSETS.md`.

Linode deploy builds from the **monorepo root** (not this directory alone):

```bash
./deploy_to_linode/deploy.sh deploy.conf
```

## Architecture

### Dual interface (core design constraint)
Two separate UIs share the same backend contexts and Ecto schemas:
- **Phone UI** under `/m/:farm_slug` — offline-first PWA, barn-floor data entry, scanning, large touch targets, IndexedDB write queue syncing on reconnect
- **Desktop UI** under `/farms/:farm_slug` — spreadsheet-style batch entry, reports/charts, keyboard-driven, online-mostly

Each UI has its own LiveViews, layouts, and JS bundles. Auto-routed by device with manual override. Only `app.js`/`app.css` bundles are supported — vendor deps must be imported into those.

### Multi-tenancy
- Farm identity lives in the URL slug; per-farm data isolation is enforced via `farm_id` row scoping
- Users can belong to multiple farms; roles: owner, manager, worker, veterinarian
- Offline cache on phone must be namespaced by `farm_id`

### Domain areas (planned contexts)
Animal registry (individual + batch, pen/barn/house hierarchy, movement log) · Breeding (heat, service, gestation, farrowing, weaning) · Health (vaccinations, treatments, withdrawal enforcement, mortality) · Feed & growth (rations, ADG/FCR) · Sales & finance · Reporting/KPIs · Tasks & notifications · Immutable audit log.

Drug withdrawal periods must be enforced before sale/slaughter — a cross-cutting rule touching health + sales.

## Project-specific conventions

Full Phoenix 1.8 / Elixir / LiveView / Ecto / HEEx usage rules are in **`AGENTS.md`**. Read it before writing non-trivial code. Highlights:

- HTTP: use `Req` (included). Do **not** add `httpoison`, `tesla`, or `httpc`.
- LiveView templates **must** start with `<Layouts.app flash={@flash} ...>`; `current_scope` must be passed through.
- Forms: always `to_form/2` in the LiveView + `<.form for={@form}>` + `<.input>` in the template. Never pass a changeset to `<.form>`.
- Icons: always `<.icon name="hero-..." />`, never the `Heroicons` module.
- Tailwind v4: no `tailwind.config.js`; use `@source` directives in `app.css`; never use `@apply`. **daisyUI 5 IS used** — build UI with its component classes (`btn`, `badge`, `card`, `modal`, `navbar`, `alert`, `input`, …) and the shared `core_components.ex` / `layouts.ex` components.
- Collections in LiveView must use streams (`stream/3` + `phx-update="stream"`); never `phx-update="append"`.
- Inline JS in HEEx must use colocated hooks (`:type={Phoenix.LiveView.ColocatedHook}`), never raw `<script>`.
- Elixir: no `String.to_atom/1` on user input; predicates end in `?` not `is_`; lists use `Enum.at` not `list[i]`; `if`/`case` results must be rebound outside the block.
- Tests: `start_supervised!/1`, never `Process.sleep`; use `Process.monitor` + `assert_receive {:DOWN, ...}` or `:sys.get_state/1` for sync.
