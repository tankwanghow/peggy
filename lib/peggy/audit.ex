defmodule Peggy.Audit do
  @moduledoc """
  Immutable audit trail.

  `log!/4` is a `Multi` step builder: every mutating context function
  should append it to its transaction so the log row lands atomically
  with the change.
  """

  import Ecto.Query
  alias Ecto.Multi
  alias Peggy.Repo
  alias Peggy.Accounts.Scope
  alias Peggy.Audit.AuditLog

  @doc """
  Adds an audit log insert to a `Multi`. `changes` is a map diff — pass
  the changeset's `changes` or a hand-rolled `%{before: ..., after: ...}`.
  """
  def log!(multi, %Scope{} = scope, action, opts) when is_binary(action) do
    Multi.insert(multi, {:audit, action}, fn _ ->
      row(scope, action, opts)
    end)
  end

  def log!(multi, %Scope{} = scope, action, opts, name) when is_binary(action) do
    Multi.insert(multi, name, fn _ -> row(scope, action, opts) end)
  end

  @doc """
  Synchronous insert outside a multi. Use sparingly — prefer attaching to
  the same transaction as the change being recorded.
  """
  def log_now!(%Scope{} = scope, action, opts) when is_binary(action) do
    Repo.insert!(row(scope, action, opts))
  end

  defp row(%Scope{} = scope, action, opts) do
    farm_id = opts[:farm_id] || (scope.farm && scope.farm.id) || raise "audit: farm_id required"

    %AuditLog{
      farm_id: farm_id,
      actor_user_id: scope.user && scope.user.id,
      action: action,
      entity_type: to_string(opts[:entity_type] || raise("audit: entity_type required")),
      entity_id: opts[:entity_id] && to_string(opts[:entity_id]),
      changes: opts[:changes] || %{},
      inserted_at: DateTime.utc_now(:second)
    }
  end

  @doc """
  Lists audit log rows for a farm, newest first. Supports optional filters
  for entity_type and action.
  """
  def list(%Scope{farm: farm}, opts \\ []) do
    q =
      from(a in AuditLog,
        where: a.farm_id == ^farm.id,
        order_by: [desc: a.inserted_at, desc: a.id]
      )

    q =
      Enum.reduce(opts, q, fn
        {:entity_type, nil}, acc -> acc
        {:entity_type, et}, acc -> from a in acc, where: a.entity_type == ^et
        {:action, nil}, acc -> acc
        {:action, act}, acc -> from a in acc, where: a.action == ^act
        {:limit, n}, acc -> from a in acc, limit: ^n
        _, acc -> acc
      end)

    Repo.all(q) |> Repo.preload(:actor_user)
  end
end
