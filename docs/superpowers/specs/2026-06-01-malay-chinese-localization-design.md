# Malay & Chinese localization — design

Date: 2026-06-01
Status: approved design, pre-implementation

## Goal

Make the app fully usable in **Bahasa Malaysia (`ms`)** and **Simplified Chinese
(`zh`)** in addition to English, and give logged-in users a way to switch.

## Current state (already built)

- Gettext backend `PeggyWeb.Gettext`; `config :peggy, PeggyWeb.Gettext, locales: ~w(en ms zh), default_locale: "en"`.
- `PeggyWeb.Locale` plug + LiveView `on_mount` — already wired into the router pipelines; sets the Gettext locale from `current_scope.user.locale`, falling back to `en`.
- `users.locale` field (default `"en"`, validated to `~w(en ms zh)`), with a profile changeset.
- `priv/gettext/{en,ms,zh}/LC_MESSAGES/{default,errors}.po` exist.

## What's missing (this project)

1. **PO files are stale + empty.** Only 98 msgids captured (app now has ~931 unique translatable strings); `ms`/`zh` have 0 filled translations.
2. **No language switcher UI** — `user.locale` is read but never writable by users.

## Scope

In: refresh PO files, translate all `ms` + `zh` entries (default + errors domains), add a logged-in language switcher. Out (non-goals): switching language on anonymous pages (login/registration stay English), sweeping for hardcoded non-`gettext` strings, RTL, locale-specific number/date/currency formatting beyond what gettext already does.

## Architecture

### 1. Refresh PO files

Run `mix gettext.extract --merge`. This rewrites `default.pot`/`errors.pot` from the current `gettext/3`, `dgettext/3`, `ngettext/4` calls and merges new msgids into all three locales' PO files (empty msgstr for new entries). No behavior change — untranslated strings fall back to the English msgid.

### 2. Translate

Fill every `msgstr` in `priv/gettext/ms/LC_MESSAGES/{default,errors}.po` and
`priv/gettext/zh/LC_MESSAGES/{default,errors}.po`. `en` PO files keep empty
msgstr (msgid is already English). Rules:

- **Interpolations preserved verbatim:** `%{count}`, `%{tag}`, `%{slug}`, etc. must appear unchanged in the translation. A translation that drops/renames a binding breaks rendering.
- **Plurals:** `ngettext` entries use `msgstr[0]`/`msgstr[1]`. `ms` and `zh` have **one** plural form (`nplurals=1`); the merged PO headers must reflect each locale's `Plural-Forms`. Fill the single form.
- **Capitalization follows the msgid** (a sentence-case msgid → sentence-case translation; a Title-Case label → matching case), not the glossary's canonical form.
- **No `#, fuzzy` flags** left in the committed PO files (remove or resolve), so translations actually apply.
- Glossary terms (below) used consistently for the domain vocabulary.

### 3. Language switcher

Mirror the existing `PeggyWeb.ViewModeController` (which toggles desktop/mobile via a redirect):

- **Route:** `get "/locale/:locale", LocaleController, :update` (in the authenticated scope, alongside `/view-mode`).
- **`PeggyWeb.LocaleController.update/2`:** if `locale in ~w(en ms zh)` and a user is logged in, update that user's `locale` via the profile changeset (`Accounts.update_user_locale/2` or the existing profile update), then redirect back to the `redirect_to` param (falling back to `/`). Invalid locale → ignore, redirect back. **Open-redirect guard:** only redirect to a local path (must start with a single `/`, not `//` or a scheme); otherwise fall back to `/`. The redirect makes `PeggyWeb.Locale` re-run on the next request so the whole page re-renders translated.
- **Switcher UI:** a daisyUI dropdown showing the current language with options English / Bahasa Malaysia / 中文, each linking to `~p"/locale/#{code}?redirect_to=<current path>"`. Rendered **only when `@current_scope.user` is present**, placed beside the theme toggle in:
  - the desktop navbar (`PeggyWeb.Layouts.app`), and
  - the mobile "More" sheet (`mobile_more_sheet` in `layouts.ex`).
- A small shared component (e.g. `language_switcher/1` in `core_components.ex` or `layouts.ex`) renders it in both places.

### 4. Testing

- `LocaleController`: a logged-in user hitting `/locale/ms` has `user.locale == "ms"` persisted and is redirected to `redirect_to`; an invalid locale leaves it unchanged.
- Locale application: a user with `locale: "ms"` loading a page sees a known **translated** string (pick one we translate, e.g. the dashboard "This week" → its `ms` translation), confirming the on_mount + PO wiring works end-to-end.
- Switcher renders: the dropdown (with "Bahasa Malaysia"/"中文") appears for a logged-in user in the desktop layout; absent when not logged in.
- `mix precommit` green; the app compiles the PO files without gettext errors.

## Locked glossary

Canonical domain vocabulary (capitalization adapts per string). Corrected per review: **Sow = Babi Ibu**, **Movement = 移动**.

| English | Bahasa Malaysia | 简体中文 |
|---|---|---|
| Sow | Babi Ibu | 母猪 |
| Boar | Babi jantan | 公猪 |
| Gilt | Babi dara | 后备母猪 |
| Piglet | Anak babi | 仔猪 |
| Weaner | Babi cerai susu | 断奶仔猪 |
| Grower | Babi membesar | 生长猪 |
| Finisher | Babi akhir | 育肥猪 |
| Farrowing | Beranak | 分娩 |
| Weaning | Cerai susu | 断奶 |
| Gestation | Kebuntingan | 怀孕 |
| Service / mating | Kawin | 配种 |
| Heat / oestrus | Berahi | 发情 |
| Parity | Paliti | 胎次 |
| Cull | Singkir | 淘汰 |
| Litter | Sekandang anak | 窝 |
| Born alive | Lahir hidup | 活产 |
| Stillborn | Lahir mati | 死产 |
| Mummified | Janin kering | 木乃伊胎 |
| Abortion | Keguguran | 流产 |
| Fostering | Tukar anak | 寄养 |
| Pen | Kandang | 栏 |
| House / barn | Bangsal | 猪舍 |
| Breeding | Pembiakan | 繁殖 |
| Lactating | Menyusu | 哺乳 |
| Dry (sow) | Kering | 空怀 |
| Open (sow) | Belum bunting | 未配 |
| Served | Telah dikawin | 已配种 |
| Herd | Kawanan | 猪群 |
| Farm | Ladang | 猪场 |
| Movement | Pergerakan | 移动 |

## Decomposition

The translation is large (~931 strings × 2 locales + errors domain). The implementation plan will chunk it: (a) extract/merge + switcher infra (controller, route, component, tests) first — a working, testable slice with English unchanged; (b) translate `ms` default.po; (c) `zh` default.po; (d) errors.po for both. Each chunk compiles and is independently verifiable.
