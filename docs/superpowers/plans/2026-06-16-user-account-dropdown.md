# User Account Dropdown Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace scattered top-navbar user items (email, language, theme, My farms, Settings, Log out) and farm-sub-nav account items (Members, Settings) with a single sectioned daisyUI dropdown anchored to an avatar-pill trigger button.

**Architecture:** All changes are in `lib/peggy_web/components/layouts.ex`. A new private `user_dropdown/1` component encapsulates the trigger + panel. The `app/1` navbar `<ul>` is simplified to keep only the Mobile switcher + the new dropdown when logged in. The `farm_nav/1` sub-nav loses its Members and Settings links. No new files, no router changes.

**Tech Stack:** Phoenix 1.8 / LiveView 1.1 / HEEx, daisyUI 5, Tailwind v4, Heroicons (`<.icon name="hero-*-micro">`).

---

## File Map

| File | Change |
|------|--------|
| `lib/peggy_web/components/layouts.ex` | Add `user_dropdown/1`, `display_name/1`; update `app/1` navbar `<ul>`; trim `farm_nav/1` |

---

### Task 1: Add `display_name/1` helper and `user_dropdown/1` component

**Files:**
- Modify: `lib/peggy_web/components/layouts.ex` (append before the closing `end` of the module)

Context: `language_options/0` and `theme_toggle/1` are already defined in this file and are called from `user_dropdown/1`. The daisyUI `dropdown dropdown-end` pattern is identical to the Animals and Breeding menus already in `farm_nav/1`.

- [ ] **Step 1: Add `display_name/1` private helper**

Insert just before the final `end` of the module (after `theme_toggle/1`, around line 782):

```elixir
  defp display_name(%{username: u}) when is_binary(u) and u != "", do: u
  defp display_name(%{email: e}), do: e
```

- [ ] **Step 2: Add `user_dropdown/1` private component**

Insert immediately after `display_name/1`, still before the module's closing `end`:

```elixir
  attr :current_scope, :map, required: true

  defp user_dropdown(assigns) do
    assigns = assign(assigns, :current_locale, Gettext.get_locale(PeggyWeb.Gettext))

    ~H"""
    <div class="dropdown dropdown-end">
      <%!-- Trigger pill --%>
      <div
        tabindex="0"
        role="button"
        class="flex items-center gap-2 rounded-full border border-primary/30 bg-primary/10 pl-1 pr-3 py-1 cursor-pointer hover:bg-primary/20 transition-colors"
      >
        <div class="size-7 rounded-full bg-primary flex items-center justify-center text-primary-content text-xs font-bold flex-shrink-0 select-none">
          {String.upcase(String.first(display_name(@current_scope.user)))}
        </div>
        <span class="hidden sm:block text-sm font-medium truncate max-w-[160px]">
          {display_name(@current_scope.user)}
        </span>
        <.icon name="hero-chevron-down-micro" class="size-3 text-base-content/50" />
      </div>

      <%!-- Panel --%>
      <div
        tabindex="0"
        class="dropdown-content z-50 mt-2 w-60 rounded-xl border border-base-300 bg-base-100 shadow-xl"
      >
        <%!-- Header --%>
        <div class="px-4 py-3 border-b border-base-200 bg-base-200/40 rounded-t-xl">
          <div class="flex items-center gap-3">
            <div class="size-9 rounded-full bg-primary flex items-center justify-center text-primary-content text-sm font-bold flex-shrink-0 select-none">
              {String.upcase(String.first(display_name(@current_scope.user)))}
            </div>
            <div class="min-w-0">
              <div class="font-semibold text-sm truncate">{display_name(@current_scope.user)}</div>
              <div :if={@current_scope.farm} class="text-xs text-base-content/50 font-mono truncate">
                {@current_scope.farm.slug}
              </div>
            </div>
          </div>
        </div>

        <%!-- Preferences --%>
        <div class="py-1">
          <p class="px-3 pt-2 pb-1 text-[10px] uppercase tracking-widest text-base-content/40 font-semibold">
            {gettext("Preferences")}
          </p>
          <div class="flex items-center justify-between px-3 py-2">
            <span class="flex items-center gap-2 text-sm">
              <.icon name="hero-language-micro" class="size-4 text-base-content/50" />
              {gettext("Language")}
            </span>
            <div class="flex gap-0.5">
              <.link
                :for={{code, _label} <- language_options()}
                href={~p"/locale/#{code}"}
                class={[
                  "px-1.5 py-0.5 rounded text-xs font-mono",
                  @current_locale == code &&
                    "bg-primary text-primary-content font-semibold",
                  @current_locale != code &&
                    "text-base-content/50 hover:text-base-content hover:bg-base-200"
                ]}
              >
                {String.upcase(code)}
              </.link>
            </div>
          </div>
          <div class="flex items-center justify-between px-3 py-2">
            <span class="flex items-center gap-2 text-sm">
              <.icon name="hero-swatch-micro" class="size-4 text-base-content/50" />
              {gettext("Theme")}
            </span>
            <.theme_toggle />
          </div>
        </div>

        <%!-- Farm --%>
        <div class="border-t border-base-200 py-1">
          <p class="px-3 pt-2 pb-1 text-[10px] uppercase tracking-widest text-base-content/40 font-semibold">
            {gettext("Farm")}
          </p>
          <.link
            navigate={~p"/farms"}
            class="flex items-center gap-2 px-3 py-2 text-sm hover:bg-base-200 rounded transition-colors"
          >
            <.icon name="hero-arrow-right-left-micro" class="size-4 text-base-content/50" />
            {gettext("My farms")}
          </.link>
          <.link
            :if={@current_scope.farm && Peggy.Policy.can?(@current_scope, :view_farm)}
            navigate={~p"/farms/#{@current_scope.farm.slug}/members"}
            class="flex items-center gap-2 px-3 py-2 text-sm hover:bg-base-200 rounded transition-colors"
          >
            <.icon name="hero-users-micro" class="size-4 text-base-content/50" />
            {gettext("Members")}
          </.link>
          <.link
            :if={
              @current_scope.farm &&
                Peggy.Policy.can?(@current_scope, :manage_farm_settings)
            }
            navigate={~p"/farms/#{@current_scope.farm.slug}/settings"}
            class="flex items-center gap-2 px-3 py-2 text-sm hover:bg-base-200 rounded transition-colors"
          >
            <.icon name="hero-cog-6-tooth-micro" class="size-4 text-base-content/50" />
            {gettext("Farm settings")}
          </.link>
        </div>

        <%!-- Account --%>
        <div class="border-t border-base-200 py-1">
          <p class="px-3 pt-2 pb-1 text-[10px] uppercase tracking-widest text-base-content/40 font-semibold">
            {gettext("Account")}
          </p>
          <.link
            navigate={~p"/users/settings"}
            class="flex items-center gap-2 px-3 py-2 text-sm hover:bg-base-200 rounded transition-colors"
          >
            <.icon name="hero-user-circle-micro" class="size-4 text-base-content/50" />
            {gettext("Account settings")}
          </.link>
          <.link
            href={~p"/users/log-out"}
            method="delete"
            class="flex items-center gap-2 px-3 py-2 text-sm text-error hover:bg-error/10 rounded transition-colors"
          >
            <.icon name="hero-arrow-left-on-rectangle-micro" class="size-4" />
            {gettext("Log out")}
          </.link>
        </div>
      </div>
    </div>
    """
  end
```

- [ ] **Step 3: Verify it compiles**

```bash
mix compile --warnings-as-errors 2>&1 | tail -5
```

Expected: `Generated peggy app` with no errors or warnings.

---

### Task 2: Update `app/1` navbar — replace scattered items with dropdown

**Files:**
- Modify: `lib/peggy_web/components/layouts.ex` — the `<ul>` inside `def app(assigns)`

Currently the `<ul class="flex items-center gap-2">` block (lines ~66–111) contains: email text, language switcher, theme toggle, Mobile link, My farms, Settings, Log out (logged-in branch) and Log in, Sign up (logged-out branch).

- [ ] **Step 1: Replace the `<ul>` contents in `app/1`**

Find and replace the entire `<ul class="flex items-center gap-2">…</ul>` block with:

```heex
        <ul class="flex items-center gap-2">
          <%= if @current_scope && @current_scope.user do %>
            <li :if={@current_scope.farm}>
              <.link
                href={~p"/view-mode?#{[mode: "mobile", to: "/m/#{@current_scope.farm.slug}"]}"}
                class="btn btn-ghost btn-sm"
                title={gettext("Mobile view")}
              >
                <.icon name="hero-device-phone-mobile-micro" class="size-4" />
                <span class="hidden sm:inline ml-1">{gettext("Mobile")}</span>
              </.link>
            </li>
            <li>
              <.user_dropdown current_scope={@current_scope} />
            </li>
          <% else %>
            <li><.language_switcher current_scope={@current_scope} anonymous={true} /></li>
            <li><.theme_toggle /></li>
            <li>
              <.link navigate={~p"/users/log-in"} class="btn btn-ghost btn-sm">
                {gettext("Log in")}
              </.link>
            </li>
            <li>
              <.link navigate={~p"/users/register"} class="btn btn-primary btn-sm">
                {gettext("Sign up")}
              </.link>
            </li>
          <% end %>
        </ul>
```

Note: Language switcher and theme toggle remain in the logged-out branch so anonymous users can still change them before signing in.

- [ ] **Step 2: Verify it compiles**

```bash
mix compile --warnings-as-errors 2>&1 | tail -5
```

Expected: `Generated peggy app` with no errors.

---

### Task 3: Trim `farm_nav/1` — remove Members and Settings links

**Files:**
- Modify: `lib/peggy_web/components/layouts.ex` — the `defp farm_nav(assigns)` function

The last two `<.farm_nav_link>` calls (Members and Settings) must be removed. They now live in the user dropdown.

- [ ] **Step 1: Remove the two trailing `farm_nav_link` calls**

Find and delete this block from `farm_nav/1` (currently after the Reports link):

```heex
        <.farm_nav_link
          :if={Peggy.Policy.can?(@current_scope, :view_farm)}
          href={~p"/farms/#{@current_scope.farm.slug}/members"}
          icon="hero-users-micro"
          label={gettext("Members")}
        />
        <.farm_nav_link
          :if={Peggy.Policy.can?(@current_scope, :manage_farm_settings)}
          href={~p"/farms/#{@current_scope.farm.slug}/settings"}
          icon="hero-cog-6-tooth-micro"
          label={gettext("Settings")}
        />
```

The Reports link should now be the last item in `farm_nav/1`'s inner div.

- [ ] **Step 2: Verify it compiles**

```bash
mix compile --warnings-as-errors 2>&1 | tail -5
```

Expected: `Generated peggy app` with no errors.

---

### Task 4: Run full checks, verify visually, commit

**Files:** none — verification only

- [ ] **Step 1: Run precommit**

```bash
mix precommit 2>&1 | tail -10
```

Expected: `642 tests, 0 failures` (or more if tests were added). No compile warnings.

- [ ] **Step 2: Start dev server and visually verify**

```bash
iex -S mix phx.server
```

Open `http://localhost:4000` and check:

1. **Logged out:** top-right shows language + theme + Log in + Sign up. Farm sub-nav not visible.
2. **Logged in, no farm selected** (`/farms`): avatar pill shows username (or email fallback). Dropdown opens: Preferences (language as EN/MS/ZH pills, theme toggle), Farm (only "My farms"), Account (Account settings, Log out). Farm sub-nav not visible.
3. **Logged in, on a farm** (`/farms/:slug`): avatar pill shows username/email. Dropdown Farm section shows My farms + Members (if permitted) + Farm settings (if permitted). Farm sub-nav shows Dashboard, Locations, Animals, Breeding, Reports — **no** Members or Settings links.
4. **Language links:** clicking EN/MS/ZH redirects to `/locale/:code` and the active code is highlighted.
5. **Theme toggle:** three-button pill inside dropdown still works.
6. **Log out:** clicking closes session and redirects to login.

- [ ] **Step 3: Commit**

```bash
git add lib/peggy_web/components/layouts.ex
git commit -m "$(cat <<'EOF'
feat: consolidate nav into user account dropdown

Replaces scattered top-navbar items (email, language, theme, My farms,
Settings, Log out) and farm-sub-nav Members/Settings with a single
sectioned daisyUI dropdown anchored to an avatar-pill trigger. Trigger
shows username with email fallback. Dropdown groups: Preferences
(language as inline locale pills, theme toggle), Farm (My farms,
Members, Farm settings — permission-gated), Account (Account settings,
Log out).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

Expected: commit succeeds, `mix precommit` already passed so no hook failures.
