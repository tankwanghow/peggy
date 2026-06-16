# User Account Dropdown Menu

**Date:** 2026-06-16  
**Status:** Approved

## Goal

Consolidate the scattered top-navbar user actions (language, theme, My farms, Settings, Log out) and the farm-sub-nav account items (Members, Farm settings) into a single daisyUI dropdown anchored to a user identity pill button in the top-right corner.

## Trigger Button

- **Shape:** Pill (`rounded-full`) with left-padding for the avatar circle and right-padding for text + chevron.
- **Avatar:** 28–32 px circle with the user's first initial (uppercase), coloured with `bg-primary`.
- **Label:** Username if `current_scope.user.username` is non-empty; otherwise `current_scope.user.email`. Truncates with `truncate max-w-[160px]` on small screens.
- **Chevron:** `hero-chevron-down-micro` icon at the right edge.
- **Position:** Rightmost item in the top navbar `<ul>`, after the Mobile view-switcher link.

## Dropdown Panel

Uses daisyUI `dropdown dropdown-end` — the same pattern as the Animals and Breeding menus in `farm_nav`. The panel opens below-right of the trigger.

### Header (non-interactive)

Displays avatar (32 px), username/email (bold), and current farm slug (mono, muted). Separated from the items by a bottom border.

### Section: Preferences

Label: **PREFERENCES** (small-caps, muted)

| Item | Rendering | Notes |
|------|-----------|-------|
| Language | Inline language rows | **Do NOT** nest `<.language_switcher>` — it is itself a `dropdown`, which breaks when nested. Instead render each locale as a plain `<.link href={~p"/locale/#{code}"}>` row directly in the `<ul>`, with the active locale highlighted via `font-semibold` or a checkmark. |
| Theme | Existing `<.theme_toggle>` | The three-button pill renders fine inline in a `<li>` row. |

### Section: Farm

Label: **FARM** (small-caps, muted). Only rendered when `current_scope.farm` is present and the user has the relevant permission.

| Item | Route | Permission guard |
|------|-------|-----------------|
| My farms | `/farms` | always shown (logged in) |
| Members | `/farms/:slug/members` | `Policy.can?(scope, :view_farm)` |
| Farm settings | `/farms/:slug/settings` | `Policy.can?(scope, :manage_farm_settings)` |

### Section: Account

Label: **ACCOUNT** (small-caps, muted)

| Item | Route | Notes |
|------|-------|-------|
| Account settings | `/users/settings` | always shown |
| Log out | `/users/log-out` (DELETE) | red text (`text-error`) |

## Changes to Existing Navigation

### Top navbar (`Layouts.app`)

**Remove:**
- Bare email `<li>` text
- `<.language_switcher>` standalone list item
- `<.theme_toggle>` standalone list item
- My farms link
- Settings (account) link
- Log out link

**Keep:**
- Peggy logo + farm slug
- Mobile view-switcher link

**Add:**
- User account dropdown (described above)

### Farm sub-nav (`farm_nav`)

**Remove:**
- Members link (`farm_nav_link` for `:view_farm`)
- Settings link (`farm_nav_link` for `:manage_farm_settings`)

**Keep:**
- Dashboard, Locations, Animals (dropdown), Breeding (dropdown), Reports

## Implementation File

All changes are confined to `lib/peggy_web/components/layouts.ex`:

1. Edit the `app/1` function's `<ul>` to replace removed items with the new dropdown.
2. Add a private `user_dropdown/1` component function.
3. Edit `farm_nav/1` to remove the Members and Settings `farm_nav_link` calls.

No new files, no new dependencies, no router changes.

## Out of Scope

- Mobile layout (`mobile_app`) already has a "More" sheet that serves the same purpose on phone — no changes needed there.
- Avatar image upload (initials-only for now).
- Notification badge on the trigger button.
