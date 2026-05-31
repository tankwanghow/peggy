defmodule PeggyWeb.FarmLive.Reports.Inferred do
  use PeggyWeb, :live_view

  alias Peggy.Policy
  alias Peggy.Reports

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-6xl">
        <.header>
          {gettext("Inferred / backfilled rows")}
          <:subtitle>
            {gettext(
              "Sows and services the importer auto-created via the back-fill cascade. Eyeball-verify after a legacy import."
            )}
          </:subtitle>
          <:actions>
            <.link
              navigate={~p"/farms/#{@current_scope.farm.slug}/reports"}
              class="btn btn-outline btn-sm"
            >
              <.icon name="hero-arrow-left-micro" class="size-3" /> {gettext("Reports")}
            </.link>
          </:actions>
        </.header>

        <section class="mt-6">
          <div class="flex items-baseline justify-between">
            <h2 class="text-lg font-semibold">{gettext("Inferred sows")}</h2>
            <span class="text-sm text-base-content/60">
              {gettext("%{n} rows", n: length(@sows))}
            </span>
          </div>
          <p class="mt-1 text-sm text-base-content/60">
            {gettext(
              "Created when a service / farrowing / weaning row referenced an ear-tag not in sows.csv or the database."
            )}
          </p>

          <div
            :if={@sows == []}
            class="mt-3 rounded-lg border border-base-200 p-4 text-sm text-base-content/60"
          >
            {gettext("No inferred sows.")}
          </div>

          <div :if={@sows != []} class="mt-3 overflow-x-auto rounded-lg border border-base-200">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Ear tag")}</th>
                  <th>{gettext("Status")}</th>
                  <th>{gettext("Breed")}</th>
                  <th>{gettext("DOB")}</th>
                  <th>{gettext("Needs review")}</th>
                  <th>{gettext("Created via")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={sow <- @sows}>
                  <td>
                    <.link
                      navigate={~p"/farms/#{@current_scope.farm.slug}/animals/#{sow.id}"}
                      class="link link-hover font-mono"
                    >
                      {sow.ear_tag}
                    </.link>
                  </td>
                  <td>
                    <span class="badge badge-sm">
                      {Peggy.Animals.Animal.status_label(sow.status)}
                    </span>
                  </td>
                  <td>{sow.breed || "—"}</td>
                  <td>{format_date(sow.dob)}</td>
                  <td>
                    <span :if={sow.needs_review} class="badge badge-warning badge-sm">
                      {gettext("review")}
                    </span>
                    <span :if={!sow.needs_review} class="text-base-content/40">—</span>
                  </td>
                  <td class="font-mono text-xs text-base-content/60">{sow.created_via || "—"}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section class="mt-10">
          <div class="flex items-baseline justify-between">
            <h2 class="text-lg font-semibold">{gettext("Inferred services")}</h2>
            <span class="text-sm text-base-content/60">
              {gettext("%{n} rows", n: length(@services))}
            </span>
          </div>
          <p class="mt-1 text-sm text-base-content/60">
            {gettext(
              "Created when a farrowing or weaning didn't match any service inside the gestation window. The 'farrowed at' column shows whether the inferred service did get attached to a real farrowing."
            )}
          </p>

          <div
            :if={@services == []}
            class="mt-3 rounded-lg border border-base-200 p-4 text-sm text-base-content/60"
          >
            {gettext("No inferred services.")}
          </div>

          <div :if={@services != []} class="mt-3 overflow-x-auto rounded-lg border border-base-200">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Sow")}</th>
                  <th>{gettext("Served at")}</th>
                  <th>{gettext("Type")}</th>
                  <th>{gettext("Result")}</th>
                  <th>{gettext("Result at")}</th>
                  <th>{gettext("Farrowed at")}</th>
                  <th>{gettext("Created via")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={s <- @services}>
                  <td>
                    <.link
                      navigate={~p"/farms/#{@current_scope.farm.slug}/animals/#{s.sow_id}"}
                      class="link link-hover font-mono"
                    >
                      {s.sow_ear_tag}
                    </.link>
                  </td>
                  <td>{format_date(s.served_at)}</td>
                  <td>{s.service_type}</td>
                  <td>
                    <span :if={s.result} class="badge badge-sm">{s.result}</span>
                    <span :if={!s.result} class="text-base-content/40">—</span>
                  </td>
                  <td>{format_date(s.result_at)}</td>
                  <td>
                    <span :if={s.farrowed_at}>{format_date(s.farrowed_at)}</span>
                    <span :if={!s.farrowed_at} class="text-base-content/40">—</span>
                  </td>
                  <td class="font-mono text-xs text-base-content/60">{s.created_via || "—"}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if Policy.can?(socket.assigns.current_scope, :view_reports) do
      scope = socket.assigns.current_scope

      {:ok,
       socket
       |> assign(
         sows: Reports.list_inferred_sows(scope),
         services: Reports.list_inferred_services(scope)
       )
       |> assign(:page_title, gettext("Inferred rows"))}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("You do not have access to reports."))
       |> redirect(to: ~p"/farms/#{socket.assigns.current_scope.farm.slug}")}
    end
  end

  defp format_date(nil), do: "—"
  defp format_date(%Date{} = d), do: Date.to_iso8601(d)
end
