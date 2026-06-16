# Mobile Invitation Flows

**Date:** 2026-06-16
**Status:** Approved

## Goal

Two new mobile-optimized flows:

1. **Worker acceptance** — a phone-first invitation acceptance page at `/m/invitations/:token` (currently the desktop page at `/invitations/:token` is shown to mobile users; it works but is not optimized for small screens).
2. **Manager invite session** — mobile QR code page at `/m/:farm_slug/invite-session/:role` so a manager can generate a scannable QR code from their own phone while standing in the barn.

Entry point for both: a new "Invite workers" item in the mobile More sheet (visible to managers and owners only).

---

## Approach

Dedicated mobile LiveViews + auto-routing (Approach A from brainstorming).

**No shared template between desktop and mobile.** Each side has its own LiveView so they can be tuned independently without responsive-class compromise.

**Auto-routing:** `AutoRouteByDevice` is extended to redirect mobile users landing on `/invitations/:token` to `/m/invitations/:token`, and desktop users on `/m/invitations/:token` back to `/invitations/:token`.

---

## Flow Diagrams

### Worker flow

```
Phone opens /invitations/:token
    └─► AutoRouteByDevice (mobile UA, no cookie)
        └─► redirect to /m/invitations/:token
            └─► MobileLive.InvitationShow (mode: :choose)
                ├─► "Create account & join" → mode: :create
                │       form POST → /m/invitations/:token/accept
                │       InvitationController.mobile_accept/2
                │       → redirect to /m/:slug (success)
                │       → redirect to /m/invitations/:token (error)
                └─► "Log in & join" → mode: :login
                        form POST → /m/invitations/:token/accept
                        InvitationController.mobile_accept/2
                        → same success / error
```

If the user **is already logged in** (has `current_scope`), they skip the mode picker and see a single "Accept invitation" button instead.

### Manager flow

```
Mobile More sheet → "Invite workers" (li, visible if Policy.can?(:invite_member))
    └─► navigate to /m/:slug/invite-session/worker
        └─► MobileLive.InviteSession
            - role selector (Worker / Vet pills — navigates to new URL)
            - large QR code (links to /invitations/:token — auto-routed for phone scanners)
            - live member roster (PubSub "farm:ID:members")
            - "Close session" button
```

---

## File Map

| File | Change |
|------|--------|
| `lib/peggy_web/components/layouts.ex` | Add `mobile_standalone/1`; add "Invite workers" li to `mobile_more_sheet` |
| `lib/peggy_web/router.ex` | Add 3 entries: mobile invitation LiveView, mobile invite session LiveView, mobile accept POST |
| `lib/peggy_web/plugs/auto_route_by_device.ex` | Extend `call/2` to swap `/invitations/:token` ↔ `/m/invitations/:token` by device |
| `lib/peggy_web/controllers/invitation_controller.ex` | Add `mobile_accept/2` action (same logic, redirects to `/m/` paths) |
| `lib/peggy_web/live/mobile_live/invitation_show.ex` | New file — worker acceptance LiveView |
| `lib/peggy_web/live/mobile_live/invite_session.ex` | New file — manager QR session LiveView |

---

## Design Details

### 1. `Layouts.mobile_standalone/1`

New layout function added to `lib/peggy_web/components/layouts.ex`. Used by `MobileLive.InvitationShow` only — the user is not yet a farm member so `Layouts.mobile_app` (which requires a farm scope and bottom tabs) is inappropriate.

```heex
def mobile_standalone(assigns) do
  ~H"""
  <.flash_group flash={@flash} />
  <div class="min-h-screen bg-base-200 flex flex-col items-center justify-center p-6 gap-6">
    <div class="text-2xl font-bold tracking-tight">Peggy</div>
    {@inner_content}
  </div>
  """
end
```

Peggy wordmark, no navigation, content centered vertically. Transparent to locale/flash.

---

### 2. `MobileLive.InvitationShow`

**Route:** `live "/m/invitations/:token", MobileLive.InvitationShow, :show` (in `:current_user` live_session, same scope as the desktop `/invitations/:token`).

**Mount assigns:**
- `token` — raw encoded token from params
- `invitation` — loaded via `Farms.get_invitation_by_encoded_token/1`; `nil` if invalid/expired
- `mode` — `:choose | :create | :login` (initial: `:choose`)
- `create_form`, `login_form` — `to_form(%{}, as: "create")` / `to_form(%{}, as: "login")`

**Render (3 states):**

**`:choose` mode — landing card:**
```
[farm initial circle]
[farm name]          ← invitation.farm.name
[role badge]         ← invitation.role (e.g. "worker")
"You've been invited to join this farm"
[Create account & join]   ← phx-click="pick_create"
[Log in & join]           ← phx-click="pick_login"
"Expires in N days"
```

**`:create` mode:**
```
← back (phx-click="pick_choose")
"Joining [farm] as [role]"
Username input   (required, autocomplete="username")
Password input   (required, type="password", autocomplete="new-password")
Email input      (optional, type="email")
[Create account & join farm]
```
Form: `action={~p"/m/invitations/#{@token}/accept"}`, as `"create"`.

**`:login` mode:**
```
← back (phx-click="pick_choose")
"Already have an account?"
Username or email input  (required, autocomplete="username")
Password input           (required, type="password", autocomplete="current-password")
[Log in & join farm]
```
Form: `action={~p"/m/invitations/#{@token}/accept"}`, as `"login"`.

**Already logged in (`@current_scope` present):**
Skip mode picker. Show landing card with a single "Accept invitation" button (form POSTs to same endpoint with no extra params — controller resolves user from `current_scope`).

**Invalid token (`@invitation` is nil):**
Show error card: "This invitation link is invalid, expired, or already accepted."

**Events:**
```elixir
def handle_event("pick_create", _, socket), do: {:noreply, assign(socket, :mode, :create)}
def handle_event("pick_login",  _, socket), do: {:noreply, assign(socket, :mode, :login)}
def handle_event("pick_choose", _, socket), do: {:noreply, assign(socket, :mode, :choose)}
```

---

### 3. `InvitationController.mobile_accept/2`

Add a second public action to the existing controller. Identical logic to `accept/2` but:
- On success: `put_session(:user_return_to, ~p"/m/#{invitation.farm.slug}")`
- On error (invalid credentials): `redirect(to: ~p"/m/invitations/#{token}")`
- On error (changeset): same redirect to mobile
- On error (seat limit): `redirect(to: ~p"/m/#{invitation.farm.slug}")` with flash

Extract the shared `resolve_user/2` private helper (already private, reused by both actions).

```elixir
def mobile_accept(conn, %{"token" => token} = params) do
  with {:ok, invitation} <- Farms.get_invitation_by_encoded_token(token),
       {:ok, user} <- resolve_user(conn, params),
       {:ok, _membership} <- Farms.accept_invitation(user, invitation.token) do
    conn
    |> put_session(:user_return_to, ~p"/m/#{invitation.farm.slug}")
    |> put_flash(:info, gettext("Welcome to %{farm}!", farm: invitation.farm.name))
    |> PeggyWeb.UserAuth.log_in_user(user)
  else
    {:error, :invalid_credentials} ->
      conn
      |> put_flash(:error, gettext("Those credentials didn't match. Try again."))
      |> redirect(to: ~p"/m/invitations/#{token}")

    {:error, %Ecto.Changeset{}} ->
      conn
      |> put_flash(:error, gettext("Couldn't create your account — check your username (3+ letters/numbers) and password (12+ characters), then try again."))
      |> redirect(to: ~p"/m/invitations/#{token}")

    {:error, :seat_limit_reached} ->
      conn
      |> put_flash(:error, gettext("That farm is full — ask an owner to free up a seat."))
      |> redirect(to: ~p"/farms")

    _ ->
      conn
      |> put_flash(:error, gettext("This invitation link is invalid, expired, or already accepted."))
      |> redirect(to: ~p"/")
  end
end
```

---

### 4. `MobileLive.InviteSession`

**Route:** `live "/m/:farm_slug/invite-session/:role", MobileLive.InviteSession, :show` (in `:farm_scoped` live_session, alongside existing mobile routes).

**Authorization:** If `not Policy.can?(scope, :invite_member)`, redirect to `/m/:slug` with error flash.

**Mount:** mirrors `FarmLive.InviteSession` exactly:
- `connected?` guard before calling `Farms.open_invite_session/3`
- Subscribe to `"farm:#{scope.farm.id}:members"` PubSub topic
- `qr: PeggyWeb.QR.svg(link)` where `link = url(~p"/invitations/#{encoded_token}")`
- Streams: `roster` (members who joined)
- Assigns: `role`, `invitation`, `link`, `qr`, `closed`, `count`

**Render** (uses `Layouts.mobile_app`):
```
[back icon]   "Invite workers"   [role pill: Worker | Vet]
──────────────────────────────
[large QR code, full width]
"Show to workers to scan"
──────────────────────────────
Members joined (N)
• [avatar] alice   "just now"
• [avatar] bob     "2 min ago"
──────────────────────────────
[Close session]   ← text-error, on click: phx-click="close"
```

**Role selector:** Two `<.link navigate>` pills — `/m/:slug/invite-session/worker` and `/m/:slug/invite-session/vet`. Active role highlighted. Changing role closes the current session (LiveView remounts) and opens a new one.

**Events:**
```elixir
def handle_event("close", _, socket) do
  Farms.close_invite_session(socket.assigns.current_scope.farm, socket.assigns.invitation.id)
  {:noreply, assign(socket, :closed, true)}
end
```

**PubSub:**
```elixir
def handle_info({:member_joined, membership}, socket) do
  {:noreply, socket |> stream_insert(:roster, membership, at: 0) |> update(:count, &(&1 + 1))}
end
```

**Closed state:** When `@closed` is true, show "Session closed" message and a "Back to farm" link to `/m/:slug`.

---

### 5. Router additions

**In the public (`:current_user`) scope**, alongside `/invitations/:token`:

```elixir
live "/m/invitations/:token", MobileLive.InvitationShow, :show
```

**In the `:farm_scoped` live_session**, alongside other mobile routes:

```elixir
live "/m/:farm_slug/invite-session/:role", MobileLive.InviteSession, :show
```

**In the unauthenticated POST scope**, alongside `post "/invitations/:token/accept"`:

```elixir
post "/m/invitations/:token/accept", InvitationController, :mobile_accept
```

---

### 6. `AutoRouteByDevice` extension

Extend `call/2` to handle the invitation URL pair. The existing `cond` has three groups of clauses — cookie-mobile, cookie-desktop, cookie-catch-all, and no-cookie UA detection. Four new clauses must be **inserted within the cookie groups** so the `cookie -> conn` catch-all doesn't swallow them:

```elixir
cond do
  # --- existing ---
  cookie == "mobile" and desktop_url?(path) ->
    maybe_redirect_to_mobile(conn, path)

  # --- new ---
  cookie == "mobile" and String.starts_with?(path, "/invitations/") ->
    redirect_swap(conn, path, "/invitations/", "/m/invitations/")

  # --- existing ---
  cookie == "desktop" and mobile_url?(path) ->
    redirect_swap(conn, path, "/m/", "/farms/")

  # --- new ---
  cookie == "desktop" and String.starts_with?(path, "/m/invitations/") ->
    redirect_swap(conn, path, "/m/invitations/", "/invitations/")

  # --- existing (catch-all for any other cookie value) ---
  cookie ->
    conn

  # --- existing ---
  mobile_ua?(conn) and desktop_url?(path) ->
    maybe_redirect_to_mobile(conn, path)

  # --- new ---
  mobile_ua?(conn) and String.starts_with?(path, "/invitations/") ->
    redirect_swap(conn, path, "/invitations/", "/m/invitations/")

  # --- existing ---
  not mobile_ua?(conn) and mobile_url?(path) ->
    redirect_swap(conn, path, "/m/", "/farms/")

  # --- new ---
  not mobile_ua?(conn) and String.starts_with?(path, "/m/invitations/") ->
    redirect_swap(conn, path, "/m/invitations/", "/invitations/")

  true ->
    conn
end
```

---

### 7. More sheet: "Invite workers" entry

In `mobile_more_sheet/1` in `layouts.ex`, add a new `<li>` after the Locations entry:

```heex
<li :if={
  @current_scope && @current_scope.farm &&
    Peggy.Policy.can?(@current_scope, :invite_member)
}>
  <.link
    navigate={~p"/m/#{@current_scope.farm.slug}/invite-session/worker"}
    class="flex items-center gap-3 px-4 py-4 active:bg-base-200"
  >
    <.icon name="hero-user-plus" class="size-5 text-base-content/60" />
    <span>{gettext("Invite workers")}</span>
  </.link>
</li>
```

---

## Out of Scope

- Mobile members list (`/m/:slug/members`) — not requested; owners/managers use the desktop page.
- Invitation creation form (sending invite by email) — no desktop equivalent yet.
- Role confirmation after successful join — the success flash on the farm dashboard is sufficient.
- Farm settings link in the closed-session state — just "Back to farm" is enough.
