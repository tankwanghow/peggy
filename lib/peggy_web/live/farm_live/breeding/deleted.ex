defmodule PeggyWeb.FarmLive.Breeding.Deleted do
  @moduledoc """
  Deleted tab of the Breeding section. Read-only audit view of
  soft-deleted services, farrowings, and weanings. Deletions are
  permanent — there is no restore.
  """
  use PeggyWeb, :live_view

  alias Peggy.{Breeding, Policy}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-6xl">
        <.header>
          {gettext("Deleted")}
          <:subtitle>
            {gettext("Audit trail of soft-deleted records. Deletions are permanent.")}
          </:subtitle>
        </.header>

        <section class="mt-4 space-y-8">
          <div>
            <h3 class="font-semibold mb-2">{gettext("Deleted services")}</h3>

            <div class="overflow-x-auto">
              <table class="table table-sm w-full">
                <thead class="text-left text-base-content/60">
                  <tr>
                    <th class="py-2">{gettext("Sow")}</th>
                    <th class="py-2">{gettext("Boar")}</th>
                    <th class="py-2">{gettext("Type")}</th>
                    <th class="py-2">{gettext("Served")}</th>
                    <th class="py-2">{gettext("Result")}</th>
                    <th class="py-2">{gettext("Deleted at")}</th>
                    <th class="py-2">{gettext("By")}</th>
                  </tr>
                </thead>
                <tbody id="deleted-rows" phx-update="stream">
                  <tr
                    :for={{dom_id, s} <- @streams.deleted}
                    id={dom_id}
                    class="border-t border-base-200"
                  >
                    <td class="py-1.5 font-mono font-semibold">
                      {s.sow && s.sow.ear_tag}
                    </td>
                    <td class="py-1.5 font-mono">{s.boar && s.boar.ear_tag}</td>
                    <td class="py-1.5">{s.service_type}</td>
                    <td class="py-1.5">{s.served_at}</td>
                    <td class="py-1.5">{s.result || gettext("open")}</td>
                    <td class="py-1.5 text-base-content/70">
                      {Calendar.strftime(s.deleted_at, "%Y-%m-%d %H:%M")}
                    </td>
                    <td class="py-1.5 text-base-content/70">
                      {s.deleted_by && s.deleted_by.email}
                    </td>
                  </tr>
                </tbody>
              </table>
              <p :if={@deleted_services_empty} class="mt-2 text-sm text-base-content/60">
                {gettext("No deleted services.")}
              </p>
            </div>
          </div>

          <div>
            <h3 class="font-semibold mb-2">{gettext("Deleted farrowings")}</h3>

            <div class="overflow-x-auto">
              <table class="table table-sm w-full">
                <thead class="text-left text-base-content/60">
                  <tr>
                    <th class="py-2">{gettext("Sow")}</th>
                    <th class="py-2">{gettext("Farrowed")}</th>
                    <th class="py-2 text-right">{gettext("Born alive")}</th>
                    <th class="py-2">{gettext("Pen")}</th>
                    <th class="py-2">{gettext("Deleted at")}</th>
                    <th class="py-2">{gettext("By")}</th>
                  </tr>
                </thead>
                <tbody id="deleted-farrowing-rows" phx-update="stream">
                  <tr
                    :for={{dom_id, f} <- @streams.deleted_farrowings}
                    id={dom_id}
                    class="border-t border-base-200"
                  >
                    <td class="py-1.5 font-mono font-semibold">
                      {f.sow && f.sow.ear_tag}
                    </td>
                    <td class="py-1.5">{f.farrowed_at}</td>
                    <td class="py-1.5 text-right font-mono">{f.born_alive}</td>
                    <td class="py-1.5 font-mono">
                      {f.pen && "#{f.pen.house.code}/#{f.pen.code}"}
                    </td>
                    <td class="py-1.5 text-base-content/70">
                      {Calendar.strftime(f.deleted_at, "%Y-%m-%d %H:%M")}
                    </td>
                    <td class="py-1.5 text-base-content/70">
                      {f.deleted_by && f.deleted_by.email}
                    </td>
                  </tr>
                </tbody>
              </table>
              <p :if={@deleted_farrowings_empty} class="mt-2 text-sm text-base-content/60">
                {gettext("No deleted farrowings.")}
              </p>
            </div>
          </div>

          <div>
            <h3 class="font-semibold mb-2">{gettext("Deleted weanings")}</h3>

            <div class="overflow-x-auto">
              <table class="table table-sm w-full">
                <thead class="text-left text-base-content/60">
                  <tr>
                    <th class="py-2">{gettext("Sow")}</th>
                    <th class="py-2">{gettext("Weaned at")}</th>
                    <th class="py-2 text-right">{gettext("Weaned count")}</th>
                    <th class="py-2">{gettext("Dest. pen")}</th>
                    <th class="py-2">{gettext("Deleted at")}</th>
                    <th class="py-2">{gettext("By")}</th>
                  </tr>
                </thead>
                <tbody id="deleted-weaning-rows" phx-update="stream">
                  <tr
                    :for={{dom_id, w} <- @streams.deleted_weanings}
                    id={dom_id}
                    class="border-t border-base-200"
                  >
                    <td class="py-1.5 font-mono font-semibold">
                      {w.farrowing && w.farrowing.sow && w.farrowing.sow.ear_tag}
                    </td>
                    <td class="py-1.5">{w.weaned_at}</td>
                    <td class="py-1.5 text-right">{w.weaned_count}</td>
                    <td class="py-1.5 font-mono">
                      {w.destination_pen &&
                        "#{w.destination_pen.house.code}/#{w.destination_pen.code}"}
                    </td>
                    <td class="py-1.5 text-base-content/70">
                      {Calendar.strftime(w.deleted_at, "%Y-%m-%d %H:%M")}
                    </td>
                    <td class="py-1.5 text-base-content/70">
                      {w.deleted_by && w.deleted_by.email}
                    </td>
                  </tr>
                </tbody>
              </table>
              <p :if={@deleted_weanings_empty} class="mt-2 text-sm text-base-content/60">
                {gettext("No deleted weanings.")}
              </p>
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     socket
     |> assign(can_record: Policy.can?(scope, :record_breeding))
     |> stream_configure(:deleted, dom_id: &"deleted-#{&1.id}")
     |> stream_configure(:deleted_farrowings, dom_id: &"deleted-farrowing-#{&1.id}")
     |> stream_configure(:deleted_weanings, dom_id: &"deleted-weaning-#{&1.id}")
     |> stream(:deleted, [])
     |> stream(:deleted_farrowings, [])
     |> stream(:deleted_weanings, [])}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, load_rows(socket)}
  end

  defp load_rows(socket) do
    scope = socket.assigns.current_scope
    services = Breeding.list_deleted_services(scope)
    farrowings = Breeding.list_deleted_farrowings(scope)
    weanings = Breeding.list_deleted_weanings(scope)

    socket
    |> assign(
      deleted_services_empty: services == [],
      deleted_farrowings_empty: farrowings == [],
      deleted_weanings_empty: weanings == []
    )
    |> stream(:deleted, services, reset: true)
    |> stream(:deleted_farrowings, farrowings, reset: true)
    |> stream(:deleted_weanings, weanings, reset: true)
  end
end
