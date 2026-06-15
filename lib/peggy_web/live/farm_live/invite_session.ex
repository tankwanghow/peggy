defmodule PeggyWeb.FarmLive.InviteSession do
  use PeggyWeb, :live_view

  alias Peggy.Farms
  alias Peggy.Policy

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-md text-center">
        <.header>
          {gettext("Invite %{role}s", role: @role)}
          <:subtitle>
            {gettext("Scan to join %{farm}. Closes automatically in 30 min.",
              farm: @current_scope.farm.name
            )}
          </:subtitle>
        </.header>

        <%= if @closed do %>
          <p class="alert alert-info mt-6">{gettext("Session closed.")}</p>
          <.link navigate={~p"/farms/#{@current_scope.farm.slug}/settings"} class="btn mt-4">
            {gettext("Back to settings")}
          </.link>
        <% else %>
          <div class="mt-6 flex justify-center">{raw(@qr)}</div>
          <p class="mt-2 break-all text-sm text-base-content/70">{@link}</p>

          <button
            phx-click="close"
            class="btn btn-error btn-soft mt-4"
            phx-disable-with={gettext("Closing...")}
          >
            {gettext("Close session")}
          </button>

          <div class="mt-8 text-left">
            <p class="font-semibold">{gettext("Joined so far (%{count})", count: @count)}</p>
            <ul id="roster" phx-update="stream" class="mt-2 space-y-1">
              <li :for={{id, m} <- @streams.roster} id={id} class="badge badge-soft">
                {m.user.username || m.user.email}
              </li>
            </ul>
          </div>
        <% end %>
      </div>
    </Layouts.app>
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
         |> push_navigate(to: ~p"/farms/#{scope.farm.slug}/settings")}

      connected?(socket) ->
        case Farms.open_invite_session(scope.farm, scope.user, role) do
          {:ok, invitation} ->
            Phoenix.PubSub.subscribe(Peggy.PubSub, "farm:#{scope.farm.id}:members")

            link = url(~p"/invitations/#{Farms.Invitation.encode_token(invitation.token)}")

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
             |> put_flash(:error, gettext("You can't open an invite session."))
             |> push_navigate(to: ~p"/farms/#{scope.farm.slug}/settings")}
        end

      true ->
        {:ok,
         assign(socket,
           role: role,
           invitation: nil,
           link: "",
           qr: "",
           closed: false,
           count: 0
         )
         |> stream(:roster, [])}
    end
  end

  @impl true
  def handle_event("close", _params, socket) do
    Farms.close_invite_session(socket.assigns.current_scope.farm, socket.assigns.invitation.id)
    {:noreply, assign(socket, :closed, true)}
  end

  @impl true
  def handle_info({:member_joined, membership}, socket) do
    {:noreply,
     socket
     |> stream_insert(:roster, membership, at: 0)
     |> update(:count, &(&1 + 1))}
  end
end
