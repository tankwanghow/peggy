defmodule PeggyWeb.MembershipLive.Index do
  use PeggyWeb, :live_view

  alias Peggy.Farms
  alias Peggy.Farms.Invitation
  alias Peggy.Policy

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="members" class="mx-auto max-w-3xl">
        <.header>
          {gettext("Members")}
          <:subtitle>
            {@current_scope.farm.name} · {@seats_used}/{@current_scope.farm.seat_limit} {gettext(
              "seats"
            )}
          </:subtitle>
        </.header>

        <section class="mt-6">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
            {gettext("Team")}
          </h2>
          <ul
            id="members-list"
            class="mt-3 divide-y divide-base-300 rounded-box border border-base-300"
          >
            <li
              :for={m <- @members}
              id={"member-#{m.id}"}
              class="flex items-center gap-3 p-3"
            >
              <div class="flex-1 min-w-0">
                <span class="font-medium truncate">
                  <span :if={m.user.email}>{m.user.email}</span>
                  <span :if={m.user.email && m.user.username} class="mx-4">♦</span>
                  <span :if={m.user.username} class="text-base-content/70 truncate">
                    {m.user.username}
                  </span>
                  <span :if={m.user_id == @current_scope.user.id} class="mx-4">♦</span>
                  <span :if={m.user_id == @current_scope.user.id} class="text-base-content/40">
                    {gettext("you")}
                  </span>
                </span>
              </div>
              <form
                :if={@can_manage? and m.role != "owner"}
                id={"role-form-#{m.id}"}
                phx-change="change_role"
              >
                <input type="hidden" name="membership_id" value={m.id} />
                <select name="role" class="select select-sm w-36">
                  <option
                    :for={{label, value} <- assignable_roles()}
                    value={value}
                    selected={m.role == value}
                  >
                    {label}
                  </option>
                </select>
              </form>
              <span
                :if={not @can_manage? or m.role == "owner"}
                class="badge badge-ghost badge-sm capitalize"
              >
                {m.role}
              </span>
              <button
                :if={@can_manage? and m.role != "owner" and m.user_id != @current_scope.user.id}
                id={"remove-member-#{m.id}"}
                type="button"
                phx-click="remove_member"
                phx-value-id={m.id}
                class="btn btn-ghost btn-xs text-error"
                data-confirm={gettext("Remove this member?")}
              >
                {gettext("Remove")}
              </button>
            </li>
          </ul>
        </section>

        <section :if={@can_manage?} class="mt-8">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
            {gettext("Invite a member")}
          </h2>
          <.form
            for={@invite_form}
            id="invite-form"
            phx-submit="invite"
            class="mt-3 flex flex-wrap items-end gap-3"
          >
            <.input
              field={@invite_form[:email]}
              type="email"
              label={gettext("Email (optional)")}
              class="input w-72"
            />
            <.input
              field={@invite_form[:role]}
              type="select"
              label={gettext("Role")}
              options={assignable_roles()}
            />
            <.button class="btn btn-primary btn-sm" phx-disable-with={gettext("Inviting…")}>
              {gettext("Send invite")}
            </.button>
          </.form>
          <div :if={@last_invite_link} class="alert alert-info mt-2" id="invite-link">
            <a href={@last_invite_link} target="_blank" rel="noopener" class="link break-all">
              {@last_invite_link}
            </a>
          </div>
          <div class="mt-4 flex gap-2">
            <.link
              navigate={~p"/farms/#{@current_scope.farm.slug}/invite-session/manager"}
              class="btn btn-outline btn-sm"
            >
              <.icon name="hero-qr-code" class="size-4" /> {gettext("Manager QR")}
            </.link>
            <.link
              navigate={~p"/farms/#{@current_scope.farm.slug}/invite-session/worker"}
              class="btn btn-outline btn-sm"
            >
              <.icon name="hero-qr-code" class="size-4" /> {gettext("Worker QR")}
            </.link>
          </div>
        </section>

        <section :if={@can_manage? and @pending != []} class="mt-8">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
            {gettext("Pending invitations")}
          </h2>
          <ul
            id="pending-invitations"
            class="mt-3 divide-y divide-base-300 rounded-box border border-base-300"
          >
            <li
              :for={invite <- @pending}
              id={"invite-#{invite.id}"}
              class="flex items-center gap-3 p-3"
            >
              <div class="flex-1 min-w-0">
                <div class="font-medium truncate">{invite.email || gettext("Link invite")}</div>
                <div class="text-xs text-base-content/50">
                  {invite.role} · {gettext("expires")} {format_date(
                    DateTime.to_date(invite.expires_at)
                  )}
                </div>
              </div>
              <span class="badge badge-warning badge-sm">{gettext("pending")}</span>
              <button
                id={"revoke-invite-#{invite.id}"}
                type="button"
                phx-click="revoke_invitation"
                phx-value-invitation_id={invite.id}
                class="btn btn-ghost btn-xs text-error"
              >
                {gettext("Revoke")}
              </button>
            </li>
          </ul>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:can_manage?, Policy.can?(socket.assigns.current_scope, :invite_member))
     |> assign(:last_invite_link, nil)
     |> assign_invite_form()
     |> load_members()}
  end

  @impl true
  def handle_event("change_role", %{"membership_id" => id, "role" => role}, socket) do
    unless Policy.can?(socket.assigns.current_scope, :change_member_role) do
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    else
      membership = Enum.find(socket.assigns.members, &(&1.id == String.to_integer(id)))

      cond do
        is_nil(membership) ->
          {:noreply, socket}

        membership.role == "owner" ->
          {:noreply, put_flash(socket, :error, gettext("Cannot change the owner's role."))}

        role not in Enum.map(assignable_roles(), &elem(&1, 1)) ->
          {:noreply, put_flash(socket, :error, gettext("Invalid role."))}

        true ->
          case Farms.change_role(membership, role) do
            {:ok, _} ->
              {:noreply,
               socket
               |> put_flash(:info, gettext("Role updated."))
               |> assign(:last_invite_link, nil)
               |> load_members()}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, gettext("Could not update role."))}
          end
      end
    end
  end

  def handle_event("revoke_invitation", %{"invitation_id" => invitation_id}, socket) do
    unless Policy.can?(socket.assigns.current_scope, :invite_member) do
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    else
      invitation =
        Enum.find(socket.assigns.pending, &(&1.id == String.to_integer(invitation_id)))

      if invitation do
        {:ok, _} = Farms.revoke_invitation(invitation)

        {:noreply,
         socket
         |> put_flash(:info, gettext("Invitation revoked."))
         |> assign(:last_invite_link, nil)
         |> load_members()}
      else
        {:noreply, put_flash(socket, :error, gettext("Invitation not found."))}
      end
    end
  end

  def handle_event("remove_member", %{"id" => id}, socket) do
    unless Policy.can?(socket.assigns.current_scope, :remove_member) do
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    else
      membership = Enum.find(socket.assigns.members, &(&1.id == String.to_integer(id)))

      cond do
        is_nil(membership) ->
          {:noreply, socket}

        membership.user_id == socket.assigns.current_scope.user.id ->
          {:noreply, put_flash(socket, :error, gettext("You cannot remove yourself."))}

        membership.role == "owner" ->
          {:noreply, put_flash(socket, :error, gettext("Cannot remove the farm owner."))}

        true ->
          {:ok, _} = Farms.remove_member(membership)

          {:noreply,
           socket
           |> put_flash(:info, gettext("Member removed."))
           |> assign(:last_invite_link, nil)
           |> load_members()}
      end
    end
  end

  def handle_event("invite", %{"invitation" => params}, socket) do
    farm = socket.assigns.current_scope.farm
    user = socket.assigns.current_scope.user

    case Farms.invite(farm, params, user, &url(~p"/invitations/#{&1}")) do
      {:ok, invitation} ->
        link =
          if invitation.email do
            nil
          else
            url(~p"/invitations/#{Invitation.encode_token(invitation.token)}")
          end

        {:noreply,
         socket
         |> put_flash(:info, invite_flash(invitation))
         |> assign(:last_invite_link, link)
         |> assign_invite_form()
         |> load_members()}

      {:error, :seat_limit_reached} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Seat limit (%{cap}) reached. Raise it in farm settings or remove a member.",
             cap: farm.seat_limit
           )
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :invite_form, to_form(changeset, as: "invitation"))}
    end
  end

  defp invite_flash(%{email: nil}), do: gettext("Invitation created. Share the link below.")
  defp invite_flash(%{email: email}), do: gettext("Invitation sent to %{email}.", email: email)

  defp load_members(socket) do
    farm = socket.assigns.current_scope.farm

    socket
    |> assign(:members, Farms.list_members(farm))
    |> assign(:seats_used, Farms.seats_used(farm))
    |> assign(:pending, Farms.list_pending_invitations(farm))
  end

  defp assign_invite_form(socket) do
    changeset = Ecto.Changeset.change(%Invitation{role: "worker"})
    assign(socket, :invite_form, to_form(changeset, as: "invitation"))
  end

  defp assignable_roles do
    [
      {gettext("Manager"), "manager"},
      {gettext("Worker"), "worker"},
      {gettext("Veterinarian"), "vet"}
    ]
  end

  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%d %b %Y")
end
