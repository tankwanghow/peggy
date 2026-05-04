defmodule PeggyWeb.MobileLive.Tasks do
  @moduledoc """
  Mobile tasks page. Card-per-task with a one-tap "Done" button on
  each open card; completed tasks fade and move to the bottom of the
  Done filter. New tasks via a sheet, same shape as the desktop form.
  """
  use PeggyWeb, :live_view

  alias Peggy.{FarmClock, Policy, Tasks}
  alias Peggy.Tasks.Task

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_app flash={@flash} current_scope={@current_scope}>
      <div>
        <%!-- Sticky top bar --%>
        <header class="sticky top-0 z-10 bg-base-100 border-b border-base-200 px-3 py-2 flex items-center gap-2">
          <h1 class="font-semibold text-lg flex-1">{gettext("Tasks")}</h1>
          <button
            :if={@can_manage}
            type="button"
            phx-click="new"
            class="btn btn-primary btn-square btn-lg"
            aria-label={gettext("New task")}
          >
            <.icon name="hero-plus" class="size-6" />
          </button>
        </header>

        <%!-- Status pill toggle --%>
        <nav class="px-3 pt-2 flex gap-2 text-xs">
          <.link
            patch={~p"/m/#{@current_scope.farm.slug}/tasks?#{[status: "open"]}"}
            class={pill_class(@filter_status == :open)}
          >
            {gettext("Open")} ({@open_count})
          </.link>
          <.link
            patch={~p"/m/#{@current_scope.farm.slug}/tasks?#{[status: "done"]}"}
            class={pill_class(@filter_status == :done)}
          >
            {gettext("Done")}
          </.link>
        </nav>

        <%!-- Cards --%>
        <ul class="px-3 py-2 space-y-2">
          <li
            :for={t <- @tasks}
            class={[
              "p-4 rounded-xl border bg-base-100 shadow-sm",
              t.completed_at && "border-base-200 opacity-60",
              !t.completed_at && "border-base-300"
            ]}
          >
            <div class="flex items-baseline justify-between gap-2">
              <span class={[
                "font-semibold text-base",
                t.completed_at && "line-through"
              ]}>
                {t.title}
              </span>
              <span class="text-[10px] uppercase tracking-wide text-base-content/50 font-mono">
                {t.kind}
              </span>
            </div>
            <p
              :if={t.notes && t.notes != ""}
              class="mt-1 text-xs text-base-content/60 whitespace-pre-line"
            >
              {t.notes}
            </p>
            <div class="mt-2 flex items-center justify-between text-xs">
              <span class={["font-mono", due_color(t, @today)]}>
                {if t.due_at, do: gettext("Due %{d}", d: t.due_at), else: gettext("No due date")}
              </span>
              <span :if={t.assignee_user} class="text-base-content/60 truncate">
                {t.assignee_user.email}
              </span>
            </div>

            <div class="mt-3 flex gap-2">
              <button
                :if={@can_manage and is_nil(t.completed_at)}
                phx-click="complete"
                phx-value-id={t.id}
                class="btn btn-success flex-1"
              >
                <.icon name="hero-check-circle" class="size-5" />
                {gettext("Done")}
              </button>
              <button
                :if={@can_manage and not is_nil(t.completed_at)}
                phx-click="uncomplete"
                phx-value-id={t.id}
                class="btn btn-ghost flex-1"
              >
                {gettext("Reopen")}
              </button>
              <button
                :if={@can_manage}
                phx-click="delete"
                phx-value-id={t.id}
                data-confirm={gettext("Delete this task?")}
                class="btn btn-ghost btn-square text-error/70"
                aria-label={gettext("Delete task")}
              >
                <.icon name="hero-trash" class="size-5" />
              </button>
            </div>
          </li>
        </ul>

        <p :if={@tasks == []} class="px-4 py-8 text-center text-sm text-base-content/60">
          {if @filter_status == :open,
            do: gettext("No open tasks. Nice work."),
            else: gettext("No completed tasks yet.")}
        </p>

        <%!-- New task sheet --%>
        <div
          :if={@form}
          class="fixed inset-0 z-40 bg-black/40 flex items-end"
          phx-click="cancel"
        >
          <.form
            :let={f}
            for={@form}
            phx-change="validate"
            phx-submit="save"
            phx-click="ignore_click"
            class="w-full bg-base-100 rounded-t-2xl pb-[env(safe-area-inset-bottom)]
                   max-h-[90vh] overflow-y-auto"
          >
            <div class="flex justify-center pt-2 pb-1">
              <div class="w-10 h-1 rounded-full bg-base-300"></div>
            </div>
            <div class="px-4 py-2 border-b border-base-200 text-center">
              <div class="font-semibold">{gettext("New task")}</div>
            </div>

            <div class="px-4 py-4 space-y-3">
              <label class="block">
                <span class="text-xs uppercase text-base-content/60">{gettext("Title")}</span>
                <input
                  type="text"
                  name="task[title]"
                  value={Phoenix.HTML.Form.input_value(f, :title)}
                  required
                  autocomplete="off"
                  class="input input-bordered input-lg w-full mt-1 text-base"
                />
              </label>

              <div class="grid grid-cols-2 gap-3">
                <label class="block">
                  <span class="text-xs uppercase text-base-content/60">{gettext("Kind")}</span>
                  <select
                    name="task[kind]"
                    class="select select-bordered select-lg w-full mt-1"
                  >
                    <option
                      :for={k <- Task.kinds()}
                      value={k}
                      selected={Phoenix.HTML.Form.input_value(f, :kind) == k}
                    >
                      {String.capitalize(k)}
                    </option>
                  </select>
                </label>
                <label class="block">
                  <span class="text-xs uppercase text-base-content/60">{gettext("Due")}</span>
                  <input
                    type="date"
                    name="task[due_at]"
                    value={Phoenix.HTML.Form.input_value(f, :due_at)}
                    class="input input-bordered input-lg w-full mt-1"
                  />
                </label>
              </div>

              <label class="block">
                <span class="text-xs uppercase text-base-content/60">{gettext("Notes")}</span>
                <textarea
                  name="task[notes]"
                  rows="2"
                  class="textarea textarea-bordered w-full mt-1"
                >{Phoenix.HTML.Form.input_value(f, :notes)}</textarea>
              </label>

              <div class="grid grid-cols-2 gap-3 pt-2">
                <button type="button" phx-click="cancel" class="btn btn-lg btn-ghost">
                  {gettext("Cancel")}
                </button>
                <button
                  type="submit"
                  phx-disable-with={gettext("Saving…")}
                  class="btn btn-lg btn-primary"
                >
                  {gettext("Create")}
                </button>
              </div>
            </div>
          </.form>
        </div>
      </div>
    </Layouts.mobile_app>
    """
  end

  # ── Mount ──────────────────────────────────────────────────────────

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     assign(socket,
       page_title: gettext("Tasks"),
       can_manage: Policy.can?(scope, :manage_tasks),
       today: FarmClock.today(scope),
       form: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    status = status_param(params["status"])
    scope = socket.assigns.current_scope

    tasks = Tasks.list_tasks(scope, status: status, limit: 100)
    open_count = Tasks.count_tasks(scope, status: :open)

    {:noreply, assign(socket, filter_status: status, tasks: tasks, open_count: open_count)}
  end

  # ── Events ─────────────────────────────────────────────────────────

  @impl true
  def handle_event("ignore_click", _, socket), do: {:noreply, socket}

  def handle_event("complete", %{"id" => id}, socket) do
    if socket.assigns.can_manage do
      task = Tasks.get_task!(socket.assigns.current_scope, id)
      {:ok, _} = Tasks.complete_task(socket.assigns.current_scope, task)

      {:noreply,
       socket
       |> reload()
       |> put_flash(:info, gettext("Task completed."))}
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("uncomplete", %{"id" => id}, socket) do
    if socket.assigns.can_manage do
      task = Tasks.get_task!(socket.assigns.current_scope, id)
      {:ok, _} = Tasks.uncomplete_task(socket.assigns.current_scope, task)
      {:noreply, socket |> reload() |> put_flash(:info, gettext("Task reopened."))}
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    if socket.assigns.can_manage do
      task = Tasks.get_task!(socket.assigns.current_scope, id)
      {:ok, _} = Tasks.delete_task(socket.assigns.current_scope, task)
      {:noreply, socket |> reload() |> put_flash(:info, gettext("Task deleted."))}
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("new", _, socket) do
    if socket.assigns.can_manage do
      cs = Tasks.change_task(%Task{kind: "ad_hoc", due_at: socket.assigns.today})
      {:noreply, assign(socket, :form, to_form(cs, as: :task))}
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("validate", %{"task" => params}, socket) do
    cs = Tasks.change_task(%Task{}, params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(cs, as: :task))}
  end

  def handle_event("save", %{"task" => params}, socket) do
    if socket.assigns.can_manage do
      case Tasks.create_task(socket.assigns.current_scope, params) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:form, nil)
           |> reload()
           |> put_flash(:info, gettext("Task created."))}

        {:error, %Ecto.Changeset{} = cs} ->
          {:noreply, assign(socket, :form, to_form(cs, as: :task))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  def handle_event("cancel", _, socket), do: {:noreply, assign(socket, :form, nil)}

  # ── Helpers ────────────────────────────────────────────────────────

  defp reload(socket) do
    scope = socket.assigns.current_scope

    assign(socket,
      tasks: Tasks.list_tasks(scope, status: socket.assigns.filter_status, limit: 100),
      open_count: Tasks.count_tasks(scope, status: :open)
    )
  end

  defp status_param("done"), do: :done
  defp status_param(_), do: :open

  defp pill_class(true),
    do: "px-3 py-1 rounded-full bg-primary text-primary-content font-semibold"

  defp pill_class(false),
    do: "px-3 py-1 rounded-full border border-base-300 text-base-content/70"

  defp due_color(%{completed_at: ts}, _today) when not is_nil(ts), do: "text-base-content/40"
  defp due_color(%{due_at: nil}, _today), do: "text-base-content/40"

  defp due_color(%{due_at: due}, today) do
    case Date.compare(due, today) do
      :lt -> "text-error font-semibold"
      :eq -> "text-warning font-semibold"
      _ -> "text-base-content/70"
    end
  end
end
