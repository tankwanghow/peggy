# Mobile Home + Anonymous Language Switching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Serve a phone-optimized landing page at `/` and let anonymous visitors switch UI language from the home page (mobile + desktop), persisted via a cookie.

**Architecture:** A `PeggyWeb.Device.mobile?/1` helper drives template choice in `PageController`. A `peggy_locale` cookie carries the anonymous locale; the `Locale` plug reads user.locale → cookie → default and bridges it into the session for LiveViews. `LocaleController` (moved to a public route) sets the cookie. The `language_switcher` gains an `anonymous` mode and is placed in the home templates only.

**Tech Stack:** Elixir, Phoenix LiveView 1.1, Gettext, daisyUI 5, ExUnit.

Spec: `docs/superpowers/specs/2026-06-02-mobile-home-anonymous-locale-design.md`.

---

## File Structure

- Create `lib/peggy_web/device.ex` — `PeggyWeb.Device.{mobile?/1, mobile_ua?/1}`.
- Modify `lib/peggy_web/plugs/auto_route_by_device.ex` — delegate UA check to `PeggyWeb.Device`.
- Modify `lib/peggy_web/locale.ex` — cookie + session fallback.
- Modify `lib/peggy_web/router.ex` — move `/locale/:locale` to the public scope.
- Modify `lib/peggy_web/controllers/locale_controller.ex` — set `peggy_locale` cookie.
- Modify `lib/peggy_web/components/layouts.ex` — refactor `language_switcher/1`.
- Modify `lib/peggy_web/controllers/page_controller.ex` — device-detect render.
- Create `lib/peggy_web/controllers/page_html/home_mobile.html.heex`.
- Modify `lib/peggy_web/controllers/page_html/home.html.heex` — add anonymous switcher.
- Tests: `test/peggy_web/device_test.exs`, `test/peggy_web/locale_test.exs`, extend `test/peggy_web/controllers/locale_controller_test.exs`, extend `test/peggy_web/controllers/page_controller_test.exs`, extend `test/peggy_web/live/localization_test.exs`.

Run `mix precommit` before each commit unless a task says otherwise.

---

## Task 1: `PeggyWeb.Device` helper + plug delegation

**Files:**
- Create: `lib/peggy_web/device.ex`
- Modify: `lib/peggy_web/plugs/auto_route_by_device.ex`
- Test: `test/peggy_web/device_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule PeggyWeb.DeviceTest do
  use PeggyWeb.ConnCase, async: true

  test "peggy_view cookie overrides the user-agent" do
    assert PeggyWeb.Device.mobile?(Plug.Test.put_req_cookie(build_conn(), "peggy_view", "mobile"))

    desktop =
      build_conn()
      |> Plug.Test.put_req_cookie("peggy_view", "desktop")
      |> put_req_header("user-agent", "iPhone")

    refute PeggyWeb.Device.mobile?(desktop)
  end

  test "falls back to the user-agent when no cookie" do
    assert PeggyWeb.Device.mobile?(put_req_header(build_conn(), "user-agent", "Mozilla (iPhone)"))
    refute PeggyWeb.Device.mobile?(put_req_header(build_conn(), "user-agent", "Mozilla (Macintosh)"))
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/peggy_web/device_test.exs`
Expected: FAIL — `PeggyWeb.Device` undefined.

- [ ] **Step 3: Create the module**

```elixir
defmodule PeggyWeb.Device do
  @moduledoc """
  Device detection (mobile vs desktop) for routing and template choice.
  The explicit `peggy_view` cookie wins; otherwise we sniff the user-agent.
  """
  import Plug.Conn

  @mobile_ua ~r/Mobile|Android|iPhone|iPod|Opera Mini|IEMobile/i

  @doc "True when the request should render the mobile UI."
  def mobile?(conn) do
    conn = fetch_cookies(conn)

    case conn.cookies["peggy_view"] do
      "mobile" -> true
      "desktop" -> false
      _ -> mobile_ua?(conn)
    end
  end

  @doc "True when the user-agent header looks like a mobile device."
  def mobile_ua?(conn) do
    ua = conn |> get_req_header("user-agent") |> List.first() |> Kernel.||("")
    String.match?(ua, @mobile_ua)
  end
end
```

- [ ] **Step 4: Delegate the plug's UA check** — in `lib/peggy_web/plugs/auto_route_by_device.ex`, replace the private `mobile_ua?/1` function body with a delegation (keeps behavior identical, removes the duplicated regex):

```elixir
  defp mobile_ua?(conn), do: PeggyWeb.Device.mobile_ua?(conn)
```

- [ ] **Step 5: Run tests**

Run: `mix test test/peggy_web/device_test.exs test/peggy_web/plugs 2>/dev/null; mix test test/peggy_web/device_test.exs`
Expected: PASS. Also `mix compile --warnings-as-errors` clean (the plug no longer uses its old regex).

- [ ] **Step 6: Commit**

```bash
git add lib/peggy_web/device.ex lib/peggy_web/plugs/auto_route_by_device.ex test/peggy_web/device_test.exs
git commit -m "Add PeggyWeb.Device.mobile?/1 + delegate AutoRouteByDevice UA check"
```

---

## Task 2: `Locale` plug — cookie + session fallback

**Files:**
- Modify: `lib/peggy_web/locale.ex`
- Test: `test/peggy_web/locale_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule PeggyWeb.LocaleTest do
  use PeggyWeb.ConnCase, async: true

  alias Peggy.Accounts.{Scope, User}

  defp run(conn), do: PeggyWeb.Locale.call(conn, [])

  test "anonymous + peggy_locale cookie uses that locale and stores it in the session" do
    conn =
      build_conn()
      |> Plug.Test.put_req_cookie("peggy_locale", "ms")
      |> Plug.Test.init_test_session(%{})
      |> run()

    assert Gettext.get_locale(PeggyWeb.Gettext) == "ms"
    assert Plug.Conn.get_session(conn, :locale) == "ms"
  end

  test "logged-in user.locale wins over the cookie" do
    conn =
      build_conn()
      |> Plug.Test.put_req_cookie("peggy_locale", "ms")
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.assign(:current_scope, %Scope{user: %User{locale: "zh"}})
      |> run()

    assert Gettext.get_locale(PeggyWeb.Gettext) == "zh"
  end

  test "no user and no cookie falls back to en" do
    conn = build_conn() |> Plug.Test.init_test_session(%{}) |> run()
    assert Gettext.get_locale(PeggyWeb.Gettext) == "en"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/peggy_web/locale_test.exs`
Expected: FAIL — anonymous cookie case returns `en` (no cookie support yet); session assertion fails.

- [ ] **Step 3: Update `lib/peggy_web/locale.ex`**

Replace the whole module body below the moduledoc with:

```elixir
  import Plug.Conn

  @supported ~w(en ms zh)
  @default "en"

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)
    locale = locale_for(conn.assigns[:current_scope], conn.cookies["peggy_locale"])
    Gettext.put_locale(PeggyWeb.Gettext, locale)

    conn
    |> assign(:locale, locale)
    |> put_session(:locale, locale)
  end

  def on_mount(:default, _params, session, socket) do
    locale = locale_for(socket.assigns[:current_scope], session["locale"])
    Gettext.put_locale(PeggyWeb.Gettext, locale)
    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end

  # Precedence: logged-in user's locale, then the request/session fallback
  # (cookie for the plug, session value for LiveView), then the default.
  defp locale_for(%{user: %{locale: l}}, _fallback) when l in @supported, do: l
  defp locale_for(_scope, fallback) when fallback in @supported, do: fallback
  defp locale_for(_scope, _fallback), do: @default
```

(Note: the `on_mount/4` signature changes its 3rd arg from `_session` to `session`. All existing `on_mount` registrations pass session positionally — no caller change needed.)

- [ ] **Step 4: Run tests**

Run: `mix test test/peggy_web/locale_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/peggy_web/locale.ex test/peggy_web/locale_test.exs
git commit -m "Locale plug: peggy_locale cookie fallback + session bridge for LiveView"
```

---

## Task 3: Public `/locale` route + `LocaleController` sets the cookie

**Files:**
- Modify: `lib/peggy_web/router.ex`
- Modify: `lib/peggy_web/controllers/locale_controller.ex`
- Test: `test/peggy_web/controllers/locale_controller_test.exs`

- [ ] **Step 1: Move the route to the public scope** — in `lib/peggy_web/router.ex`:

Remove `get "/locale/:locale", LocaleController, :update` from the authenticated scope (the one with `pipe_through [:browser, :require_authenticated_user, PeggyWeb.Plugs.AutoRouteByDevice]`). Add it to the public scope so anonymous visitors can reach it:

```elixir
  scope "/", PeggyWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/locale/:locale", LocaleController, :update
  end
```

(`/view-mode` stays in the authenticated scope.)

- [ ] **Step 2: Write the failing test** — append to `test/peggy_web/controllers/locale_controller_test.exs`:

```elixir
  test "an anonymous visitor sets the peggy_locale cookie and is redirected", %{} do
    conn =
      build_conn()
      |> put_req_header("referer", "http://localhost:4000/")
      |> get(~p"/locale/zh")

    assert redirected_to(conn) == "/"
    assert conn.resp_cookies["peggy_locale"].value == "zh"
  end

  test "a logged-in user gets both the cookie and a persisted user.locale", %{conn: conn} do
    conn = conn |> put_req_header("referer", "http://localhost:4000/farms") |> get(~p"/locale/ms")
    assert conn.resp_cookies["peggy_locale"].value == "ms"
    assert Peggy.Repo.reload(conn.assigns.current_scope.user).locale == "ms"
  end
```

(The existing `setup` logs in a user, so `%{conn: conn}` is authenticated; the anonymous test builds its own `build_conn()`.)

- [ ] **Step 3: Run test to verify it fails**

Run: `mix test test/peggy_web/controllers/locale_controller_test.exs`
Expected: FAIL — no `peggy_locale` cookie is set yet (and the anonymous case may previously have redirected to login before the route move).

- [ ] **Step 4: Set the cookie in the controller** — in `lib/peggy_web/controllers/locale_controller.ex`, change the matched `update/2` clause to set the cookie before redirecting:

```elixir
  def update(conn, %{"locale" => locale}) when locale in @locales do
    case conn.assigns[:current_scope] do
      %{user: %User{} = user} -> Accounts.update_user_locale(user, locale)
      _ -> :noop
    end

    conn
    |> put_resp_cookie("peggy_locale", locale, max_age: 60 * 60 * 24 * 365, same_site: "Lax")
    |> redirect(to: return_path(conn))
  end
```

(The `update(conn, _params)` fallback clause and `return_path/1`/`safe_path/1` stay as-is.)

- [ ] **Step 5: Run tests**

Run: `mix test test/peggy_web/controllers/locale_controller_test.exs`
Expected: PASS (existing 3 + new 2).

- [ ] **Step 6: Commit**

```bash
git add lib/peggy_web/router.ex lib/peggy_web/controllers/locale_controller.ex test/peggy_web/controllers/locale_controller_test.exs
git commit -m "Make /locale public; LocaleController sets peggy_locale cookie"
```

---

## Task 4: `language_switcher/1` — anonymous mode + active-locale from Gettext

**Files:**
- Modify: `lib/peggy_web/components/layouts.ex`
- Test: `test/peggy_web/live/localization_test.exs`

- [ ] **Step 1: Write the failing test** — append to `test/peggy_web/live/localization_test.exs`:

```elixir
  test "language_switcher renders for anonymous when anonymous: true" do
    html =
      Phoenix.LiveViewTest.render_component(&PeggyWeb.Layouts.language_switcher/1, anonymous: true)

    assert html =~ "Bahasa Malaysia"
    assert html =~ "中文"
    assert html =~ "/locale/ms"
  end

  test "language_switcher renders nothing for anonymous by default" do
    html =
      Phoenix.LiveViewTest.render_component(&PeggyWeb.Layouts.language_switcher/1, current_scope: nil)

    assert html == "" or not (html =~ "/locale/ms")
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/peggy_web/live/localization_test.exs`
Expected: FAIL — `language_switcher` requires `current_scope` / has no `anonymous` attr.

- [ ] **Step 3: Replace `language_switcher/1`** in `lib/peggy_web/components/layouts.ex` with:

```elixir
  @doc "Language picker. Renders for logged-in users, or when `anonymous: true`."
  attr :current_scope, :map, default: nil
  attr :anonymous, :boolean, default: false

  def language_switcher(assigns) do
    assigns = assign(assigns, :current, Gettext.get_locale(PeggyWeb.Gettext))

    ~H"""
    <div
      :if={@anonymous || (@current_scope && @current_scope.user)}
      class="dropdown dropdown-end"
    >
      <div tabindex="0" role="button" class="btn btn-ghost btn-sm gap-1" title={gettext("Language")}>
        <.icon name="hero-language-micro" class="size-4" />
        <span class="hidden sm:inline">{language_label(@current)}</span>
      </div>
      <ul tabindex="0" class="dropdown-content menu bg-base-100 rounded-box z-50 w-44 p-2 shadow">
        <li :for={{code, label} <- language_options()}>
          <.link href={~p"/locale/#{code}"} class={@current == code && "menu-active"}>
            {label}
          </.link>
        </li>
      </ul>
    </div>
    """
  end
```

(Keep `language_options/0` and `language_label/1` as they are. The existing navbar call `<.language_switcher current_scope={@current_scope} />` is unchanged — `anonymous` defaults to `false`, so it still hides for anonymous users on login/register.)

- [ ] **Step 4: Run tests**

Run: `mix test test/peggy_web/live/localization_test.exs`
Expected: PASS (existing switcher/translation tests + the 2 new ones).

- [ ] **Step 5: Commit**

```bash
git add lib/peggy_web/components/layouts.ex test/peggy_web/live/localization_test.exs
git commit -m "language_switcher: anonymous mode; active locale from Gettext"
```

---

## Task 5: Device-detected home + mobile template + desktop switcher

**Files:**
- Modify: `lib/peggy_web/controllers/page_controller.ex`
- Create: `lib/peggy_web/controllers/page_html/home_mobile.html.heex`
- Modify: `lib/peggy_web/controllers/page_html/home.html.heex`
- Test: `test/peggy_web/controllers/page_controller_test.exs`

- [ ] **Step 1: Write the failing test** — replace the contents of `test/peggy_web/controllers/page_controller_test.exs` with:

```elixir
defmodule PeggyWeb.PageControllerTest do
  use PeggyWeb.ConnCase, async: true

  test "desktop home renders the landing with an anonymous language switcher", %{conn: conn} do
    html = conn |> put_req_header("user-agent", "Mozilla (Macintosh)") |> get(~p"/") |> html_response(200)
    assert html =~ "Run your pig farm"
    assert html =~ "Bahasa Malaysia"
    assert html =~ "/locale/zh"
    refute html =~ ~s(id="mobile-home")
  end

  test "mobile visitor gets the mobile home with the switcher", %{conn: conn} do
    html =
      conn
      |> Plug.Test.put_req_cookie("peggy_view", "mobile")
      |> get(~p"/")
      |> html_response(200)

    assert html =~ ~s(id="mobile-home")
    assert html =~ "Run your pig farm"
    assert html =~ "Bahasa Malaysia"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/peggy_web/controllers/page_controller_test.exs`
Expected: FAIL — no anonymous switcher / no mobile template yet.

- [ ] **Step 3: Device-detect in the controller** — in `lib/peggy_web/controllers/page_controller.ex`, change the anonymous branch:

```elixir
  def home(conn, _params) do
    case conn.assigns[:current_scope] do
      %Peggy.Accounts.Scope{user: %Peggy.Accounts.User{} = user} ->
        Phoenix.Controller.redirect(conn, to: PeggyWeb.UserAuth.default_farm_path(user))

      _ ->
        if PeggyWeb.Device.mobile?(conn) do
          render(conn, :home_mobile)
        else
          render(conn, :home)
        end
    end
  end
```

- [ ] **Step 4: Add the anonymous switcher to the desktop home** — in `lib/peggy_web/controllers/page_html/home.html.heex`, immediately after the opening `<Layouts.app flash={@flash} current_scope={@current_scope}>` line, add:

```heex
  <div class="flex justify-end">
    <.language_switcher anonymous={true} />
  </div>
```

- [ ] **Step 5: Create the mobile home** — `lib/peggy_web/controllers/page_html/home_mobile.html.heex`:

```heex
<Layouts.mobile flash={@flash} current_scope={@current_scope}>
  <div id="mobile-home" class="min-h-screen flex flex-col">
    <header class="flex items-center justify-between px-4 py-3 border-b border-base-200">
      <span class="flex items-center gap-2 font-bold text-lg">
        <span class="text-2xl">🐷</span>
        <span>Peggy</span>
      </span>
      <div class="flex items-center gap-2">
        <.language_switcher anonymous={true} />
        <.theme_toggle />
      </div>
    </header>

    <main class="flex-1 px-5 py-8 space-y-8">
      <section class="text-center space-y-3">
        <h1 class="text-3xl font-bold tracking-tight">
          {gettext("Run your pig farm, not your spreadsheet.")}
        </h1>
        <p class="text-base text-base-content/70">
          {gettext(
            "Peggy is a farm management system for swine operations — breeding, health, feed, growth and sales in one place. Built for the desktop office and the barn floor."
          )}
        </p>
      </section>

      <section class="space-y-3">
        <div class="card bg-base-200 p-4">
          <.icon name="hero-identification" class="size-6 text-primary" />
          <h3 class="mt-2 font-semibold">{gettext("Animal registry")}</h3>
        </div>
        <div class="card bg-base-200 p-4">
          <.icon name="hero-calendar-days" class="size-6 text-primary" />
          <h3 class="mt-2 font-semibold">{gettext("Breeding calendar")}</h3>
        </div>
        <div class="card bg-base-200 p-4">
          <.icon name="hero-chart-bar" class="size-6 text-primary" />
          <h3 class="mt-2 font-semibold">{gettext("Reports & KPIs")}</h3>
        </div>
      </section>

      <section class="flex flex-col gap-3 pb-8">
        <.link navigate={~p"/users/register"} class="btn btn-primary btn-block">
          {gettext("Sign up")}
        </.link>
        <.link navigate={~p"/users/log-in"} class="btn btn-ghost btn-block">
          {gettext("Log in")}
        </.link>
      </section>
    </main>
  </div>
</Layouts.mobile>
```

NOTE: confirm the three heroicons exist — `hero-identification` and `hero-calendar-days` are already used by the desktop home; verify `hero-chart-bar` (`ls deps/heroicons/optimized/24/outline/chart-bar.svg`). If missing, use `hero-presentation-chart-line` or another confirmed outline icon. All `gettext(...)` strings here already exist in the desktop home / app, so no new extraction/translation is needed.

- [ ] **Step 6: Run tests**

Run: `mix test test/peggy_web/controllers/page_controller_test.exs`
Expected: PASS (2 tests).

- [ ] **Step 7: Full suite + commit**

Run: `mix precommit`
Expected: 0 failures, no warnings.

```bash
git add lib/peggy_web/controllers/page_controller.ex lib/peggy_web/controllers/page_html/home.html.heex lib/peggy_web/controllers/page_html/home_mobile.html.heex test/peggy_web/controllers/page_controller_test.exs
git commit -m "Device-detected home: mobile template + anonymous language switcher on both"
```

---

## Self-Review

**Spec coverage:**
- Cookie locale + plug precedence + session bridge → Task 2. ✓
- LocaleController sets cookie → Task 3 (plus the required public-route move the spec implied). ✓
- `language_switcher` anonymous mode, active-locale from Gettext, navbar unchanged (home-only) → Task 4. ✓
- `PeggyWeb.Device.mobile?/1` + plug DRY → Task 1. ✓
- PageController device-detect, `home_mobile.html.heex`, desktop home switcher → Task 5. ✓
- Non-goals (no anonymous switcher on login/register; logged-in unchanged; no new translations) — respected: switcher only in home templates; user.locale still wins; mobile home reuses existing msgids. ✓

**Placeholder scan:** none. The only "verify X" is the `hero-chart-bar` icon check in Task 5 with a concrete fallback.

**Type/consistency:** `PeggyWeb.Device.mobile?/1` + `mobile_ua?/1` used consistently (plug delegates to `mobile_ua?/1`, controller uses `mobile?/1`). `locale_for/2` arity consistent between `call` (cookie) and `on_mount` (session). `language_switcher` attrs (`current_scope`, `anonymous`) match the navbar call (`current_scope` only) and home calls (`anonymous: true`). `peggy_locale` cookie name consistent across plug (read) and controller (write). Route `/locale/:locale` → `LocaleController.update` unchanged name, only scope moved.

**Executor watch-outs:**
- `Plug.Test.put_req_cookie/3` and `init_test_session/2` — qualify with `Plug.Test.` (ConnCase imports Plug.Conn + Phoenix.ConnTest, not Plug.Test).
- `%Peggy.Accounts.Scope{user: %Peggy.Accounts.User{locale: ...}}` — confirm both structs build with those fields (they do).
- Confirm `:fetch_session` precedes `PeggyWeb.Locale` in the `:browser` pipeline (it does) so `put_session/3` works.
