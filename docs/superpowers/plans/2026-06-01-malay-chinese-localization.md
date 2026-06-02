# Malay & Chinese Localization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the app usable in Bahasa Malaysia (`ms`) and Simplified Chinese (`zh`), with a logged-in language switcher beside the theme toggle.

**Architecture:** The locale plumbing already exists (`PeggyWeb.Locale` reads `user.locale`; config lists `en ms zh`). We refresh+translate the gettext PO files and add a `LocaleController` (mirroring `ViewModeController`) plus a `language_switcher` component. Switching persists to `user.locale` and redirects (full page reload) so everything re-renders translated.

**Tech Stack:** Elixir, Phoenix LiveView 1.1, Gettext, daisyUI 5, ExUnit.

Spec: `docs/superpowers/specs/2026-06-01-malay-chinese-localization-design.md`.

---

## File Structure

- Modify `priv/gettext/{en,ms,zh}/LC_MESSAGES/{default,errors}.po` — refreshed msgids; `ms`/`zh` translated.
- Modify `lib/peggy/accounts/user.ex` — add `locale_changeset/2`.
- Modify `lib/peggy/accounts.ex` — add `update_user_locale/2`.
- Create `lib/peggy_web/controllers/locale_controller.ex` — `LocaleController.update/2`.
- Modify `lib/peggy_web/router.ex` — `get "/locale/:locale"` route.
- Modify `lib/peggy_web/components/layouts.ex` — `language_switcher/1` component + render in desktop navbar (near line 53) and mobile "More" sheet (near line 273).
- Create `test/peggy_web/controllers/locale_controller_test.exs`.
- Modify `test/peggy/accounts_test.exs` — `update_user_locale/2` tests.
- Create `test/peggy_web/live/localization_test.exs` — switcher render + translated-string render.

Run `mix precommit` before each commit unless the task says otherwise.

---

## Task 1: Refresh the gettext PO files

Re-extract all current strings and merge into every locale (English behavior unchanged; new `ms`/`zh` entries get empty msgstr → English fallback).

**Files:** Modifies `priv/gettext/**/*.po` and `priv/gettext/*.pot`.

- [ ] **Step 1: Run extract + merge**

Run: `mix gettext.extract --merge`
Expected: writes `priv/gettext/default.pot`, `priv/gettext/errors.pot`, and merges into `en/ms/zh` `default.po`/`errors.po`. The `ms`/`zh` `default.po` should now contain ~900+ msgids (up from 98).

- [ ] **Step 2: Verify nothing broke (English unchanged)**

Run: `mix precommit`
Expected: 0 failures, no warnings. (English still renders via msgid; empty `ms`/`zh` msgstr fall back to English.)

- [ ] **Step 3: Confirm headers**

Run: `grep "Plural-Forms" priv/gettext/ms/LC_MESSAGES/default.po priv/gettext/zh/LC_MESSAGES/default.po`
Expected: each shows `nplurals=1; plural=0;`. If a merged file lost this (shows `nplurals=2`), set it back to `nplurals=1; plural=0;` for `ms` and `zh`.

- [ ] **Step 4: Commit**

```bash
git add priv/gettext
git commit -m "Refresh gettext PO files (extract --merge) for ms/zh"
```

---

## Task 2: `Accounts.update_user_locale/2`

A narrow changeset that updates only `locale` (decoupled from the timezone-requiring `profile_changeset`).

**Files:**
- Modify: `lib/peggy/accounts/user.ex`
- Modify: `lib/peggy/accounts.ex`
- Test: `test/peggy/accounts_test.exs`

- [ ] **Step 1: Write the failing test** (append inside the existing `Peggy.AccountsTest` module)

```elixir
  describe "update_user_locale/2" do
    test "sets a supported locale" do
      user = user_fixture()
      assert {:ok, updated} = Peggy.Accounts.update_user_locale(user, "ms")
      assert updated.locale == "ms"
    end

    test "rejects an unsupported locale" do
      user = user_fixture()
      assert {:error, changeset} = Peggy.Accounts.update_user_locale(user, "xx")
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).locale
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/peggy/accounts_test.exs`
Expected: FAIL — `update_user_locale/2` undefined.

- [ ] **Step 3: Add `locale_changeset/2` to `user.ex`** (next to `profile_changeset/2`)

```elixir
  @doc "Changeset for just the UI locale (no timezone coupling)."
  def locale_changeset(user, attrs) do
    user
    |> cast(attrs, [:locale])
    |> validate_required([:locale])
    |> validate_inclusion(:locale, ~w(en ms zh))
  end
```

- [ ] **Step 4: Add `update_user_locale/2` to `accounts.ex`** (near `update_user_password/2`)

```elixir
  @doc "Updates a user's UI locale. Returns `{:ok, user}` or `{:error, changeset}`."
  def update_user_locale(%User{} = user, locale) do
    user
    |> User.locale_changeset(%{locale: locale})
    |> Repo.update()
  end
```

(Confirm `alias Peggy.Accounts.User` and `alias Peggy.Repo` already exist at the top of `accounts.ex`; they do.)

- [ ] **Step 5: Run test to verify it passes**

Run: `mix test test/peggy/accounts_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/peggy/accounts/user.ex lib/peggy/accounts.ex test/peggy/accounts_test.exs
git commit -m "Add Accounts.update_user_locale/2 + User.locale_changeset/2"
```

---

## Task 3: `LocaleController` + route

`GET /locale/:locale` updates the logged-in user's locale and redirects back to the referring page (open-redirect-guarded). Mirrors `ViewModeController`.

**Files:**
- Create: `lib/peggy_web/controllers/locale_controller.ex`
- Modify: `lib/peggy_web/router.ex`
- Test: `test/peggy_web/controllers/locale_controller_test.exs`

- [ ] **Step 1: Add the route** in `lib/peggy_web/router.ex` next to `get "/view-mode", ViewModeController, :set` (line ~54):

```elixir
    get "/locale/:locale", LocaleController, :update
```

- [ ] **Step 2: Write the failing test**

```elixir
defmodule PeggyWeb.LocaleControllerTest do
  use PeggyWeb.ConnCase, async: true

  import Peggy.AccountsFixtures

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  test "updates the user's locale and redirects to the referring path", %{conn: conn} do
    conn =
      conn
      |> put_req_header("referer", "http://localhost:4000/farms?x=1")
      |> get(~p"/locale/ms")

    assert redirected_to(conn) == "/farms?x=1"
    assert Peggy.Repo.reload(conn.assigns.current_scope.user).locale == "ms"
  end

  test "ignores an unsupported locale", %{conn: conn} do
    conn = conn |> put_req_header("referer", "http://localhost:4000/farms") |> get(~p"/locale/xx")
    assert redirected_to(conn) == "/farms"
    assert Peggy.Repo.reload(conn.assigns.current_scope.user).locale == "en"
  end

  test "falls back to / for an external referer (no open redirect)", %{conn: conn} do
    conn = conn |> put_req_header("referer", "https://evil.example.com/farms") |> get(~p"/locale/ms")
    assert redirected_to(conn) == "/"
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `mix test test/peggy_web/controllers/locale_controller_test.exs`
Expected: FAIL — `LocaleController` undefined.

- [ ] **Step 4: Create the controller**

```elixir
defmodule PeggyWeb.LocaleController do
  @moduledoc """
  Persists the logged-in user's UI locale and redirects back to the
  referring page, so `PeggyWeb.Locale` re-applies it on the next request.
  Mirrors `PeggyWeb.ViewModeController`.
  """
  use PeggyWeb, :controller

  alias Peggy.Accounts
  alias Peggy.Accounts.User

  @locales ~w(en ms zh)

  def update(conn, %{"locale" => locale}) when locale in @locales do
    case conn.assigns[:current_scope] do
      %{user: %User{} = user} -> Accounts.update_user_locale(user, locale)
      _ -> :noop
    end

    redirect(conn, to: return_path(conn))
  end

  def update(conn, _params), do: redirect(conn, to: return_path(conn))

  # Only redirect to internal paths; preserve the query string.
  defp return_path(conn) do
    conn |> get_req_header("referer") |> List.first() |> safe_path()
  end

  defp safe_path(referer) when is_binary(referer) do
    uri = URI.parse(referer)
    path = uri.path || "/"

    if String.starts_with?(path, "/") and not String.starts_with?(path, "//") do
      path <> if(uri.query, do: "?" <> uri.query, else: "")
    else
      ~p"/"
    end
  end

  defp safe_path(_), do: ~p"/"
end
```

- [ ] **Step 5: Run test to verify it passes**

Run: `mix test test/peggy_web/controllers/locale_controller_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/peggy_web/controllers/locale_controller.ex lib/peggy_web/router.ex test/peggy_web/controllers/locale_controller_test.exs
git commit -m "Add LocaleController + /locale/:locale route"
```

---

## Task 4: `language_switcher` component in both layouts

**Files:**
- Modify: `lib/peggy_web/components/layouts.ex`
- Test: `test/peggy_web/live/localization_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule PeggyWeb.LocalizationTest do
  use PeggyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Peggy.AccountsFixtures

  test "language switcher shows the three languages for a logged-in user", %{conn: conn} do
    {:ok, _lv, html} = conn |> log_in_user(user_fixture()) |> live(~p"/farms")
    assert html =~ "Bahasa Malaysia"
    assert html =~ "中文"
    assert html =~ "/locale/ms"
    assert html =~ "/locale/zh"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/peggy_web/live/localization_test.exs`
Expected: FAIL — switcher not rendered.

- [ ] **Step 3: Add the component** to `lib/peggy_web/components/layouts.ex` (place near `theme_toggle/1`, around line 670)

```elixir
  @doc "Language picker; persists to user.locale via LocaleController. Logged-in only."
  attr :current_scope, :map, required: true

  def language_switcher(assigns) do
    ~H"""
    <div :if={@current_scope && @current_scope.user} class="dropdown dropdown-end">
      <div tabindex="0" role="button" class="btn btn-ghost btn-sm gap-1" title={gettext("Language")}>
        <.icon name="hero-language-micro" class="size-4" />
        <span class="hidden sm:inline">{language_label(@current_scope.user.locale)}</span>
      </div>
      <ul tabindex="0" class="dropdown-content menu bg-base-100 rounded-box z-50 w-44 p-2 shadow">
        <li :for={{code, label} <- language_options()}>
          <.link href={~p"/locale/#{code}"} class={@current_scope.user.locale == code && "menu-active"}>
            {label}
          </.link>
        </li>
      </ul>
    </div>
    """
  end

  defp language_options, do: [{"en", "English"}, {"ms", "Bahasa Malaysia"}, {"zh", "中文"}]

  defp language_label(code) do
    {_, label} = Enum.find(language_options(), {code, code}, fn {c, _} -> c == code end)
    label
  end
```

Note: confirm `hero-language-micro` exists (`ls deps/heroicons/optimized/16/solid/language.svg`). If not, use `hero-globe-alt-micro`.

- [ ] **Step 4: Render it in the desktop navbar** — in the `app/1` function, the `<li><.theme_toggle /></li>` (around line 53) becomes:

```elixir
          <li><.language_switcher current_scope={@current_scope} /></li>
          <li><.theme_toggle /></li>
```

- [ ] **Step 5: Render it in the mobile "More" sheet** — in `mobile_more_sheet/1`, right after the Theme `<li>...</li>` block (around line 273, the one containing `<.theme_toggle />`), add:

```elixir
          <li class="flex items-center justify-between gap-3 px-4 py-3">
            <span class="flex items-center gap-3">
              <.icon name="hero-language" class="size-5 text-base-content/60" />
              <span>{gettext("Language")}</span>
            </span>
            <.language_switcher current_scope={@current_scope} />
          </li>
```

- [ ] **Step 6: Run test to verify it passes**

Run: `mix test test/peggy_web/live/localization_test.exs`
Expected: PASS.

- [ ] **Step 7: Full suite + commit**

Run: `mix precommit`
Expected: 0 failures, no warnings.

```bash
git add lib/peggy_web/components/layouts.ex test/peggy_web/live/localization_test.exs
git commit -m "Add language switcher to desktop navbar and mobile More sheet"
```

After this task the switcher works end-to-end; untranslated strings still show English.

---

## Task 5: Translate `ms` default.po

This is a **content task**: fill EVERY empty `msgstr` in `priv/gettext/ms/LC_MESSAGES/default.po` with Bahasa Malaysia, using the spec's locked glossary. Rules below are mandatory.

**Translation rules:**
- **Preserve interpolations verbatim:** every `%{name}` in the msgid must appear unchanged in the msgstr. Example: `msgid "%{n} animals on farm"` → `msgstr "%{n} ekor babi di ladang"`.
- **Match the msgid's capitalization style** (UI label Title Case vs sentence case).
- **Use the glossary** (Babi Ibu, Beranak, Cerai susu, Kebuntingan, Kawin, Kandang, Bangsal, Singkir, Paliti, Kawanan, Pergerakan, etc.).
- **Leave no `#, fuzzy` flags** — remove any.
- If a msgid is a pure interpolation/format with no translatable words, copy it unchanged.

**Files:**
- Modify: `priv/gettext/ms/LC_MESSAGES/default.po`
- Test: `test/peggy_web/live/localization_test.exs`

- [ ] **Step 1: Write a failing test** locking representative translations (append to `localization_test.exs`)

```elixir
  describe "ms translations" do
    test "core strings are translated" do
      assert t("ms", "Cancel") == "Batal"
      assert t("ms", "Save") == "Simpan"
      assert t("ms", "Reports") == "Laporan"
      assert t("ms", "Settings") == "Tetapan"
      assert t("ms", "Breeding") == "Pembiakan"
      assert t("ms", "Language") == "Bahasa"
    end
  end

  defp t(locale, msgid) do
    Gettext.with_locale(PeggyWeb.Gettext, locale, fn -> Gettext.gettext(PeggyWeb.Gettext, msgid) end)
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/peggy_web/live/localization_test.exs`
Expected: FAIL — these msgstr are empty (returns the English msgid).

- [ ] **Step 3: Fill the PO file**

Translate every entry in `priv/gettext/ms/LC_MESSAGES/default.po`. The six strings the test pins must be exactly: `Cancel→Batal`, `Save→Simpan`, `Reports→Laporan`, `Settings→Tetapan`, `Breeding→Pembiakan`, `Language→Bahasa`. Worked examples for format/consistency:

```
msgid "Dashboard"
msgstr "Papan Pemuka"

msgid "Animals"
msgstr "Ternakan"

msgid "Tasks"
msgstr "Tugasan"

msgid "Sows due to farrow (≤7d)"
msgstr "Babi Ibu hampir beranak (≤7h)"

msgid "%{n} animals on farm, %{p} piglets nursing"
msgstr "%{n} ekor babi di ladang, %{p} anak babi menyusu"

msgid "Mark for cull"
msgstr "Tanda untuk singkir"
```

Translate ALL remaining entries the same way.

- [ ] **Step 4: Compile + run test**

Run: `mix compile --warnings-as-errors && mix test test/peggy_web/live/localization_test.exs`
Expected: clean compile (PO parses), tests PASS.

- [ ] **Step 5: Commit**

```bash
git add priv/gettext/ms/LC_MESSAGES/default.po test/peggy_web/live/localization_test.exs
git commit -m "Translate ms default.po (Bahasa Malaysia)"
```

---

## Task 6: Translate `zh` default.po

Same as Task 5 for Simplified Chinese in `priv/gettext/zh/LC_MESSAGES/default.po`. Same rules (preserve `%{...}`, no fuzzy, glossary: 母猪/公猪/分娩/断奶/怀孕/配种/胎次/淘汰/猪舍/栏/移动/猪场/猪群…).

**Files:**
- Modify: `priv/gettext/zh/LC_MESSAGES/default.po`
- Test: `test/peggy_web/live/localization_test.exs`

- [ ] **Step 1: Write a failing test** (append)

```elixir
  describe "zh translations" do
    test "core strings are translated" do
      assert t("zh", "Cancel") == "取消"
      assert t("zh", "Save") == "保存"
      assert t("zh", "Reports") == "报告"
      assert t("zh", "Settings") == "设置"
      assert t("zh", "Breeding") == "繁殖"
      assert t("zh", "Language") == "语言"
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/peggy_web/live/localization_test.exs`
Expected: FAIL.

- [ ] **Step 3: Fill the PO file**

Translate every entry in `priv/gettext/zh/LC_MESSAGES/default.po`. Pinned strings exactly: `Cancel→取消`, `Save→保存`, `Reports→报告`, `Settings→设置`, `Breeding→繁殖`, `Language→语言`. Worked examples:

```
msgid "Dashboard"
msgstr "仪表板"

msgid "Animals"
msgstr "猪只"

msgid "Tasks"
msgstr "任务"

msgid "Sows due to farrow (≤7d)"
msgstr "临近分娩的母猪（≤7天）"

msgid "%{n} animals on farm, %{p} piglets nursing"
msgstr "农场有 %{n} 头猪，%{p} 头仔猪哺乳中"

msgid "Mark for cull"
msgstr "标记淘汰"
```

Translate ALL remaining entries.

- [ ] **Step 4: Compile + run test**

Run: `mix compile --warnings-as-errors && mix test test/peggy_web/live/localization_test.exs`
Expected: clean compile, PASS.

- [ ] **Step 5: Commit**

```bash
git add priv/gettext/zh/LC_MESSAGES/default.po test/peggy_web/live/localization_test.exs
git commit -m "Translate zh default.po (Simplified Chinese)"
```

---

## Task 7: Translate errors.po (ms + zh)

The `errors` domain holds Ecto/validation messages (e.g. "can't be blank", "is invalid", "has already been taken", "must be greater than %{number}"). Translate both `priv/gettext/ms/LC_MESSAGES/errors.po` and `priv/gettext/zh/LC_MESSAGES/errors.po`. Note these contain `ngettext` plural entries — `ms`/`zh` have `nplurals=1`, so fill `msgstr[0]` only, preserving `%{count}`.

**Files:**
- Modify: `priv/gettext/ms/LC_MESSAGES/errors.po`, `priv/gettext/zh/LC_MESSAGES/errors.po`
- Test: `test/peggy_web/live/localization_test.exs`

- [ ] **Step 1: Write a failing test** (append; uses `dgettext` for the errors domain)

```elixir
  describe "error-domain translations" do
    test "common validation messages are translated" do
      assert de("ms", "can't be blank") == "tidak boleh kosong"
      assert de("zh", "can't be blank") == "不能为空"
      assert de("ms", "is invalid") == "tidak sah"
      assert de("zh", "is invalid") == "无效"
    end
  end

  defp de(locale, msgid) do
    Gettext.with_locale(PeggyWeb.Gettext, locale, fn ->
      Gettext.dgettext(PeggyWeb.Gettext, "errors", msgid)
    end)
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/peggy_web/live/localization_test.exs`
Expected: FAIL.

- [ ] **Step 3: Fill both errors.po files**

Translate every entry. Pinned: ms `can't be blank→tidak boleh kosong`, `is invalid→tidak sah`; zh `can't be blank→不能为空`, `is invalid→无效`. For plural entries keep only `msgstr[0]` populated, e.g. ms:

```
msgid "should have %{count} item(s)"
msgid_plural "should have %{count} item(s)"
msgstr[0] "patut ada %{count} item"
```

and zh `msgstr[0] "应有 %{count} 项"`. Preserve every `%{count}`/`%{number}`/`%{...}`.

- [ ] **Step 4: Compile + run test**

Run: `mix compile --warnings-as-errors && mix test test/peggy_web/live/localization_test.exs`
Expected: clean compile, PASS.

- [ ] **Step 5: Commit**

```bash
git add priv/gettext/ms/LC_MESSAGES/errors.po priv/gettext/zh/LC_MESSAGES/errors.po test/peggy_web/live/localization_test.exs
git commit -m "Translate errors.po for ms + zh"
```

---

## Task 8: End-to-end locale rendering + final verification

Confirm a user's `locale` actually changes the rendered page.

**Files:**
- Test: `test/peggy_web/live/localization_test.exs`

- [ ] **Step 1: Write the test** (append)

```elixir
  test "a user with locale ms sees translated chrome", %{conn: conn} do
    user = user_fixture()
    {:ok, _} = Peggy.Accounts.update_user_locale(user, "ms")
    {:ok, _lv, html} = conn |> log_in_user(user) |> live(~p"/farms")
    assert html =~ "Pembiakan" or html =~ "Tetapan" or html =~ "Laporan"
  end
```

NOTE: assert on a string that actually appears on the `/farms` page after translation. If none of `Pembiakan`/`Tetapan`/`Laporan` appear on `/farms`, pick a visible translated label that does (inspect the rendered `html`) and assert that instead — the point is to prove the on_mount locale + PO translation render together.

- [ ] **Step 2: Run test**

Run: `mix test test/peggy_web/live/localization_test.exs`
Expected: PASS.

- [ ] **Step 3: Final full verification**

Run: `mix precommit`
Expected: 0 failures, no warnings, formatted.

- [ ] **Step 4: Commit**

```bash
git add test/peggy_web/live/localization_test.exs
git commit -m "Verify end-to-end locale rendering"
```

---

## Self-Review

**Spec coverage:**
- Refresh PO files (extract --merge) → Task 1. ✓
- Translate ms/zh default + errors → Tasks 5, 6, 7. ✓
- Switcher: controller + route, persists to user.locale, redirect, open-redirect guard → Tasks 2, 3. ✓
- Switcher UI beside theme toggle in both layouts, logged-in only → Task 4. ✓
- Interpolation preserved, no fuzzy, nplurals=1 plurals → rules in Tasks 5–7. ✓
- Glossary (incl. Babi Ibu, 移动) → referenced in translation tasks. ✓
- Non-goals (anonymous switching, hardcoded sweep) — correctly absent. ✓

**Placeholder note:** Tasks 5–7 are content-generation (translate ~931 strings); the plan can't inline the full corpus, so it specifies the exact rules, glossary, pinned test strings, and worked examples, with `mix compile` (PO validity) + pinned-string tests as gates. Task 8 Step 1 contains an explicit "pick a visible string if these don't appear" instruction — the implementer must verify the asserted string is actually on `/farms`.

**Type consistency:** `update_user_locale/2`, `User.locale_changeset/2`, `language_switcher/1` (attr `current_scope`), `language_options/0`, `LocaleController.update/2`, route `/locale/:locale` — names used consistently across tasks. The switcher links (`~p"/locale/#{code}"`) require the Task 3 route, which precedes Task 4. ✓

**Executor watch-outs:**
- Confirm `hero-language-micro` exists; else `hero-globe-alt-micro` (Task 4 Step 3).
- `Peggy.Repo.reload/1` returns the freshly-loaded struct (used in the controller test); if unavailable, use `Peggy.Accounts.get_user!/1` or `Repo.get!(User, id)`.
- `mix gettext.extract --merge` may reformat `en` PO files too — that's fine, commit them.
- Verify `user_fixture/0` creates a user with `locale: "en"` (default) — the invalid-locale and e2e tests assume it.
