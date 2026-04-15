defmodule PeggyWeb.FarmLive.Audit do
  use PeggyWeb, :live_view

  alias Peggy.Audit
  alias Peggy.Policy

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-5xl">
        <.header>
          {gettext("Audit log")}
          <:subtitle>{gettext("Every change to this farm, newest first.")}</:subtitle>
        </.header>

        <form phx-change="filter" class="mt-4 flex gap-3">
          <.input
            name="entity_type"
            value={@filter_entity || ""}
            type="select"
            label={gettext("Entity")}
            options={[
              {gettext("All"), ""} | Enum.map(~w(farm house pen), &{String.capitalize(&1), &1})
            ]}
          />
          <.input
            name="action"
            value={@filter_action || ""}
            type="text"
            label={gettext("Action contains")}
          />
        </form>

        <table class="mt-6 w-full text-sm">
          <thead class="text-left text-base-content/60">
            <tr>
              <th class="py-2">{gettext("When")}</th>
              <th>{gettext("Actor")}</th>
              <th>{gettext("Action")}</th>
              <th>{gettext("Entity")}</th>
              <th>{gettext("Changes")}</th>
            </tr>
          </thead>
          <tbody id="audit-rows" phx-update="stream">
            <tr
              :for={{dom_id, row} <- @streams.audit}
              id={dom_id}
              class="border-t border-base-200 align-top"
            >
              <td class="py-2 whitespace-nowrap">
                {Calendar.strftime(row.inserted_at, "%Y-%m-%d %H:%M:%S")}
              </td>
              <td>{row.actor_user && row.actor_user.email}</td>
              <td class="font-mono">{row.action}</td>
              <td>{row.entity_type}#{row.entity_id}</td>
              <td class="font-mono text-xs">{inspect(row.changes)}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if Policy.can?(socket.assigns.current_scope, :view_audit) do
      {:ok,
       socket
       |> assign(filter_entity: nil, filter_action: nil)
       |> stream(:audit, list(socket.assigns.current_scope, nil, nil))}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Not authorized."))
       |> redirect(to: ~p"/farms/#{socket.assigns.current_scope.farm.slug}")}
    end
  end

  @impl true
  def handle_event("filter", %{"entity_type" => et, "action" => act}, socket) do
    et = if et == "", do: nil, else: et
    act = if act == "", do: nil, else: act

    {:noreply,
     socket
     |> assign(filter_entity: et, filter_action: act)
     |> stream(:audit, list(socket.assigns.current_scope, et, act), reset: true)}
  end

  defp list(scope, entity_type, action) do
    Audit.list(scope, entity_type: entity_type, action: action, limit: 500)
  end
end
