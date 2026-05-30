defmodule PeggyWeb.FarmLive.Audit do
  use PeggyWeb, :live_view

  alias Peggy.Audit
  alias Peggy.Policy

  @per_page 100

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-5xl">
        <.header>
          {gettext("Audit log")}
          <:subtitle>{gettext("Every change to this farm, newest first.")}</:subtitle>
        </.header>

        <form phx-change="filter" class="mt-4 grid grid-cols-2 md:grid-cols-4 gap-3">
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
          <.input
            name="changes_key"
            value={@filter_changes_key || ""}
            type="select"
            label={gettext("Changes key")}
            options={[{gettext("Any key"), ""} | Enum.map(@change_keys, &{&1, &1})]}
          />
          <.input
            name="changes_value"
            value={@filter_changes_value || ""}
            type="text"
            label={gettext("Changes value contains")}
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
        <.infinite_scroll has_more={@has_more} total={@loaded} id="audit-sentinel" />
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if Policy.can?(socket.assigns.current_scope, :view_audit) do
      scope = socket.assigns.current_scope

      {:ok,
       socket
       |> assign(
         filter_entity: nil,
         filter_action: nil,
         filter_changes_key: nil,
         filter_changes_value: nil,
         change_keys: Audit.list_change_keys(scope)
       )
       |> assign(page: 1, loaded: 0, has_more: false)
       |> stream(:audit, [])
       |> load_rows()}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Not authorized."))
       |> redirect(to: ~p"/farms/#{socket.assigns.current_scope.farm.slug}")}
    end
  end

  @impl true
  def handle_event("filter", params, socket) do
    blank_to_nil = fn v -> if v in [nil, ""], do: nil, else: v end

    {:noreply,
     socket
     |> assign(
       filter_entity: blank_to_nil.(params["entity_type"]),
       filter_action: blank_to_nil.(params["action"]),
       filter_changes_key: blank_to_nil.(params["changes_key"]),
       filter_changes_value: blank_to_nil.(params["changes_value"])
     )
     |> load_rows()}
  end

  def handle_event("load_more", _, socket), do: {:noreply, append_rows(socket)}

  defp load_rows(socket) do
    rows = list(socket.assigns.current_scope, socket, 0)

    socket
    |> assign(page: 1, loaded: length(rows), has_more: length(rows) == @per_page)
    |> stream(:audit, rows, reset: true)
  end

  defp append_rows(socket) do
    next_page = socket.assigns.page + 1
    rows = list(socket.assigns.current_scope, socket, (next_page - 1) * @per_page)

    socket = Enum.reduce(rows, socket, fn r, acc -> stream_insert(acc, :audit, r) end)

    assign(socket,
      page: next_page,
      loaded: socket.assigns.loaded + length(rows),
      has_more: length(rows) == @per_page
    )
  end

  defp list(scope, socket, offset) do
    Audit.list(scope,
      entity_type: socket.assigns.filter_entity,
      action: socket.assigns.filter_action,
      changes_key: socket.assigns.filter_changes_key,
      changes_value: socket.assigns.filter_changes_value,
      limit: @per_page,
      offset: offset
    )
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
