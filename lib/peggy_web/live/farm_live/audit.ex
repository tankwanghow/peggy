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
              {gettext("All"), ""} | Enum.map(~w(farm house pen animal), &{String.capitalize(&1), &1})
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
              <th class="py-2 pr-4">{gettext("When")}</th>
              <th class="py-2 pr-4">{gettext("Actor")}</th>
              <th class="py-2 pr-4">{gettext("Action")}</th>
              <th class="py-2 pr-4">{gettext("Entity")}</th>
              <th class="py-2">{gettext("Changes")}</th>
            </tr>
          </thead>
          <tbody id="audit-rows" phx-update="stream">
            <tr
              :for={{dom_id, row} <- @streams.audit}
              id={dom_id}
              class="border-t border-base-200 align-top"
            >
              <td class="py-2 pr-4 whitespace-nowrap">
                {Calendar.strftime(row.inserted_at, "%Y-%m-%d %H:%M:%S")}
              </td>
              <td class="py-2 pr-4 truncate max-w-48">
                {row.actor_user && row.actor_user.email}
              </td>
              <td class="py-2 pr-4 font-mono">{row.action}</td>
              <td class="py-2 pr-4 whitespace-nowrap">
                {row.entity_type}#{row.entity_id}
              </td>
              <td class="py-2 font-mono text-xs">
                <dl class="space-y-0.5">
                  <div :for={{field, value} <- row.changes} class="flex gap-1">
                    <dt class="text-base-content/60 shrink-0">{field}:</dt>
                    <dd>{format_value(value)}</dd>
                  </div>
                </dl>
              </td>
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

  defp format_value(nil), do: ""

  defp format_value(map) when is_map(map) and not is_struct(map) do
    Jason.encode!(map)
  end

  defp format_value(list) when is_list(list) do
    if Enum.all?(list, &scalar?/1) do
      Enum.join(list, ", ")
    else
      Jason.encode!(list)
    end
  end

  defp format_value(value), do: "#{value}"

  defp scalar?(v) when is_binary(v) or is_number(v) or is_atom(v), do: true
  defp scalar?(_), do: false
end
