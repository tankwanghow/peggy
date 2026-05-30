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
        {:entity_type, nil}, acc ->
          acc

        {:entity_type, et}, acc ->
          from a in acc, where: a.entity_type == ^et

        {:entity_id, nil}, acc ->
          acc

        {:entity_id, id}, acc ->
          from a in acc, where: a.entity_id == ^to_string(id)

        {:action, nil}, acc ->
          acc

        {:action, ""}, acc ->
          acc

        {:action, act}, acc ->
          from a in acc, where: ilike(a.action, ^"%#{escape_like(act)}%")

        {:changes_key, nil}, acc ->
          acc

        {:changes_key, ""}, acc ->
          acc

        {:changes_key, key}, acc ->
          # Filter rows where the changes map has this top-level key.
          # Combined with :changes_value below if also supplied.
          from a in acc,
            where: fragment("jsonb_extract_path_text(?, ?) IS NOT NULL", a.changes, ^key)

        {:changes_value, nil}, acc ->
          acc

        {:changes_value, ""}, acc ->
          acc

        {:changes_value, val}, acc ->
          # Combined with :changes_key when both are set (key+value pair
          # check uses path_text ILIKE). With no key, fall back to a
          # whole-document substring search via JSONB-cast-to-text.
          key = Keyword.get(opts, :changes_key)

          if is_binary(key) and key != "" do
            from a in acc,
              where:
                fragment(
                  "jsonb_extract_path_text(?, ?) ILIKE ?",
                  a.changes,
                  ^key,
                  ^"%#{escape_like(val)}%"
                )
          else
            from a in acc,
              where: fragment("?::text ILIKE ?", a.changes, ^"%#{escape_like(val)}%")
          end

        {:limit, n}, acc ->
          from a in acc, limit: ^n

        {:offset, n}, acc ->
          from a in acc, offset: ^n

        _, acc ->
          acc
      end)

    Repo.all(q) |> Repo.preload(:actor_user)
  end

  @doc """
  Returns the distinct top-level keys appearing in `changes` across the
  most recent N audit rows for the farm. Used to populate a key
  dropdown without scanning the entire table.
  """
  def list_change_keys(%Scope{farm: farm}, sample_size \\ 1_000) do
    from(a in AuditLog,
      where: a.farm_id == ^farm.id,
      order_by: [desc: a.inserted_at, desc: a.id],
      limit: ^sample_size,
      select: a.changes
    )
    |> Repo.all()
    |> Enum.flat_map(fn
      m when is_map(m) -> Map.keys(m)
      _ -> []
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp escape_like(value) do
    value
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end
end
