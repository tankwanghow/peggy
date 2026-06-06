# Mobile Autocomplete — Design Spec

**Date:** 2026-06-06
**Status:** Approved (design), pending implementation plan

## Problem

The desktop UI has a complete, reusable `<.autocomplete>` component
(`core_components.ex:370`) backed by the `AutoComplete` JS hook (`app.js:42`)
and the vendored `autoComplete.js`. It is used throughout `farm_live`. **No
mobile LiveView uses it.**

Mobile picker fields today take a different, weaker approach: the user types an
*exact* code/tag into a plain `type="text"` input and the server resolves it on
`phx-change` (showing `✓` or `⚠`), with no list to choose from. Affected fields:

- `mobile_live/breeding/movement_form.ex` — From pen / To pen
  (`from_code`/`to_code` → `resolve_pen/3` → `Locations.find_pen_by_code/2`)
- `mobile_live/animals.ex` — register pen (`register_pen_code` → same path)
- `mobile_live/breeding/gestating.ex` — service form boar (`boar_tag`)

Two obstacles to simply reusing the desktop component on mobile:

1. The desktop dropdown is `absolute top-full` (opens **downward**); on a phone
   the on-screen keyboard covers the bottom ~45% of the viewport, hiding it.
2. Desktop row sizing (`py-1.5`) is too small for touch.

## Goal

One reusable, mobile-friendly autocomplete pattern applied across the mobile
picker fields, with a polish pass on the list-search bars. The result must look
polished (daisyUI) and work offline (client-side filtering, no server
round-trip to resolve a selection).

## Decisions

- **Interaction model: flip-up dropdown** (chosen over a bottom-sheet picker).
  Reuse the existing component; results open **upward** so the keyboard never
  covers them. Smallest change, no drift from desktop.
- **Picker fields move from server-resolve to client-side autocomplete.** The
  client-side model (items preloaded as JSON, selection writes the id into a
  hidden input) is the better fit for the offline-first PWA — it needs no
  connection to resolve a choice.
- **List-search bars stay live-filter.** The bars in `animals`, `serviceable`,
  `lactating`, `gestating` already filter the card stream live below them — the
  better mobile pattern. They get a polish pass only (clear button + result
  count), **not** a dropdown, which would visually compete with the cards.
- **Rejected:** auto-detecting viewport space to flip automatically (fights the
  keyboard resize events; can be layered on later); a separate mobile component
  (duplicates logic, guaranteed drift).

## Design

### 1. Component + hook changes

`core_components.ex` `<.autocomplete>`:

- Add `attr :drop_up, :boolean, default: false`. When true the results `<ul>`
  is positioned `bottom-full mb-1` instead of `top-full mt-1`.
- Add `attr :touch, :boolean, default: false` (mobile callers pass `true`) for
  touch-friendly sizing: result rows `py-3` (≈44px min height), `input-lg`
  on the visible input.
- Emit orientation/size to the DOM via data attributes
  (e.g. `data-ac-drop-up`, `data-ac-touch`) that the hook reads.

`app.js` `AutoComplete` hook:

- Read `this.el.dataset.acDropUp` / `acTouch` and build the
  `resultsList.class` accordingly:
  - drop-up: swap `top-full mt-1` → `bottom-full mb-1`.
  - touch: row class `py-1.5` → `py-3`; ensure comfortable tap targets.
- All other behavior (hidden-id write, `ac:reset`, blur auto-commit, freetext
  mode) is unchanged.

### 2. Mobile picker fields

Each form preloads its item list once when the form opens and renders
`<.autocomplete drop_up touch ...>` instead of the plain text input.

| Form / field | Item source | Hidden id field |
|---|---|---|
| `movement_form` From pen | `Locations.list_all_pens/1` → `%{id, label: "HOUSE-PEN"}` | `from_pen_id` |
| `movement_form` To pen | same | `to_pen_id` |
| `animals` register pen | same | `current_pen_id` |
| `gestating` service form boar | `Shared.animal_items(boars, "boar")` | `boar_id` |

- Reuse the existing item-building helpers: the pen mapping at
  `farm_live/breeding/shared.ex:211` and `Shared.animal_items/2`
  (`shared.ex:226`). Extract/share rather than duplicate.
- Replace the `from_code`/`to_code`/`register_pen_code`/`boar_tag` +
  server-resolve plumbing with the hidden-id the component writes. Keep a
  visible state hint (`✓` etc.) only where it still adds value.

### 3. List-search bar polish

In `animals`, `serviceable`, `lactating`, `gestating`:

- Add a clear (`×`) button inside the search bar that resets the filter.
- Show a small result count (e.g. "12 results").
- No dropdown; behavior otherwise unchanged.

### 4. Look-and-feel (daisyUI)

- Dropdown panel: `bg-base-100`, `rounded`, `shadow-lg`, `divide-y
  divide-base-200`, `max-h` with scroll.
- Match highlight in `text-primary`; selected/active row `bg-primary/10`.
- Comfortable touch rows; empty state uses the existing `empty_text` row.

### 5. Testing

- LiveView tests: choosing a pen/boar sets the expected hidden id and the form
  saves with the right `*_id`; the bars' clear button resets the filter and
  count.
- Dropdown positioning/orientation is visual and not unit-tested, consistent
  with how the existing component is treated.

## Out of scope

- Bottom-sheet / full-screen picker variant.
- Auto-flip-on-space detection.
- Adding dropdowns to the list-search bars.
- Any desktop behavior change (desktop keeps `drop_up=false` defaults).

## Affected files

- `lib/peggy_web/components/core_components.ex` — `<.autocomplete>` attrs
- `assets/js/app.js` — `AutoComplete` hook
- `lib/peggy_web/live/mobile_live/breeding/movement_form.ex`
- `lib/peggy_web/live/mobile_live/animals.ex`
- `lib/peggy_web/live/mobile_live/breeding/gestating.ex`
- `lib/peggy_web/live/mobile_live/breeding/{serviceable,lactating}.ex` — bar polish
- shared item-builder location (extract from `farm_live/breeding/shared.ex` if needed)
- corresponding tests under `test/peggy_web/live/mobile_live/`
