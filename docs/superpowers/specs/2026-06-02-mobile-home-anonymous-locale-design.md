# Mobile home page + anonymous language switching — design

Date: 2026-06-02
Status: approved design, pre-implementation

## Goal

1. Add a phone-optimized landing page (`home_mobile.html.heex`) served at `/`
   to mobile visitors.
2. Let **anonymous** visitors change the UI language from the home page
   (mobile + desktop), persisted across requests.

## Current state

- `/` → `PageController.home`. Logged-in users redirect to their default farm;
  anonymous users get `render(conn, :home)` (a single, desktop-oriented
  `page_html/home.html.heex` wrapped in `Layouts.app`). The page is already
  responsive but there is no mobile-specific template.
- `PeggyWeb.Locale` plug + `on_mount` set the Gettext locale **only** from
  `current_scope.user.locale`, falling back to `"en"`. No cookie/anonymous
  support, so an anonymous visitor is always English.
- `language_switcher/1` (in `layouts.ex`) renders only when
  `@current_scope.user` is present; `LocaleController` persists to
  `user.locale` and redirects back (open-redirect-guarded).
- `login`, `registration`, `confirmation`, and `settings` LiveViews all use
  `Layouts.app`. (So a navbar-level anonymous switcher would leak onto
  login/register — hence the switcher goes in the home templates instead.)
- `PeggyWeb.Plugs.AutoRouteByDevice` already detects device via a
  `peggy_view=mobile|desktop` cookie and a mobile user-agent regex.

## Architecture

### 1. Anonymous locale via a `peggy_locale` cookie

- **`PeggyWeb.Locale.call/2`**: ensure cookies are fetched, then compute
  `locale =` first supported of: logged-in `user.locale`, the `peggy_locale`
  cookie, `"en"`. Call `Gettext.put_locale/2`, `assign(conn, :locale, locale)`,
  and `put_session(conn, :locale, locale)` (so LiveViews can read it without
  cookie access).
- **`PeggyWeb.Locale.on_mount/4`**: `locale =` first supported of: logged-in
  `user.locale`, `session["locale"]`, `"en"`. (The plug populated the session
  on the HTTP request that mounts the LiveView.)
- Supported set stays `~w(en ms zh)`, default `"en"`. Logged-in `user.locale`
  always wins over the cookie.

### 2. `LocaleController` sets the cookie

`update/2` (locale ∈ `en/ms/zh`):
- If `current_scope.user` present → `Accounts.update_user_locale(user, locale)`
  (unchanged).
- **Always** `put_resp_cookie(conn, "peggy_locale", locale, max_age: 60*60*24*365, same_site: "Lax")`.
- Redirect to the referer via the existing `safe_path/1` guard.
- Unsupported locale clause: just redirect back (no cookie set).

### 3. `language_switcher/1` refactor

- Determine the active locale from `Gettext.get_locale(PeggyWeb.Gettext)`
  (works with or without a user; the plug/on_mount already set it).
- Add `attr :anonymous, :boolean, default: false`. Keep `attr :current_scope`.
  Render the dropdown when `@anonymous or (@current_scope && @current_scope.user)`.
  Highlight the option whose code equals the active locale.
- Existing navbar call (`<.language_switcher current_scope={@current_scope} />`)
  is unchanged → still hidden for anonymous users on login/register/etc.
- Home templates call `<.language_switcher anonymous={true} />`.

### 4. Device-detected home + mobile template

- **`PeggyWeb.Device`** (new module) — `mobile?(conn)`:
  - `peggy_view` cookie `"mobile"` → `true`; `"desktop"` → `false`;
  - otherwise the mobile user-agent regex.
  Extract the UA regex out of `AutoRouteByDevice` into this module and have the
  plug delegate to `PeggyWeb.Device` (DRY; behavior unchanged).
- **`PageController.home`**: anonymous branch becomes
  `if PeggyWeb.Device.mobile?(conn), do: render(conn, :home_mobile), else: render(conn, :home)`.
  Logged-in redirect is unchanged.
- **`home_mobile.html.heex`** (new): wrapped in
  `<Layouts.mobile flash={@flash} current_scope={@current_scope}>`, containing
  its own top bar (🐷 Peggy brand, `<.language_switcher anonymous={true} />`,
  `<.theme_toggle />`), a single-column hero, stacked feature cards, and
  Log in / Sign up buttons. **Reuses the same `gettext(...)` msgids as the
  desktop home** so no new translation work is needed (any genuinely new string
  would fall back to English until translated — avoid introducing new ones).
- **`home.html.heex`** (desktop): add `<.language_switcher anonymous={true} />`
  in the hero section (top of the content).

## Testing

- **Locale plug** (`test/peggy_web/locale_test.exs` or controller-level):
  with no user and `peggy_locale=ms` cookie → Gettext locale is `ms`; a
  logged-in `zh` user with `peggy_locale=ms` cookie → `zh` (user wins); neither
  → `en`.
- **`LocaleController`**: anonymous `GET /locale/ms` sets the `peggy_locale`
  cookie and redirects to referer; logged-in sets cookie **and** `user.locale`.
- **`PageController`**: a mobile user-agent (or `peggy_view=mobile` cookie) at
  `/` renders the mobile home (assert a marker unique to `home_mobile`); a
  desktop UA renders the desktop home. Logged-in still redirects.
- **Switcher on home**: anonymous `GET /` (desktop) and the mobile home both
  contain `Bahasa Malaysia`, `中文`, and `/locale/ms` + `/locale/zh` links.

## Non-goals

- Anonymous switcher on login/register/confirmation (kept home-only).
- Changing logged-in locale behavior (user.locale still wins).
- New translations (mobile home reuses existing translated msgids).
- Device-routing `/` via `AutoRouteByDevice` (we detect in the controller and
  render the right template under the same `/` URL; no redirect).
