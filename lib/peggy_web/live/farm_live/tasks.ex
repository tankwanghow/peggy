defmodule PeggyWeb.FarmLive.Tasks do
  @moduledoc """
  Tasks list — assignable, completable workflow items per farm.

  Phase 8 v1: manual create + bulk complete + reassign + delete.
  No auto-generation yet (a Scheduler GenServer will add scheduled
  tasks like "wean due" / "vax due" in a follow-up).
  """
  use PeggyWeb, :live_view

  alias Peggy.{FarmClock, Farms, Policy, Tasks}
  alias Peggy.Tasks.Task

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-5xl">
        <.header>
          {gettext("Tasks")}
          <:subtitle>
            {gettext("Assignable to-dos for this farm")}
          </:subtitle>
          <:actions>
            <.button
              :if={@can_manage}
              phx-click="new"
              class="btn btn-primary btn-sm"
            >
              <.icon name="hero-plus" class="size-4" /> {gettext("New task")}
            </.button>
          </:actions>
        </.header>

        <%!-- Filter strip --%>
        <form
          phx-change="filter"
          class="mt-3 flex gap-2 items-end overflow-x-auto"
        >
          <.input
            name="status"
            type="select"
            label={gettext("Status")}
            value={@filter_status}
            class="select select-sm"
            options={[
              {gettext("Open"), "open"},
              {gettext("Done"), "done"},
              {gettext("All"), "all"}
            ]}
          />
          <.input
            name="assignee"
            type="select"
            label={gettext("Assignee")}
            value={@filter_assignee}
            class="select select-sm"
            options={assignee_options(@members)}
          />
        </form>

        <%!-- Bulk action bar --%>
        <div
          :if={@can_manage and MapSet.size(@selected) > 0}
          class="mt-3 flex items-center gap-3 rounded-md bg-base-200 px-3 py-2 text-sm"
        >
          <span>
            {gettext("Selected")}: <span class="font-mono">{MapSet.size(@selected)}</span>
          </span>
          <button phx-click="bulk_complete" class="btn btn-success btn-sm">
            <.icon name="hero-check-circle" class="size-4" />
            {gettext("Mark complete")}
          </button>
          <button
            phx-click="clear_selection"
            class="btn btn-ghost btn-sm ml-auto"
          >
            {gettext("Clear")}
          </button>
        </div>

        <%!-- Tasks table --%>
        <div class="mt-4 overflow-x-auto">
          <table class="table table-sm w-full">
            <thead class="text-left text-base-content/60">
              <tr>
                <th :if={@can_manage} class="py-2 w-6"></th>
                <th class="py-2">{gettext("Title")}</th>
                <th class="py-2">{gettext("Kind")}</th>
                <th class="py-2">{gettext("Due")}</th>
                <th class="py-2">{gettext("Assignee")}</th>
                <th class="py-2 w-24"></th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={t <- @tasks}
                class={[
                  "border-t border-base-200",
                  t.completed_at && "text-base-content/40"
                ]}
              >
                <td :if={@can_manage} class="py-2">
                  <input
                    type="checkbox"
                    class="checkbox checkbox-sm"
                    checked={MapSet.member?(@selected, t.id)}
                    phx-click="toggle_select"
                    phx-value-id={t.id}
                    disabled={not is_nil(t.completed_at)}
                  />
                </td>
                <td class="py-2">
                  <span class={t.completed_at && "line-through"}>{t.title}</span>
                  <p :if={t.notes && t.notes != ""} class="text-xs text-base-content/60">
                    {t.notes}
                  </p>
                </td>
                <td class="py-2 text-xs uppercase font-mono">{t.kind}</td>
                <td class={[
                  "py-2 text-sm",
                  due_color(t, @today)
                ]}>
                  {t.due_at || "—"}
                </td>
                <td class="py-2 text-sm">
                  {t.assignee_user && t.assignee_user.email}
                </td>
                <td class="py-2 text-right">
                  <button
                    :if={@can_manage and is_nil(t.completed_at)}
                    phx-click="complete"
                    phx-value-id={t.id}
                    class="btn btn-ghost btn-xs text-success"
                  >
                    {gettext("Done")}
                  </button>
                  <button
                    :if={@can_manage and not is_nil(t.completed_at)}
                    phx-click="uncomplete"
                    phx-value-id={t.id}
                    class="btn btn-ghost btn-xs"
                  >
                    {gettext("Reopen")}
                  </button>
                  <button
                    :if={@can_manage}
                    phx-click="delete"
                    phx-value-id={t.id}
                    data-confirm={gettext("Delete this task?")}
                    class="btn btn-ghost btn-xs text-error/70"
                  >
                    <.icon name="hero-trash" class="size-4" />
                  </button>
                </td>
              </tr>
              <tr :if={@tasks == []}>
                <td colspan="6" class="py-6 text-center text-sm text-base-content/60">
                  {gettext("No tasks match the filters.")}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <%!-- New / edit task modal --%>
        <div
          :if={@form}
          id="task-modal"
          class="fixed inset-0 z-40 bg-black/40 flex items-center justify-center"
          phx-click="cancel"
        >
          <div
            class="bg-base-100 rounded-md p-4 sm:p-6 w-full max-w-lg mx-4"
            phx-click={Phoenix.LiveView.JS.exec("phx-noop", to: "#task-modal-card")}
            id="task-modal-card"
          >
            <h3 class="text-lg font-semibold mb-3">
              {if @form_id, do: gettext("Edit task"), else: gettext("New task")}
            </h3>
            <.form
              for={@form}
              phx-submit="save"
              phx-change="validate"
              class="grid grid-cols-2 gap-x-4 gap-y-2"
            >
              <div class="col-span-2">
                <.input field={@form[:title]} type="text" label={gettext("Title")} />
              </div>
              <.input
                field={@form[:kind]}
                type="select"
                label={gettext("Kind")}
                options={Enum.map(Task.kinds(), &{String.capitalize(&1), &1})}
              />
              <.input field={@form[:due_at]} type="date" label={gettext("Due")} />
              <div class="col-span-2">
                <.input
                  field={@form[:assignee_user_id]}
                  type="select"
                  label={gettext("Assignee")}
                  options={[{gettext("Unassigned"), ""} | member_options(@members)]}
                />
              </div>
              <div class="col-span-2">
                <.input field={@form[:notes]} type="textarea" label={gettext("Notes")} />
              </div>
              <div class="col-span-2 flex justify-end gap-2 pt-2">
                <button type="button" phx-click="cancel" class="btn btn-ghost">
                  {gettext("Cancel")}
                </button>
                <.button class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
                  {gettext("Save")}
                </.button>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ── Mount ──────────────────────────────────────────────────────────

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    members = Farms.list_members(scope.farm)

    {:ok,
     socket
     |> assign(
       page_title: gettext("Tasks"),
       can_manage: Policy.can?(scope, :manage_tasks),
       members: members,
       today: FarmClock.today(scope),
       selected: MapSet.new(),
       form: nil,
       form_id: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = %{
      status: status_param(params["status"]),
      assignee: assignee_param(params["assignee"])
    }

    {:noreply,
     socket
     |> assign(filter_status: filters.status, filter_assignee: filters.assignee)
     |> load_tasks()}
  end

  # ── Events ─────────────────────────────────────────────────────────

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply,
     push_patch(socket,
       to:
         ~p"/farms/#{socket.assigns.current_scope.farm.slug}/tasks?#{[status: params["status"] || "open", assignee: params["assignee"] || "any"]}"
     )}
  end

  def handle_event("toggle_select", %{"id" => id}, socket) do
    id = String.to_integer(id)

    selected =
      if MapSet.member?(socket.assigns.selected, id),
        do: MapSet.delete(socket.assigns.selected, id),
        else: MapSet.put(socket.assigns.selected, id)

    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("clear_selection", _, socket),
    do: {:noreply, assign(socket, :selected, MapSet.new())}

  def handle_event("bulk_complete", _, socket) do
    if socket.assigns.can_manage do
      ids = MapSet.to_list(socket.assigns.selected)
      {:ok, n} = Tasks.bulk_complete(socket.assigns.current_scope, ids)

      {:noreply,
       socket
       |> assign(:selected, MapSet.new())
       |> load_tasks()
       |> put_flash(:info, gettext("Completed %{n} task(s).", n: n))}
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("complete", %{"id" => id}, socket) do
    task = Tasks.get_task!(socket.assigns.current_scope, id)
    {:ok, _} = Tasks.complete_task(socket.assigns.current_scope, task)
    {:noreply, socket |> load_tasks() |> put_flash(:info, gettext("Task completed."))}
  end

  def handle_event("uncomplete", %{"id" => id}, socket) do
    task = Tasks.get_task!(socket.assigns.current_scope, id)
    {:ok, _} = Tasks.uncomplete_task(socket.assigns.current_scope, task)
    {:noreply, socket |> load_tasks() |> put_flash(:info, gettext("Task reopened."))}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    task = Tasks.get_task!(socket.assigns.current_scope, id)
    {:ok, _} = Tasks.delete_task(socket.assigns.current_scope, task)
    {:noreply, socket |> load_tasks() |> put_flash(:info, gettext("Task deleted."))}
  end

  def handle_event("new", _, socket) do
    if socket.assigns.can_manage do
      cs = Tasks.change_task(%Task{kind: "ad_hoc", due_at: socket.assigns.today})
      {:noreply, assign(socket, form: to_form(cs, as: :task), form_id: nil)}
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("validate", %{"task" => params}, socket) do
    cs =
      Tasks.change_task(%Task{}, params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(cs, as: :task))}
  end

  def handle_event("save", %{"task" => params}, socket) do
    if socket.assigns.can_manage do
      params = normalize_assignee(params)

      case Tasks.create_task(socket.assigns.current_scope, params) do
        {:ok, _task} ->
          {:noreply,
           socket
           |> assign(form: nil, form_id: nil)
           |> load_tasks()
           |> put_flash(:info, gettext("Task created."))}

        {:error, %Ecto.Changeset{} = cs} ->
          {:noreply, assign(socket, :form, to_form(cs, as: :task))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("cancel", _, socket),
    do: {:noreply, assign(socket, form: nil, form_id: nil)}

  # ── Helpers ────────────────────────────────────────────────────────

  defp load_tasks(socket) do
    scope = socket.assigns.current_scope

    opts = [
      status: socket.assigns.filter_status,
      assignee_user_id: socket.assigns.filter_assignee
    ]

    assign(socket, tasks: Tasks.list_tasks(scope, opts))
  end

  defp status_param("done"), do: :done
  defp status_param("all"), do: :all
  defp status_param(_), do: :open

  defp assignee_param("any"), do: :any
  defp assignee_param(""), do: :any
  defp assignee_param(nil), do: :any
  defp assignee_param("unassigned"), do: nil

  defp assignee_param(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> :any
    end
  end

  defp normalize_assignee(%{"assignee_user_id" => ""} = params),
    do: Map.put(params, "assignee_user_id", nil)

  defp normalize_assignee(params), do: params

  defp assignee_options(members) do
    [
      {gettext("Anyone"), "any"},
      {gettext("Unassigned"), "unassigned"}
      | member_options(members)
    ]
  end

  defp member_options(members) do
    Enum.map(members, fn m -> {m.user.email, to_string(m.user.id)} end)
  end

  defp due_color(%{completed_at: ts}, _today) when not is_nil(ts), do: "text-base-content/40"
  defp due_color(%{due_at: nil}, _today), do: "text-base-content/40"

  defp due_color(%{due_at: due}, today) do
    case Date.compare(due, today) do
      :lt -> "text-error font-semibold"
      :eq -> "text-warning font-semibold"
      _ -> ""
    end
  end
end
