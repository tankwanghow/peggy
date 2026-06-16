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
