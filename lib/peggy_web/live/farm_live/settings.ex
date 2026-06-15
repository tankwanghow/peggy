defmodule PeggyWeb.FarmLive.Settings do
  use PeggyWeb, :live_view

  alias Peggy.Farms
  alias Peggy.Policy

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-3xl">
        <.header>{gettext("Farm settings - %{name}", name: @current_scope.farm.name)}</.header>

        <section
          :if={
            Peggy.Policy.can?(@current_scope, :view_audit) or
              Peggy.Policy.can?(@current_scope, :import_data) or
              Peggy.Policy.can?(@current_scope, :delete_farm)
          }
          class="mt-6"
        >
          <h2 class="text-lg font-semibold">{gettext("Tools")}</h2>
          <ul class="mt-3 grid gap-3 sm:grid-cols-2">
            <li :if={Peggy.Policy.can?(@current_scope, :import_data)}>
              <.link
                navigate={~p"/farms/#{@current_scope.farm.slug}/admin/import"}
                class="flex items-center gap-3 rounded-md border border-base-200 bg-base-100 p-3 active:bg-base-200 hover:bg-base-200/50"
              >
                <.icon name="hero-arrow-up-tray" class="size-5 text-primary" />
                <div class="flex-1">
                  <div class="font-semibold">{gettext("Import legacy data")}</div>
                  <div class="text-xs text-base-content/60">
                    {gettext("Upload CSVs from another farm-management system.")}
                  </div>
                </div>
                <.icon name="hero-chevron-right-micro" class="size-4 text-base-content/40" />
              </.link>
            </li>
            <li :if={Peggy.Policy.can?(@current_scope, :view_audit)}>
              <.link
                navigate={~p"/farms/#{@current_scope.farm.slug}/audit"}
                class="flex items-center gap-3 rounded-md border border-base-200 bg-base-100 p-3 active:bg-base-200 hover:bg-base-200/50"
              >
                <.icon name="hero-clipboard-document-list" class="size-5 text-base-content/70" />
                <div class="flex-1">
                  <div class="font-semibold">{gettext("Audit log")}</div>
                  <div class="text-xs text-base-content/60">
                    {gettext("Immutable history of every change on this farm.")}
                  </div>
                </div>
                <.icon name="hero-chevron-right-micro" class="size-4 text-base-content/40" />
              </.link>
            </li>
            <li :if={Peggy.Policy.can?(@current_scope, :delete_farm)}>
              <.link
                navigate={~p"/farms/#{@current_scope.farm.slug}/admin/backup"}
                class="flex items-center gap-3 rounded-md border border-base-200 bg-base-100 p-3 active:bg-base-200 hover:bg-base-200/50"
              >
                <.icon name="hero-archive-box-arrow-down" class="size-5 text-primary" />
                <div class="flex-1">
                  <div class="font-semibold">{gettext("Backup & restore")}</div>
                  <div class="text-xs text-base-content/60">
                    {gettext("Download a full snapshot or restore one into a new farm.")}
                  </div>
                </div>
                <.icon name="hero-chevron-right-micro" class="size-4 text-base-content/40" />
              </.link>
            </li>
          </ul>
        </section>

        <section class="mt-8">
          <h2 class="text-lg font-semibold">{gettext("Farm profile")}</h2>
          <.form
            for={@farm_form}
            id="farm-form"
            phx-submit="save_farm"
            phx-change="validate_farm"
            class="mt-3 space-y-3"
          >
            <.input field={@farm_form[:name]} type="text" label={gettext("Name")} required />
            <.input
              field={@farm_form[:slug]}
              type="text"
              label={gettext("Slug")}
              class="w-full input font-mono"
              required
            />
            <.input
              field={@farm_form[:timezone]}
              type="select"
              label={gettext("Timezone")}
              options={Peggy.Timezones.options()}
              required
            />
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
            <div class="rounded-md border border-base-300 p-3">
              <.input
                field={@farm_form[:simulated_today]}
                type="date"
                label={gettext("Simulated today")}
              />
              <p class="mt-1 text-xs text-base-content/60">
                {gettext(
                  "Pin a date the app uses for age, lactation length, gestation day, and other date-of-day calculations. Leave blank to use the real date. Audit timestamps and record-creation times always use real time."
                )}
              </p>
            </div>
            <.button class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
              {gettext("Save changes")}
            </.button>
          </.form>
        </section>

        <section class="mt-10">
          <h2 class="text-lg font-semibold">{gettext("Breeding parameters")}</h2>
          <p class="mt-1 text-sm text-base-content/70">
            {gettext(
              "Tune the reproductive cycle to your herd. Changes apply immediately to new and existing services — a sow gestating today will use the new gestation length for her expected farrow date."
            )}
          </p>

          <.form
            for={@breeding_form}
            id="breeding-form"
            phx-submit="save_breeding"
            phx-change="validate_breeding"
            class="mt-3 grid sm:grid-cols-2 gap-4"
          >
            <label class="form-control">
              <.input
                field={@breeding_form[:gestation_days]}
                type="number"
                label={gettext("Gestation length (days)")}
                min="100"
                max="130"
              />
              <span class="text-xs text-base-content/60 mt-1">
                {gettext("Default 114. Drives expected farrow date and due-window filters.")}
              </span>
            </label>

            <label class="form-control">
              <.input
                field={@breeding_form[:gestation_tolerance_days]}
                type="number"
                label={gettext("Gestation tolerance (±days)")}
                min="0"
                max="7"
              />
              <span class="text-xs text-base-content/60 mt-1">
                {gettext(
                  "Default 3. Farrowing must land within ±this many days of served_at + gestation."
                )}
              </span>
            </label>

            <label class="form-control">
              <.input
                field={@breeding_form[:lactation_days]}
                type="number"
                label={gettext("Lactation length (days)")}
                min="14"
                max="42"
              />
              <span class="text-xs text-base-content/60 mt-1">
                {gettext("Default 24. Used to back-fill farrow date when only a wean date is known.")}
              </span>
            </label>

            <label class="form-control">
              <.input
                field={@breeding_form[:wean_due_days]}
                type="number"
                label={gettext("Wean-due alert (days)")}
                min="14"
                max="42"
              />
              <span class="text-xs text-base-content/60 mt-1">
                {gettext("Default 21. Lactating sows older than this trigger a “wean due” task.")}
              </span>
            </label>

            <label class="form-control">
              <.input
                field={@breeding_form[:minimum_sow_age_days]}
                type="number"
                label={gettext("Minimum sow age (days)")}
                min="180"
                max="540"
              />
              <span class="text-xs text-base-content/60 mt-1">
                {gettext("Default 365. DOB offset for back-filled (inferred) sows.")}
              </span>
            </label>

            <label class="form-control">
              <.input
                field={@breeding_form[:collapse_window_days]}
                type="number"
                label={gettext("Heat clustering window (days)")}
                min="1"
                max="14"
              />
              <span class="text-xs text-base-content/60 mt-1">
                {gettext(
                  "Default 7. Re-services within this window collapse into the prior service event instead of creating a new row."
                )}
              </span>
            </label>

            <label class="form-control sm:col-span-2">
              <.input
                field={@breeding_form[:recent_weaner_batch_days]}
                type="number"
                label={gettext("Weaner batch recency (days)")}
                min="14"
                max="180"
              />
              <span class="text-xs text-base-content/60 mt-1">
                {gettext(
                  "Default 60. How far back the weaning form's batch picker looks when suggesting pools to consolidate into."
                )}
              </span>
            </label>

            <label class="form-control">
              <.input
                field={@breeding_form[:weaner_to_grower_days]}
                type="number"
                label={gettext("Weaner → Grower (days from birth)")}
                min="35"
                max="120"
              />
              <span class="text-xs text-base-content/60 mt-1">
                {gettext(
                  "Default 70. Weaner batches older than this surface in the “Promote batch animals” triage screen."
                )}
              </span>
            </label>

            <label class="form-control">
              <.input
                field={@breeding_form[:grower_to_finisher_days]}
                type="number"
                label={gettext("Grower → Finisher (days from birth)")}
                min="70"
                max="200"
              />
              <span class="text-xs text-base-content/60 mt-1">
                {gettext("Default 120. Grower batches older than this are flagged for promotion.")}
              </span>
            </label>

            <label class="form-control sm:col-span-2">
              <.input
                field={@breeding_form[:finisher_overdue_days]}
                type="number"
                label={gettext("Finisher overdue (days from birth)")}
                min="140"
                max="365"
              />
              <span class="text-xs text-base-content/60 mt-1">
                {gettext(
                  "Default 200. Finisher batches still on farm past this age are flagged for departure (sale / slaughter)."
                )}
              </span>
            </label>

            <div class="sm:col-span-2">
              <.button class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
                {gettext("Save breeding parameters")}
              </.button>
            </div>
          </.form>
        </section>

        <section
          :if={Policy.can?(@current_scope, :delete_farm)}
          class="mt-12 border-t border-error/30 pt-6"
        >
          <h2 class="text-lg font-semibold text-error">{gettext("Danger zone")}</h2>
          <p class="mt-2 text-sm text-base-content/70">
            {gettext(
              "Archiving hides this farm from all members immediately. You have 30 days to restore it from your farms list before it is permanently purged."
            )}
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
              label={
                gettext("Type the farm slug (%{slug}) to confirm", slug: @current_scope.farm.slug)
              }
              class="w-full input font-mono"
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
      {:ok,
       socket
       |> assign_farm_form()
       |> assign_breeding_form()}
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

  def handle_event("validate_breeding", %{"farm" => params}, socket) do
    changeset =
      socket.assigns.current_scope.farm
      |> Farms.change_breeding_parameters(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :breeding_form, to_form(changeset, as: "farm"))}
  end

  def handle_event("save_breeding", %{"farm" => params}, socket) do
    case Farms.update_breeding_parameters(socket.assigns.current_scope.farm, params) do
      {:ok, farm} ->
        scope =
          Peggy.Accounts.Scope.put_farm(
            socket.assigns.current_scope,
            farm,
            socket.assigns.current_scope.membership
          )

        {:noreply,
         socket
         |> assign(:current_scope, scope)
         |> assign_breeding_form(farm)
         |> put_flash(:info, gettext("Breeding parameters saved."))}

      {:error, changeset} ->
        {:noreply, assign(socket, :breeding_form, to_form(changeset, as: "farm"))}
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
             |> put_flash(
               :info,
               gettext("%{farm} archived. Restore within 30 days from your farms list.",
                 farm: farm.name
               )
             )
             |> push_navigate(to: ~p"/farms")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not archive farm."))}
        end
    end
  end

  defp assign_farm_form(socket, farm \\ nil) do
    farm = farm || socket.assigns.current_scope.farm
    assign(socket, :farm_form, to_form(Farms.change_farm(farm), as: "farm"))
  end

  defp assign_breeding_form(socket, farm \\ nil) do
    farm = farm || socket.assigns.current_scope.farm

    assign(
      socket,
      :breeding_form,
      to_form(Farms.change_breeding_parameters(farm), as: "farm")
    )
  end
end
