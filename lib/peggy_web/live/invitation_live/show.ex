defmodule PeggyWeb.InvitationLive.Show do
  use PeggyWeb, :live_view

  alias Peggy.Farms

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-md text-center">
        <%= case @state do %>
          <% :invalid -> %>
            <.header>{gettext("Invitation not valid")}</.header>
            <p class="mt-4 text-base-content/70">
              {gettext("This invitation link is invalid, expired, or already accepted.")}
            </p>
          <% :needs_login -> %>
            <.header>{gettext("Log in to accept")}</.header>
            <p class="mt-4">
              {gettext("You've been invited to join")} <b>{@invitation.farm.name}</b>
              {gettext("as")} <b>{@invitation.role}</b>. {gettext("Log in or register with")} <b>{@invitation.email}</b>, {gettext(
                "then open this link again."
              )}
            </p>
            <.link
              navigate={~p"/users/register?email=#{@invitation.email}"}
              class="btn btn-primary mt-4"
            >
              {gettext("Register")}
            </.link>
            <p class="mt-3 text-sm text-base-content/60">
              {gettext("Already have an account?")}
              <.link navigate={~p"/users/log-in"} class="link link-primary">
                {gettext("Log in")}
              </.link>
              {gettext("and return here.")}
            </p>
          <% :email_mismatch -> %>
            <.header>{gettext("Different email required")}</.header>
            <p class="mt-4">
              {gettext("This invitation is for")} <b>{@invitation.email}</b>, {gettext(
                "but you are logged in as"
              )} <b>{@current_scope.user.email}</b>. {gettext("Log out and try again.")}
            </p>
          <% :ready -> %>
            <.header>{gettext("Join %{farm}", farm: @invitation.farm.name)}</.header>
            <p class="mt-4">{gettext("Role:")} <b>{@invitation.role}</b></p>
            <button phx-click="accept" class="btn btn-primary mt-6">
              {gettext("Accept invitation")}
            </button>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case Farms.get_invitation_by_token(token) do
      {:ok, invitation} ->
        {:ok, socket |> assign(:invitation, invitation) |> compute_state()}

      :error ->
        {:ok, assign(socket, state: :invalid, invitation: nil)}
    end
  end

  @impl true
  def handle_event("accept", _, socket) do
    invitation = socket.assigns.invitation
    user = socket.assigns.current_scope.user

    case Farms.accept_invitation(invitation, user) do
      {:ok, _membership} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Welcome to %{farm}!", farm: invitation.farm.name))
         |> push_navigate(to: ~p"/farms/#{invitation.farm.slug}")}

      {:error, :seat_limit_reached} ->
        {:noreply,
         put_flash(socket, :error, gettext("That farm is full — ask an owner to free up a seat."))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Could not accept invitation."))}
    end
  end

  defp compute_state(socket) do
    invitation = socket.assigns.invitation
    user = socket.assigns.current_scope && socket.assigns.current_scope.user

    state =
      cond do
        is_nil(user) -> :needs_login
        String.downcase(user.email) != invitation.email -> :email_mismatch
        true -> :ready
      end

    assign(socket, :state, state)
  end
end
