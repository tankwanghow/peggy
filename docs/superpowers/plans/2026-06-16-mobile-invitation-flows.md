# Mobile Invitation Flows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build two mobile-optimized flows: worker invitation acceptance at `/m/invitations/:token` and manager QR invite session at `/m/:farm_slug/invite-session/:role`.

**Architecture:** Two new LiveViews mirror their desktop counterparts. Acceptance uses a new `Layouts.mobile_standalone/1` (no nav, centered card). `InvitationController` gains a `mobile_accept/2` action that redirects to `/m/:slug` on success. `AutoRouteByDevice` is extended with invitation-URL swapping and the plug is added to the invitation routes scope so device-based routing works before login.

**Tech Stack:** Phoenix 1.8, LiveView 1.1, HEEx, daisyUI 5, Tailwind v4, `PeggyWeb.QR.svg/1` for QR generation.

---

## File Map

| File | Change |
|------|--------|
| `lib/peggy_web/components/layouts.ex` | Add `mobile_standalone/1`; add "Invite workers" li to `mobile_more_sheet` |
| `lib/peggy_web/controllers/invitation_controller.ex` | Add `mobile_accept/2` |
| `lib/peggy_web/router.ex` | Add POST + 2 live routes; add plug to invitation scope |
| `lib/peggy_web/live/mobile_live/invitation_show.ex` | New |
| `lib/peggy_web/live/mobile_live/invite_session.ex` | New |
| `lib/peggy_web/plugs/auto_route_by_device.ex` | Add 4 cond clauses (re-ordered for correctness) |
| `test/peggy_web/controllers/invitation_controller_test.exs` | Extend with mobile_accept tests |
| `test/peggy_web/live/mobile_live/invitation_show_test.exs` | New |
| `test/peggy_web/live/mobile_live/invite_session_test.exs` | New |
| `test/peggy_web/plugs/auto_route_by_device_test.exs` | New |

---

### Task 1: `Layouts.mobile_standalone/1`

**Files:**
- Modify: `lib/peggy_web/components/layouts.ex`

This layout is used by `MobileLive.InvitationShow`. It has no navigation — just a Peggy wordmark above a centered content slot. Do NOT add the "Invite workers" more-sheet entry yet; that route doesn't exist until Task 4.

- [ ] **Step 1: Add `mobile_standalone/1` to `layouts.ex`**

Insert this function just before the `defp mobile_more_sheet(assigns)` line (around line 248). It must be `def` (public) so LiveViews can reference `Layouts.mobile_standalone`:

```elixir
attr :flash, :map, required: true

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

- [ ] **Step 2: Verify compile**

```bash
mix compile --warnings-as-errors 2>&1 | tail -5
```

Expected: `Generated peggy app` with no errors or warnings.

- [ ] **Step 3: Commit**

```bash
git add lib/peggy_web/components/layouts.ex
git commit -m "$(cat <<'EOF'
feat: add mobile_standalone layout for invitation acceptance

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `mobile_accept/2` controller action + POST route

**Files:**
- Modify: `lib/peggy_web/controllers/invitation_controller.ex`
- Modify: `lib/peggy_web/router.ex`
- Modify: `test/peggy_web/controllers/invitation_controller_test.exs`

`mobile_accept/2` is identical to `accept/2` except it redirects to `/m/:slug` on success and `/m/invitations/:token` on credential/changeset errors.

- [ ] **Step 1: Write failing tests**

Add this `describe` block at the end of `test/peggy_web/controllers/invitation_controller_test.exs`, inside the module (before the final `end`):

```elixir
describe "mobile_accept/2" do
  test "create-account path redirects to mobile farm URL", %{conn: conn} do
    %{scope: scope, encoded: encoded} = pending_invitation()

    conn =
      post(conn, ~p"/m/invitations/#{encoded}/accept", %{
        "create" => %{"username" => "mobilenew", "password" => "supersecret12"}
      })

    assert redirected_to(conn) == ~p"/m/#{scope.farm.slug}"
    assert get_session(conn, :user_token)
  end

  test "log-in-to-accept path redirects to mobile farm URL", %{conn: conn} do
    existing = username_user_fixture(%{username: "mobilelogin"})
    %{scope: scope, encoded: encoded} = pending_invitation()

    conn =
      post(conn, ~p"/m/invitations/#{encoded}/accept", %{
        "login" => %{"identifier" => "mobilelogin", "password" => valid_user_password()}
      })

    assert redirected_to(conn) == ~p"/m/#{scope.farm.slug}"
    assert get_session(conn, :user_token)
    assert Farms.get_membership(existing, scope.farm)
  end

  test "already-logged-in user redirects to mobile farm URL", %{conn: conn} do
    user = username_user_fixture()
    %{scope: scope, encoded: encoded} = pending_invitation()

    conn =
      conn
      |> log_in_user(user)
      |> post(~p"/m/invitations/#{encoded}/accept", %{})

    assert redirected_to(conn) == ~p"/m/#{scope.farm.slug}"
    assert Farms.get_membership(user, scope.farm)
  end

  test "wrong credentials redirect back to mobile invite URL", %{conn: conn} do
    username_user_fixture(%{username: "wrongmobile"})
    %{encoded: encoded} = pending_invitation()

    conn =
      post(conn, ~p"/m/invitations/#{encoded}/accept", %{
        "login" => %{"identifier" => "wrongmobile", "password" => "wrong password here"}
      })

    assert redirected_to(conn) == ~p"/m/invitations/#{encoded}"
    refute get_session(conn, :user_token)
  end

  test "invalid token redirects home", %{conn: conn} do
    conn = post(conn, ~p"/m/invitations/garbage/accept", %{})
    assert redirected_to(conn) == ~p"/"
    refute get_session(conn, :user_token)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
mix test test/peggy_web/controllers/invitation_controller_test.exs 2>&1 | tail -15
```

Expected: compile error — `~p"/m/invitations/..."` route not defined yet.

- [ ] **Step 3: Add the POST route to `router.ex`**

In `lib/peggy_web/router.ex`, find the line:
```elixir
post "/invitations/:token/accept", InvitationController, :accept
```

Add the mobile POST immediately after:
```elixir
post "/m/invitations/:token/accept", InvitationController, :mobile_accept
```

- [ ] **Step 4: Add `mobile_accept/2` to `invitation_controller.ex`**

Add this function immediately after `accept/2` (the existing public function). The private `resolve_user/2` helper is already defined and shared by both:

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
      |> put_flash(
        :error,
        gettext(
          "Couldn't create your account — check your username (3+ letters/numbers) and password (12+ characters), then try again."
        )
      )
      |> redirect(to: ~p"/m/invitations/#{token}")

    {:error, :seat_limit_reached} ->
      conn
      |> put_flash(:error, gettext("That farm is full — ask an owner to free up a seat."))
      |> redirect(to: ~p"/farms")

    _ ->
      conn
      |> put_flash(
        :error,
        gettext("This invitation link is invalid, expired, or already accepted.")
      )
      |> redirect(to: ~p"/")
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
mix test test/peggy_web/controllers/invitation_controller_test.exs 2>&1 | tail -10
```

Expected: all tests pass, no failures.

- [ ] **Step 6: Commit**

```bash
git add lib/peggy_web/controllers/invitation_controller.ex \
        lib/peggy_web/router.ex \
        test/peggy_web/controllers/invitation_controller_test.exs
git commit -m "$(cat <<'EOF'
feat: add mobile invitation accept controller action

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `MobileLive.InvitationShow` + live route

**Files:**
- Create: `lib/peggy_web/live/mobile_live/invitation_show.ex`
- Modify: `lib/peggy_web/router.ex`
- Create: `test/peggy_web/live/mobile_live/invitation_show_test.exs`

This LiveView has three render modes: `:choose` (landing card), `:create` (account creation form), `:login` (login form). For already-logged-in users it skips the mode picker and shows a single accept button. The form action for both forms is `~p"/m/invitations/#{@token}/accept"` (the POST route added in Task 2).

- [ ] **Step 1: Create the test file**

Create `test/peggy_web/live/mobile_live/invitation_show_test.exs`:

```elixir
defmodule PeggyWeb.MobileLive.InvitationShowTest do
  use PeggyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Peggy.AccountsFixtures
  import Peggy.FarmsFixtures

  alias Peggy.Farms
  alias Peggy.Farms.Invitation

  defp pending_invitation do
    scope = farm_scope_fixture()
    {:ok, invitation} = Farms.invite(scope.farm, %{"email" => nil, "role" => "worker"}, scope.user)
    %{scope: scope, invitation: invitation, encoded: Invitation.encode_token(invitation.token)}
  end

  test "anonymous user sees farm name, role badge, and two CTAs", %{conn: conn} do
    %{scope: scope, encoded: encoded} = pending_invitation()

    {:ok, _lv, html} = live(conn, ~p"/m/invitations/#{encoded}")

    assert html =~ scope.farm.name
    assert html =~ "worker"
    assert html =~ "Create account"
    assert html =~ "Log in"
  end

  test "clicking create account shows the account creation form", %{conn: conn} do
    %{encoded: encoded} = pending_invitation()

    {:ok, lv, _html} = live(conn, ~p"/m/invitations/#{encoded}")
    html = lv |> element("button[phx-click='pick_create']") |> render_click()

    assert html =~ "Username"
    assert html =~ "Password"
    assert html =~ "Email"
  end

  test "clicking log in shows the login form", %{conn: conn} do
    %{encoded: encoded} = pending_invitation()

    {:ok, lv, _html} = live(conn, ~p"/m/invitations/#{encoded}")
    html = lv |> element("button[phx-click='pick_login']") |> render_click()

    assert html =~ "Username or email"
    refute html =~ "Email (optional)"
  end

  test "back button from create mode returns to choose", %{conn: conn} do
    %{encoded: encoded} = pending_invitation()

    {:ok, lv, _html} = live(conn, ~p"/m/invitations/#{encoded}")
    lv |> element("button[phx-click='pick_create']") |> render_click()
    html = lv |> element("button[phx-click='pick_choose']") |> render_click()

    assert html =~ "Create account"
    assert html =~ "Log in"
  end

  test "invalid token shows error card", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/m/invitations/not-a-real-token")
    assert html =~ "Invitation not valid"
  end

  test "logged-in user sees single accept button", %{conn: conn} do
    %{encoded: encoded} = pending_invitation()
    user = user_fixture()

    {:ok, _lv, html} = conn |> log_in_user(user) |> live(~p"/m/invitations/#{encoded}")

    assert html =~ "Accept invitation"
    refute html =~ "Create account"
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
mix test test/peggy_web/live/mobile_live/invitation_show_test.exs 2>&1 | tail -10
```

Expected: compile error — `MobileLive.InvitationShow` does not exist yet.

- [ ] **Step 3: Create `lib/peggy_web/live/mobile_live/invitation_show.ex`**

```elixir
defmodule PeggyWeb.MobileLive.InvitationShow do
  use PeggyWeb, :live_view

  alias Peggy.Farms

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_standalone flash={@flash}>
      <%= if @invitation do %>
        <%= if @current_scope do %>
          <div class="w-full max-w-sm card bg-base-100 shadow">
            <div class="card-body items-center text-center gap-4">
              <div class="size-16 rounded-xl bg-primary/10 flex items-center justify-center text-2xl font-bold text-primary">
                {String.upcase(String.first(@invitation.farm.name))}
              </div>
              <div>
                <h2 class="text-lg font-semibold">{@invitation.farm.name}</h2>
                <div class="badge badge-soft badge-primary mt-1">{@invitation.role}</div>
              </div>
              <.form
                for={@accept_form}
                id="accept-form"
                action={~p"/m/invitations/#{@token}/accept"}
                class="w-full"
              >
                <.button class="btn btn-primary w-full" phx-disable-with={gettext("Joining...")}>
                  {gettext("Accept invitation")}
                </.button>
              </.form>
            </div>
          </div>
        <% else %>
          <%= case @mode do %>
            <% :choose -> %>
              <div class="w-full max-w-sm card bg-base-100 shadow">
                <div class="card-body items-center text-center gap-4">
                  <div class="size-16 rounded-xl bg-primary/10 flex items-center justify-center text-2xl font-bold text-primary">
                    {String.upcase(String.first(@invitation.farm.name))}
                  </div>
                  <div>
                    <h2 class="text-lg font-semibold">{@invitation.farm.name}</h2>
                    <div class="badge badge-soft badge-primary mt-1">{@invitation.role}</div>
                  </div>
                  <p class="text-sm text-base-content/70">
                    {gettext("You've been invited to join this farm")}
                  </p>
                  <button class="btn btn-primary w-full" phx-click="pick_create">
                    {gettext("Create account & join")}
                  </button>
                  <button class="btn btn-soft w-full" phx-click="pick_login">
                    {gettext("Log in & join")}
                  </button>
                  <p class="text-xs text-base-content/50">
                    {gettext("Expires in %{days} days", days: expiry_days(@invitation))}
                  </p>
                </div>
              </div>
            <% :create -> %>
              <div class="w-full max-w-sm card bg-base-100 shadow">
                <div class="card-body gap-4">
                  <button class="btn btn-ghost btn-sm self-start -ml-2" phx-click="pick_choose">
                    <.icon name="hero-arrow-left-micro" class="size-4" />
                    {gettext("Back")}
                  </button>
                  <p class="text-sm text-base-content/70">
                    {gettext("Joining %{farm} as %{role}",
                      farm: @invitation.farm.name,
                      role: @invitation.role
                    )}
                  </p>
                  <.form
                    for={@create_form}
                    id="create-form"
                    action={~p"/m/invitations/#{@token}/accept"}
                    class="space-y-3"
                  >
                    <.input
                      field={@create_form[:username]}
                      label={gettext("Username")}
                      autocomplete="username"
                      spellcheck="false"
                      phx-mounted={JS.focus()}
                      required
                    />
                    <.input
                      field={@create_form[:password]}
                      type="password"
                      label={gettext("Password")}
                      autocomplete="new-password"
                      required
                    />
                    <.input
                      field={@create_form[:email]}
                      type="email"
                      label={gettext("Email (optional)")}
                      autocomplete="email"
                      spellcheck="false"
                    />
                    <.button
                      class="btn btn-primary w-full"
                      phx-disable-with={gettext("Creating...")}
                    >
                      {gettext("Create account & join")}
                    </.button>
                  </.form>
                </div>
              </div>
            <% :login -> %>
              <div class="w-full max-w-sm card bg-base-100 shadow">
                <div class="card-body gap-4">
                  <button class="btn btn-ghost btn-sm self-start -ml-2" phx-click="pick_choose">
                    <.icon name="hero-arrow-left-micro" class="size-4" />
                    {gettext("Back")}
                  </button>
                  <p class="text-sm font-semibold">{gettext("Already have an account?")}</p>
                  <.form
                    for={@login_form}
                    id="login-form"
                    action={~p"/m/invitations/#{@token}/accept"}
                    class="space-y-3"
                  >
                    <.input
                      field={@login_form[:identifier]}
                      label={gettext("Username or email")}
                      autocomplete="username"
                      spellcheck="false"
                      phx-mounted={JS.focus()}
                      required
                    />
                    <.input
                      field={@login_form[:password]}
                      type="password"
                      label={gettext("Password")}
                      autocomplete="current-password"
                      required
                    />
                    <.button
                      class="btn btn-primary w-full"
                      phx-disable-with={gettext("Joining...")}
                    >
                      {gettext("Log in & join")}
                    </.button>
                  </.form>
                </div>
              </div>
          <% end %>
        <% end %>
      <% else %>
        <div class="w-full max-w-sm card bg-base-100 shadow">
          <div class="card-body items-center text-center gap-3">
            <.icon name="hero-x-circle" class="size-10 text-error" />
            <h2 class="text-lg font-semibold">{gettext("Invitation not valid")}</h2>
            <p class="text-sm text-base-content/70">
              {gettext("This invitation link is invalid, expired, or already accepted.")}
            </p>
          </div>
        </div>
      <% end %>
    </Layouts.mobile_standalone>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    invitation =
      case Farms.get_invitation_by_encoded_token(token) do
        {:ok, inv} -> inv
        :error -> nil
      end

    {:ok,
     assign(socket,
       token: token,
       invitation: invitation,
       mode: :choose,
       accept_form: to_form(%{}, as: "accept"),
       create_form: to_form(%{}, as: "create"),
       login_form: to_form(%{}, as: "login")
     )}
  end

  @impl true
  def handle_event("pick_create", _, socket), do: {:noreply, assign(socket, :mode, :create)}
  def handle_event("pick_login", _, socket), do: {:noreply, assign(socket, :mode, :login)}
  def handle_event("pick_choose", _, socket), do: {:noreply, assign(socket, :mode, :choose)}

  defp expiry_days(invitation) do
    diff_secs = DateTime.diff(invitation.expires_at, DateTime.utc_now())
    max(0, div(diff_secs, 86_400))
  end
end
```

- [ ] **Step 4: Add the live route to `router.ex`**

In the `:current_user` `live_session` block (which already contains `/invitations/:token`), add the mobile route immediately after:

```elixir
live "/m/invitations/:token", MobileLive.InvitationShow, :show
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
mix test test/peggy_web/live/mobile_live/invitation_show_test.exs 2>&1 | tail -10
```

Expected: 6 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/peggy_web/live/mobile_live/invitation_show.ex \
        lib/peggy_web/router.ex \
        test/peggy_web/live/mobile_live/invitation_show_test.exs
git commit -m "$(cat <<'EOF'
feat: add mobile invitation acceptance LiveView

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `MobileLive.InviteSession` + live route + More sheet entry

**Files:**
- Create: `lib/peggy_web/live/mobile_live/invite_session.ex`
- Modify: `lib/peggy_web/router.ex`
- Modify: `lib/peggy_web/components/layouts.ex`
- Create: `test/peggy_web/live/mobile_live/invite_session_test.exs`

The QR link points to `/m/invitations/:token` directly (not `/invitations/:token`) so workers always reach the mobile acceptance page. The more sheet entry can only be added after the `/m/:slug/invite-session/:role` route is registered — do both in the same commit.

- [ ] **Step 1: Create the test file**

Create `test/peggy_web/live/mobile_live/invite_session_test.exs`:

```elixir
defmodule PeggyWeb.MobileLive.InviteSessionTest do
  use PeggyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Peggy.AccountsFixtures
  import Peggy.FarmsFixtures

  alias Peggy.Farms

  test "manager sees QR SVG and roster heading", %{conn: conn} do
    scope = farm_scope_fixture()

    {:ok, _lv, html} =
      conn |> log_in_user(scope.user) |> live(~p"/m/#{scope.farm.slug}/invite-session/worker")

    assert html =~ "<svg"
    assert html =~ "Joined so far"
  end

  test "worker is redirected to mobile farm home", %{conn: conn} do
    worker_scope = worker_scope_fixture()

    assert {:error, {:live_redirect, %{to: path}}} =
             conn
             |> log_in_user(worker_scope.user)
             |> live(~p"/m/#{worker_scope.farm.slug}/invite-session/worker")

    assert path == ~p"/m/#{worker_scope.farm.slug}"
  end

  test "close button closes the session", %{conn: conn} do
    scope = farm_scope_fixture()

    {:ok, lv, _html} =
      conn |> log_in_user(scope.user) |> live(~p"/m/#{scope.farm.slug}/invite-session/worker")

    html = lv |> element("button[phx-click='close']") |> render_click()
    assert html =~ "Session closed"
  end

  test "member_joined PubSub message inserts into roster", %{conn: conn} do
    scope = farm_scope_fixture()

    {:ok, lv, _html} =
      conn |> log_in_user(scope.user) |> live(~p"/m/#{scope.farm.slug}/invite-session/worker")

    worker = member_fixture(scope.farm)
    membership = Farms.get_membership(worker, scope.farm) |> Peggy.Repo.preload(:user)
    send(lv.pid, {:member_joined, membership})

    html = render(lv)
    assert html =~ (worker.username || worker.email)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
mix test test/peggy_web/live/mobile_live/invite_session_test.exs 2>&1 | tail -10
```

Expected: compile error — `MobileLive.InviteSession` does not exist yet.

- [ ] **Step 3: Create `lib/peggy_web/live/mobile_live/invite_session.ex`**

```elixir
defmodule PeggyWeb.MobileLive.InviteSession do
  use PeggyWeb, :live_view

  alias Peggy.Farms
  alias Peggy.Policy

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_app flash={@flash} current_scope={@current_scope} active={:more}>
      <div class="flex flex-col h-full">
        <div class="flex items-center justify-between gap-2 px-4 py-3 border-b border-base-200">
          <.link navigate={~p"/m/#{@current_scope.farm.slug}"} class="btn btn-ghost btn-sm">
            <.icon name="hero-arrow-left-micro" class="size-4" />
            {gettext("Back")}
          </.link>
          <h1 class="font-semibold text-sm">{gettext("Invite workers")}</h1>
          <div class="flex gap-1">
            <.link
              :for={r <- ~w[worker vet]}
              navigate={~p"/m/#{@current_scope.farm.slug}/invite-session/#{r}"}
              class={[
                "btn btn-xs",
                @role == r && "btn-primary",
                @role != r && "btn-ghost"
              ]}
            >
              {String.capitalize(r)}
            </.link>
          </div>
        </div>

        <%= if @closed do %>
          <div class="flex flex-col items-center justify-center flex-1 gap-4 px-6 text-center">
            <.icon name="hero-check-circle" class="size-12 text-success" />
            <p class="font-semibold">{gettext("Session closed.")}</p>
            <.link navigate={~p"/m/#{@current_scope.farm.slug}"} class="btn btn-primary">
              {gettext("Back to farm")}
            </.link>
          </div>
        <% else %>
          <div class="flex flex-col items-center gap-3 px-4 pt-4 flex-shrink-0">
            <div class="bg-white p-3 rounded-xl">{raw(@qr)}</div>
            <p class="text-sm text-base-content/60 text-center">
              {gettext("Show to workers to scan")}
            </p>
            <button
              phx-click="close"
              class="btn btn-error btn-soft btn-sm"
              phx-disable-with={gettext("Closing...")}
            >
              {gettext("Close session")}
            </button>
          </div>

          <div class="flex-1 overflow-y-auto px-4 pt-4">
            <p class="text-sm font-semibold mb-2">
              {gettext("Joined so far (%{count})", count: @count)}
            </p>
            <ul id="roster" phx-update="stream" class="space-y-2">
              <li
                :for={{id, m} <- @streams.roster}
                id={id}
                class="flex items-center gap-3 p-2 rounded-lg bg-base-200"
              >
                <div class="size-8 rounded-full bg-primary flex items-center justify-center text-primary-content text-sm font-bold select-none">
                  {m.user |> display_name() |> String.upcase() |> String.first()}
                </div>
                <span class="text-sm">{display_name(m.user)}</span>
              </li>
            </ul>
          </div>
        <% end %>
      </div>
    </Layouts.mobile_app>
    """
  end

  @impl true
  def mount(%{"role" => role}, _session, socket) do
    scope = socket.assigns.current_scope

    cond do
      not Policy.can?(scope, :invite_member) ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Not authorized."))
         |> push_navigate(to: ~p"/m/#{scope.farm.slug}")}

      connected?(socket) ->
        case Farms.open_invite_session(scope.farm, scope.user, role) do
          {:ok, invitation} ->
            Phoenix.PubSub.subscribe(Peggy.PubSub, "farm:#{scope.farm.id}:members")

            encoded = Farms.Invitation.encode_token(invitation.token)
            link = url(~p"/m/invitations/#{encoded}")

            {:ok,
             socket
             |> assign(
               role: role,
               invitation: invitation,
               link: link,
               qr: PeggyWeb.QR.svg(link),
               closed: false,
               count: 0
             )
             |> stream(:roster, [])}

          _ ->
            {:ok,
             socket
             |> put_flash(:error, gettext("Could not open invite session."))
             |> push_navigate(to: ~p"/m/#{scope.farm.slug}")}
        end

      true ->
        {:ok,
         assign(socket, role: role, invitation: nil, link: "", qr: "", closed: false, count: 0)
         |> stream(:roster, [])}
    end
  end

  @impl true
  def handle_event("close", _, socket) do
    if socket.assigns.invitation do
      Farms.close_invite_session(
        socket.assigns.current_scope.farm,
        socket.assigns.invitation.id
      )
    end

    {:noreply, assign(socket, :closed, true)}
  end

  @impl true
  def handle_info({:member_joined, membership}, socket) do
    {:noreply,
     socket
     |> stream_insert(:roster, membership, at: 0)
     |> update(:count, &(&1 + 1))}
  end

  defp display_name(%{username: u}) when is_binary(u) and u != "", do: u
  defp display_name(%{email: e}), do: e || "?"
end
```

- [ ] **Step 4: Add the live route to `router.ex`**

In the `:farm_scoped` `live_session` block, alongside the other mobile routes (after `"/m/:farm_slug/breeding/lactating"`), add:

```elixir
live "/m/:farm_slug/invite-session/:role", MobileLive.InviteSession, :show
```

- [ ] **Step 5: Add "Invite workers" to `mobile_more_sheet` in `layouts.ex`**

In `mobile_more_sheet/1`, after the Locations `<li>` (the one with `hero-map-pin`) and before the "Open desktop view" `<li>`, insert:

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

- [ ] **Step 6: Run tests to verify they pass**

```bash
mix test test/peggy_web/live/mobile_live/invite_session_test.exs 2>&1 | tail -10
```

Expected: 4 tests, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add lib/peggy_web/live/mobile_live/invite_session.ex \
        lib/peggy_web/router.ex \
        lib/peggy_web/components/layouts.ex \
        test/peggy_web/live/mobile_live/invite_session_test.exs
git commit -m "$(cat <<'EOF'
feat: add mobile invite session LiveView and more sheet entry

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: `AutoRouteByDevice` extension

**Files:**
- Modify: `lib/peggy_web/plugs/auto_route_by_device.ex`
- Modify: `lib/peggy_web/router.ex`
- Create: `test/peggy_web/plugs/auto_route_by_device_test.exs`

**Critical ordering note:** The specific `/m/invitations/` clause must appear BEFORE the broad `mobile_url?` clause in the `cond`. `mobile_url?` matches any path starting with `/m/` — including `/m/invitations/`. If the broad clause runs first, desktop users on `/m/invitations/:token` would incorrectly be redirected to `/farms/invitations/:token` (a 404) instead of `/invitations/:token`.

The plug also needs to run for the invitation routes (currently `pipe_through [:browser]` with no device plug). We add it to that scope.

- [ ] **Step 1: Create the test file**

Create `test/peggy_web/plugs/auto_route_by_device_test.exs`:

```elixir
defmodule PeggyWeb.Plugs.AutoRouteByDeviceTest do
  use PeggyWeb.ConnCase, async: true

  @mobile_ua "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"

  test "mobile UA on /invitations/:token redirects to /m/invitations/:token" do
    conn =
      build_conn()
      |> put_req_header("user-agent", @mobile_ua)
      |> get(~p"/invitations/sometoken")

    assert redirected_to(conn) == ~p"/m/invitations/sometoken"
  end

  test "desktop UA on /m/invitations/:token redirects to /invitations/:token" do
    conn = get(build_conn(), ~p"/m/invitations/sometoken")
    assert redirected_to(conn) == ~p"/invitations/sometoken"
  end

  test "mobile cookie on /invitations/:token redirects to /m/invitations/:token" do
    conn =
      build_conn()
      |> Plug.Test.put_req_cookie("peggy_view", "mobile")
      |> get(~p"/invitations/sometoken")

    assert redirected_to(conn) == ~p"/m/invitations/sometoken"
  end

  test "desktop cookie on /m/invitations/:token redirects to /invitations/:token" do
    conn =
      build_conn()
      |> Plug.Test.put_req_cookie("peggy_view", "desktop")
      |> get(~p"/m/invitations/sometoken")

    assert redirected_to(conn) == ~p"/invitations/sometoken"
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
mix test test/peggy_web/plugs/auto_route_by_device_test.exs 2>&1 | tail -10
```

Expected: 4 failures — the plug is not in the invitation scope and the invitation clauses don't exist yet.

- [ ] **Step 3: Replace the `call/2` body in `auto_route_by_device.ex`**

Replace the entire `def call(conn, _opts) do … end` function (currently lines ~35–61) with:

```elixir
def call(conn, _opts) do
  cookie = conn.cookies["peggy_view"]
  path = conn.request_path

  cond do
    cookie == "mobile" and desktop_url?(path) ->
      maybe_redirect_to_mobile(conn, path)

    cookie == "mobile" and String.starts_with?(path, "/invitations/") ->
      redirect_swap(conn, path, "/invitations/", "/m/invitations/")

    cookie == "desktop" and String.starts_with?(path, "/m/invitations/") ->
      redirect_swap(conn, path, "/m/invitations/", "/invitations/")

    cookie == "desktop" and mobile_url?(path) ->
      redirect_swap(conn, path, "/m/", "/farms/")

    cookie ->
      conn

    mobile_ua?(conn) and desktop_url?(path) ->
      maybe_redirect_to_mobile(conn, path)

    mobile_ua?(conn) and String.starts_with?(path, "/invitations/") ->
      redirect_swap(conn, path, "/invitations/", "/m/invitations/")

    not mobile_ua?(conn) and String.starts_with?(path, "/m/invitations/") ->
      redirect_swap(conn, path, "/m/invitations/", "/invitations/")

    not mobile_ua?(conn) and mobile_url?(path) ->
      redirect_swap(conn, path, "/m/", "/farms/")

    true ->
      conn
  end
end
```

- [ ] **Step 4: Add the plug to the invitation routes scope in `router.ex`**

Find the third scope (the one with `pipe_through [:browser]` that contains `/invitations/:token` and the auth routes). Change its `pipe_through` to include the device plug:

```elixir
# Before:
scope "/", PeggyWeb do
  pipe_through [:browser]

# After:
scope "/", PeggyWeb do
  pipe_through [:browser, PeggyWeb.Plugs.AutoRouteByDevice]
```

This is safe: the plug's `cond` only redirects `/farms/`, `/m/`, `/invitations/`, and `/m/invitations/` prefixes. Login, register, log-out, and locale routes all pass through to `true -> conn`.

- [ ] **Step 5: Run tests to verify they pass**

```bash
mix test test/peggy_web/plugs/auto_route_by_device_test.exs 2>&1 | tail -10
```

Expected: 4 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/peggy_web/plugs/auto_route_by_device.ex \
        lib/peggy_web/router.ex \
        test/peggy_web/plugs/auto_route_by_device_test.exs
git commit -m "$(cat <<'EOF'
feat: extend AutoRouteByDevice for invitation URLs

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Full precommit

**Files:** none — verification only

- [ ] **Step 1: Run full precommit suite**

```bash
mix precommit 2>&1 | tail -15
```

Expected: compile clean, no unused deps, format clean, all tests pass, 0 failures.

- [ ] **Step 2: If `mix format` made changes, commit them**

```bash
git diff --name-only
```

If any files changed:

```bash
git add -p
git commit -m "$(cat <<'EOF'
style: apply mix format

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```
