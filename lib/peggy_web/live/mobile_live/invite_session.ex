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
