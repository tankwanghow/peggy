defmodule PeggyWeb.FarmLive.Index do
  use PeggyWeb, :live_view

  alias Peggy.Farms
  alias Peggy.Farms.Farm

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-2xl">
        <.header>
          {gettext("Your farms")}
          <:subtitle>{gettext("Pick a farm to enter, or create a new one.")}</:subtitle>
        </.header>

        <section :if={@pending_invitations != []} class="mt-6">
          <h2 class="text-lg font-semibold">{gettext("Pending invitations")}</h2>
          <ul id="pending-invitations" class="mt-2 divide-y divide-base-300">
            <li
              :for={inv <- @pending_invitations}
              id={"pending-invitation-#{inv.id}"}
              class="py-3 flex items-center justify-between gap-3"
            >
              <div>
                <div class="font-medium">{inv.farm.name}</div>
                <div class="text-sm text-base-content/60">
                  {gettext("Role: %{role}", role: inv.role)}
                </div>
              </div>
              <button
                phx-click="accept_invitation"
                phx-value-id={inv.id}
                class="btn btn-primary btn-sm"
              >
                {gettext("Accept")}
              </button>
            </li>
          </ul>
        </section>

        <ul id="farms" class="mt-6 divide-y divide-base-300">
          <li
            :for={{farm, membership} <- @memberships}
            id={"farm-#{farm.id}"}
            class="py-3 flex items-center justify-between gap-3"
          >
            <div class="flex items-center gap-2">
              <span class="font-medium">{farm.name}</span>
              <span
                :if={membership.is_default}
                class="badge badge-sm badge-primary"
                title={gettext("Your default farm")}
              >
                {gettext("Default")}
              </span>
            </div>
            <div class="flex items-center gap-2">
              <button
                :if={not membership.is_default}
                phx-click="set_default"
                phx-value-farm-id={farm.id}
                class="btn btn-ghost btn-sm"
              >
                {gettext("Set as default")}
              </button>
              <.link navigate={~p"/farms/#{farm.slug}"} class="btn btn-primary btn-sm">
                {gettext("Enter")}
              </.link>
            </div>
          </li>
          <li :if={@memberships == []} class="py-6 text-base-content/60">
            {gettext("No farms yet.")}
          </li>
        </ul>

        <section :if={@archived_farms != []} class="mt-10">
          <h2 class="text-lg font-semibold">{gettext("Archived farms")}</h2>
          <p class="text-sm text-base-content/60 mt-1">
            {gettext(
              "Archived farms are hidden from members and will be permanently purged 30 days after archival."
            )}
          </p>
          <ul id="archived-farms" class="mt-3 divide-y divide-base-300">
            <li
              :for={f <- @archived_farms}
              id={"archived-farm-#{f.id}"}
              class="py-3 flex items-center justify-between gap-3"
            >
              <div>
                <div class="font-medium">{f.name}</div>
                <div class="text-sm text-base-content/60">
                  {gettext("Archived %{when}", when: Calendar.strftime(f.deleted_at, "%Y-%m-%d"))}
                </div>
              </div>
              <button
                phx-click="restore_farm"
                phx-value-id={f.id}
                class="btn btn-ghost btn-sm"
                data-confirm={gettext("Restore this farm?")}
              >
                {gettext("Restore")}
              </button>
            </li>
          </ul>
        </section>

        <div class="mt-10">
          <.header>{gettext("Create a farm")}</.header>
          <.form
            for={@form}
            id="new-farm-form"
            phx-submit="save"
            phx-change="validate"
            class="mt-4 space-y-3"
          >
            <.input field={@form[:name]} type="text" label={gettext("Name")} required />
            <.input
              field={@form[:slug]}
              type="text"
              label={gettext("Slug")}
              class="w-full input font-mono"
              required
              placeholder="lowercase-with-hyphens"
            />
            <.input
              field={@form[:timezone]}
              type="select"
              label={gettext("Timezone")}
              options={Peggy.Timezones.options()}
            />
            <.input
              field={@form[:unit_system]}
              type="select"
              label={gettext("Units")}
              options={[{gettext("Metric"), "metric"}, {gettext("Imperial"), "imperial"}]}
            />
            <.button phx-disable-with={gettext("Creating...")} class="btn btn-primary">
              {gettext("Create farm")}
            </.button>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    changeset = Farms.change_farm(%Farm{timezone: user.timezone, unit_system: "metric"})
    {:ok, socket |> load() |> assign_form(changeset)}
  end

  defp load(socket) do
    user = socket.assigns.current_scope.user

    socket
    |> assign(:memberships, Farms.list_memberships_with_farms(user))
    |> assign(:pending_invitations, Farms.list_pending_invitations_for_email(user.email))
    |> assign(:archived_farms, Farms.list_archived_farms_for_owner(user))
  end

  @impl true
  def handle_event("restore_farm", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    farm = Enum.find(socket.assigns.archived_farms, &(&1.id == String.to_integer(id)))

    with %_{} <- farm,
         %{role: "owner"} <- Farms.get_membership(user, farm),
         {:ok, restored} <- Farms.restore_farm(farm) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("%{farm} restored.", farm: restored.name))
       |> load()}
    else
      _ ->
        {:noreply, put_flash(socket, :error, gettext("Could not restore farm."))}
    end
  end

  def handle_event("accept_invitation", %{"id" => id}, socket) do
    invitation =
      Enum.find(socket.assigns.pending_invitations, &(&1.id == String.to_integer(id)))

    case invitation && Farms.accept_invitation(invitation, socket.assigns.current_scope.user) do
      {:ok, _membership} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Welcome to %{farm}!", farm: invitation.farm.name))
         |> push_navigate(to: ~p"/farms/#{invitation.farm.slug}")}

      {:error, :seat_limit_reached} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("That farm is full — ask an owner to free up a seat."))
         |> load()}

      _ ->
        {:noreply, socket |> put_flash(:error, gettext("Could not accept invitation.")) |> load()}
    end
  end

  def handle_event("set_default", %{"farm-id" => farm_id}, socket) do
    user = socket.assigns.current_scope.user

    {farm, _} =
      Enum.find(socket.assigns.memberships, fn {f, _} -> f.id == String.to_integer(farm_id) end)

    case Farms.set_default_farm(user, farm) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("%{farm} is now your default farm.", farm: farm.name))
         |> load()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not set default."))}
    end
  end

  def handle_event("validate", %{"farm" => params}, socket) do
    changeset =
      %Farm{} |> Farms.change_farm(params) |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"farm" => params}, socket) do
    case Farms.create_farm(socket.assigns.current_scope.user, params) do
      {:ok, farm} ->
        {:noreply, push_navigate(socket, to: ~p"/farms/#{farm.slug}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: "farm"))
  end
end
