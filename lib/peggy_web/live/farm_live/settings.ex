defmodule PeggyWeb.FarmLive.Settings do
  use PeggyWeb, :live_view

  alias Peggy.Farms
  alias Peggy.Farms.Invitation
  alias Peggy.Policy

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-3xl">
        <.header>{gettext("Farm settings - %{name}", name: @current_scope.farm.name)}</.header>

        <section class="mt-8">
          <h2 class="text-lg font-semibold">{gettext("Farm profile")}</h2>
          <.form for={@farm_form} id="farm-form" phx-submit="save_farm" phx-change="validate_farm" class="mt-3 space-y-3">
            <.input field={@farm_form[:name]} type="text" label={gettext("Name")} required />
            <.input field={@farm_form[:slug]} type="text" label={gettext("Slug")} required />
            <.input field={@farm_form[:timezone]} type="text" label={gettext("Timezone")} required />
            <.input
              field={@farm_form[:unit_system]}
              type="select"
              label={gettext("Units")}
              options={[{gettext("Metric"), "metric"}, {gettext("Imperial"), "imperial"}]}
            />
            <.input
              field={@farm_form[:plan]}
              type="select"
              label={gettext("Plan")}
              options={[{gettext("Free"), "free"}, {gettext("Pro"), "pro"}]}
            />
            <.input field={@farm_form[:seat_limit]} type="number" label={gettext("Seat limit")} />
            <.button class="btn btn-primary" phx-disable-with={gettext("Saving...")}>{gettext("Save changes")}</.button>
          </.form>
        </section>

        <section class="mt-10">
          <h2 class="text-lg font-semibold">{gettext("Members")}</h2>
          <ul id="members" class="mt-3 divide-y divide-base-300">
            <li :for={m <- @members} id={"member-#{m.id}"} class="py-3 flex justify-between gap-3">
              <div>
                <div class="font-medium">{m.user.email}</div>
                <div class="text-sm text-base-content/60">{m.role}</div>
              </div>
              <button
                :if={
                  Policy.can?(@current_scope, :remove_member) and m.user_id != @current_scope.user.id
                }
                phx-click="remove_member"
                phx-value-id={m.id}
                class="btn btn-sm btn-ghost"
                data-confirm={gettext("Remove this member?")}
              >
                {gettext("Remove")}
              </button>
            </li>
          </ul>
        </section>

        <section :if={Policy.can?(@current_scope, :invite_member)} class="mt-10">
          <h2 class="text-lg font-semibold">
            {gettext("Invite a member")}
            <span class="ml-2 text-sm text-base-content/60 font-normal">
              {gettext("(%{used} / %{cap} seats used)", used: @seats_used, cap: @current_scope.farm.seat_limit)}
            </span>
          </h2>
          <.form for={@invite_form} id="invite-form" phx-submit="invite" class="mt-3 space-y-3">
            <.input field={@invite_form[:email]} type="email" label={gettext("Email")} required />
            <.input
              field={@invite_form[:role]}
              type="select"
              label={gettext("Role")}
              options={[{gettext("Manager"), "manager"}, {gettext("Worker"), "worker"}, {gettext("Veterinarian"), "vet"}]}
            />
            <.button class="btn btn-primary" phx-disable-with={gettext("Sending...")}>{gettext("Send invitation")}</.button>
          </.form>

          <h3 class="mt-6 font-semibold">{gettext("Pending invitations")}</h3>
          <ul id="invitations" class="mt-2 divide-y divide-base-300">
            <li
              :for={inv <- @invitations}
              id={"invitation-#{inv.id}"}
              class="py-2 flex justify-between"
            >
              <span>{inv.email} — {inv.role}</span>
              <button
                phx-click="revoke"
                phx-value-id={inv.id}
                class="btn btn-sm btn-ghost"
              >
                {gettext("Revoke")}
              </button>
            </li>
            <li :if={@invitations == []} class="py-2 text-base-content/60">{gettext("None.")}</li>
          </ul>
        </section>

        <section :if={Policy.can?(@current_scope, :delete_farm)} class="mt-12 border-t border-error/30 pt-6">
          <h2 class="text-lg font-semibold text-error">{gettext("Danger zone")}</h2>
          <p class="mt-2 text-sm text-base-content/70">
            {gettext("Archiving hides this farm from all members immediately. You have 30 days to restore it from your farms list before it is permanently purged.")}
          </p>
          <.form
            for={%{}}
            as={:archive}
            id="archive-form"
            phx-submit="archive_farm"
            class="mt-4 space-y-3"
          >
            <.input
              name="archive[slug_confirm]"
              value=""
              type="text"
              label={gettext("Type the farm slug (%{slug}) to confirm", slug: @current_scope.farm.slug)}
              required
              autocomplete="off"
            />
            <.button
              class="btn btn-error"
              phx-disable-with={gettext("Archiving...")}
              data-confirm={gettext("Archive this farm? Members will lose access immediately.")}
            >
              {gettext("Archive farm")}
            </.button>
          </.form>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    unless Policy.can?(socket.assigns.current_scope, :manage_farm_settings) do
      {:ok, socket |> put_flash(:error, gettext("Not authorized.")) |> redirect(to: "/farms")}
    else
      {:ok, socket |> load() |> assign_invite_form() |> assign_farm_form()}
    end
  end

  @impl true
  def handle_event("validate_farm", %{"farm" => params}, socket) do
    changeset =
      socket.assigns.current_scope.farm
      |> Farms.change_farm(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :farm_form, to_form(changeset, as: "farm"))}
  end

  def handle_event("save_farm", %{"farm" => params}, socket) do
    old_slug = socket.assigns.current_scope.farm.slug

    case Farms.update_farm(socket.assigns.current_scope.farm, params) do
      {:ok, farm} ->
        scope =
          Peggy.Accounts.Scope.put_farm(
            socket.assigns.current_scope,
            farm,
            socket.assigns.current_scope.membership
          )

        socket =
          socket
          |> assign(:current_scope, scope)
          |> put_flash(:info, gettext("Farm saved."))
          |> assign_farm_form(farm)

        if farm.slug != old_slug do
          {:noreply, push_navigate(socket, to: ~p"/farms/#{farm.slug}/settings")}
        else
          {:noreply, socket}
        end

      {:error, changeset} ->
        {:noreply, assign(socket, :farm_form, to_form(changeset, as: "farm"))}
    end
  end

  def handle_event("invite", %{"invitation" => params}, socket) do
    farm = socket.assigns.current_scope.farm
    user = socket.assigns.current_scope.user

    case Farms.invite(farm, params, user, &url(~p"/invitations/#{&1}")) do
      {:ok, _invitation} ->
        {:noreply,
         socket |> put_flash(:info, gettext("Invitation sent.")) |> load() |> assign_invite_form()}

      {:error, :seat_limit_reached} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Seat limit (%{cap}) reached. Raise it in farm settings or remove a member.", cap: farm.seat_limit)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :invite_form, to_form(changeset, as: "invitation"))}
    end
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    invitation = Enum.find(socket.assigns.invitations, &(&1.id == String.to_integer(id)))

    if invitation do
      {:ok, _} = Farms.revoke_invitation(invitation)
      {:noreply, socket |> put_flash(:info, gettext("Invitation revoked.")) |> load()}
    else
      {:noreply, socket}
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

        true ->
          {:ok, _} = Farms.remove_member(membership)
          {:noreply, socket |> put_flash(:info, gettext("Member removed.")) |> load()}
      end
    end
  end

  def handle_event("archive_farm", %{"archive" => %{"slug_confirm" => confirm}}, socket) do
    farm = socket.assigns.current_scope.farm
    user = socket.assigns.current_scope.user

    cond do
      not Policy.can?(socket.assigns.current_scope, :delete_farm) ->
        {:noreply, put_flash(socket, :error, gettext("Not authorized."))}

      String.downcase(String.trim(confirm)) != farm.slug ->
        {:noreply,
         put_flash(socket, :error, gettext("Slug did not match — farm was not archived."))}

      true ->
        case Farms.archive_farm(farm, user) do
          {:ok, _farm} ->
            {:noreply,
             socket
             |> put_flash(:info, gettext("%{farm} archived. Restore within 30 days from your farms list.", farm: farm.name))
             |> push_navigate(to: ~p"/farms")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not archive farm."))}
        end
    end
  end

  defp load(socket) do
    farm = socket.assigns.current_scope.farm

    socket
    |> assign(:members, Farms.list_members(farm))
    |> assign(:invitations, Farms.list_pending_invitations(farm))
    |> assign(:seats_used, Farms.seats_used(farm))
  end

  defp assign_farm_form(socket, farm \\ nil) do
    farm = farm || socket.assigns.current_scope.farm
    assign(socket, :farm_form, to_form(Farms.change_farm(farm), as: "farm"))
  end

  defp assign_invite_form(socket) do
    changeset = Ecto.Changeset.change(%Invitation{role: "worker"})
    assign(socket, :invite_form, to_form(changeset, as: "invitation"))
  end
end
