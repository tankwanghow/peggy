defmodule Peggy.Tasks do
  @moduledoc """
  Workflow tasks — assignable, completable to-do items scoped to a
  farm. Distinct from the action_list KPIs in `Peggy.Reports`, which
  are computed on the fly from breeding state.

  Phase 8 v1: manual create / list / complete / uncomplete / delete.
  Auto-generation via a scheduler and notifications (email + PubSub)
  land in a follow-up.
  """

  import Ecto.Query

  alias Peggy.{Audit, Repo}
  alias Peggy.Accounts.Scope
  alias Peggy.Tasks.Task

  @doc """
  Lists tasks for the current farm.

  Options:
    * `:status` — `:open` (default), `:done`, or `:all`
    * `:assignee_user_id` — filter to one assignee, or `:any` (default)
    * `:limit` / `:offset` — pagination
    * `:order` — `:due_first` (default — overdue first, then by due_at,
      then created_at desc) or `:created_desc`
  """
  def list_tasks(%Scope{farm: %{id: farm_id}}, opts \\ []) do
    status = Keyword.get(opts, :status, :open)
    assignee = Keyword.get(opts, :assignee_user_id, :any)
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    order = Keyword.get(opts, :order, :due_first)

    from(t in Task, where: t.farm_id == ^farm_id)
    |> filter_status(status)
    |> filter_assignee(assignee)
    |> order_tasks(order)
    |> limit(^limit)
    |> offset(^offset)
    |> preload([:assignee_user, :created_by_user, :completed_by_user])
    |> Repo.all()
  end

  def count_tasks(%Scope{farm: %{id: farm_id}}, opts \\ []) do
    status = Keyword.get(opts, :status, :open)
    assignee = Keyword.get(opts, :assignee_user_id, :any)

    from(t in Task, where: t.farm_id == ^farm_id)
    |> filter_status(status)
    |> filter_assignee(assignee)
    |> Repo.aggregate(:count, :id)
  end

  defp filter_status(q, :all), do: q
  defp filter_status(q, :open), do: from(t in q, where: is_nil(t.completed_at))
  defp filter_status(q, :done), do: from(t in q, where: not is_nil(t.completed_at))

  defp filter_assignee(q, :any), do: q
  defp filter_assignee(q, nil), do: from(t in q, where: is_nil(t.assignee_user_id))

  defp filter_assignee(q, user_id) when is_integer(user_id),
    do: from(t in q, where: t.assignee_user_id == ^user_id)

  # Open tasks: overdue first (due_at non-null and ≤ today via NULLs LAST
  # ordering), then by due_at ascending, then created_at desc.
  defp order_tasks(q, :due_first) do
    from(t in q,
      order_by: [
        asc_nulls_last: t.due_at,
        desc: t.inserted_at
      ]
    )
  end

  defp order_tasks(q, :created_desc), do: from(t in q, order_by: [desc: t.inserted_at])

  @doc "Builds a blank task changeset for forms."
  def change_task(%Task{} = task, attrs \\ %{}), do: Task.changeset(task, attrs)

  def get_task!(%Scope{farm: %{id: farm_id}}, id),
    do: Repo.get_by!(Task, id: id, farm_id: farm_id)

  @doc """
  Creates a task. The current user is recorded as `created_by_user_id`.
  """
  def create_task(%Scope{farm: farm, user: user} = scope, attrs) do
    attrs =
      attrs
      |> stringify()
      |> Map.put("farm_id", farm.id)
      |> Map.put_new("created_by_user_id", user && user.id)

    case %Task{} |> Task.changeset(attrs) |> Repo.insert() do
      {:ok, task} ->
        Audit.log_now!(scope, "task.created",
          entity_type: :task,
          entity_id: task.id,
          changes: %{"title" => task.title, "kind" => task.kind}
        )

        {:ok, task}

      err ->
        err
    end
  end

  @doc """
  Inserts a task only if no open task already exists for the same
  `(farm, kind, ref_entity_type, ref_entity_id)` triple. Used by the
  scheduler so an hourly tick doesn't create duplicate auto-tasks.

  Returns `{:ok, :created, task}`, `{:ok, :exists, task}`, or `{:error, cs}`.
  """
  def find_or_create_open_task(%Scope{farm: farm, user: user} = scope, attrs) do
    attrs = stringify(attrs)
    kind = attrs["kind"]
    ref_type = attrs["ref_entity_type"]
    ref_id = attrs["ref_entity_id"]

    existing =
      from(t in Task,
        where:
          t.farm_id == ^farm.id and
            t.kind == ^kind and
            is_nil(t.completed_at) and
            ((is_nil(^ref_type) and is_nil(t.ref_entity_type)) or t.ref_entity_type == ^ref_type) and
            ((is_nil(^ref_id) and is_nil(t.ref_entity_id)) or t.ref_entity_id == ^ref_id),
        limit: 1
      )
      |> Repo.one()

    cond do
      not is_nil(existing) ->
        {:ok, :exists, existing}

      true ->
        attrs =
          attrs
          |> Map.put("farm_id", farm.id)
          |> Map.put_new("created_by_user_id", user && user.id)

        case %Task{} |> Task.changeset(attrs) |> Repo.insert() do
          {:ok, task} ->
            Audit.log_now!(scope, "task.created.scheduled",
              entity_type: :task,
              entity_id: task.id,
              changes: %{"title" => task.title, "kind" => task.kind}
            )

            {:ok, :created, task}

          err ->
            err
        end
    end
  end

  @doc """
  Updates a task (typically to reassign / re-title / change due date).
  """
  def update_task(%Scope{} = scope, %Task{} = task, attrs) do
    task
    |> Task.changeset(stringify(attrs))
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        Audit.log_now!(scope, "task.updated",
          entity_type: :task,
          entity_id: updated.id,
          changes: %{"title" => updated.title}
        )

        {:ok, updated}

      err ->
        err
    end
  end

  @doc """
  Marks a task complete. Idempotent — re-completing an already-done
  task is a no-op.
  """
  def complete_task(%Scope{user: user} = scope, %Task{} = task) do
    cond do
      not is_nil(task.completed_at) ->
        {:ok, task}

      true ->
        attrs = %{
          completed_at: DateTime.utc_now() |> DateTime.truncate(:second),
          completed_by_user_id: user && user.id
        }

        case task |> Task.changeset(stringify(attrs)) |> Repo.update() do
          {:ok, updated} ->
            Audit.log_now!(scope, "task.completed",
              entity_type: :task,
              entity_id: updated.id
            )

            {:ok, updated}

          err ->
            err
        end
    end
  end

  @doc """
  Re-opens a previously completed task (clears completion fields).
  """
  def uncomplete_task(%Scope{} = scope, %Task{} = task) do
    case task
         |> Task.changeset(%{
           "completed_at" => nil,
           "completed_by_user_id" => nil
         })
         |> Repo.update() do
      {:ok, updated} ->
        Audit.log_now!(scope, "task.uncompleted",
          entity_type: :task,
          entity_id: updated.id
        )

        {:ok, updated}

      err ->
        err
    end
  end

  @doc """
  Bulk-completes a list of task ids belonging to the current farm.
  Returns `{:ok, count}` with the number actually completed (already-
  done tasks are skipped silently).
  """
  def bulk_complete(%Scope{farm: %{id: farm_id}, user: user} = scope, ids)
      when is_list(ids) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    user_id = user && user.id

    {count, _} =
      from(t in Task,
        where: t.id in ^ids and t.farm_id == ^farm_id and is_nil(t.completed_at),
        update: [set: [completed_at: ^now, completed_by_user_id: ^user_id]]
      )
      |> Repo.update_all([])

    if count > 0 do
      Audit.log_now!(scope, "task.bulk_completed",
        entity_type: :task,
        entity_id: nil,
        changes: %{"count" => count, "ids" => ids}
      )
    end

    {:ok, count}
  end

  @doc "Hard-deletes a task. Tasks aren't soft-deleted — they're cheap."
  def delete_task(%Scope{} = scope, %Task{} = task) do
    case Repo.delete(task) do
      {:ok, deleted} ->
        Audit.log_now!(scope, "task.deleted",
          entity_type: :task,
          entity_id: deleted.id,
          changes: %{"title" => deleted.title}
        )

        {:ok, deleted}

      err ->
        err
    end
  end

  defp stringify(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      pair -> pair
    end)
  end
end
