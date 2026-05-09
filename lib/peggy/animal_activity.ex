defmodule Peggy.AnimalActivity do
  @moduledoc """
  Cross-context coordination for animal-history operations that touch
  more than one context (e.g. "undo the most recent event for this
  sow", which spans `Animals.Movement`, `Breeding.Service`,
  `Breeding.Farrowing`, `Breeding.Weaning`, and `Breeding.LitterEvent`).

  Each context still owns the actual write logic — this module just
  picks the right one and dispatches.
  """

  import Ecto.Query
  alias Peggy.Repo
  alias Peggy.Accounts.Scope
  alias Peggy.Animals
  alias Peggy.Animals.{Animal, Movement}
  alias Peggy.Breeding
  alias Peggy.Breeding.{Farrowing, LitterEvent, Service, Weaning}

  @typedoc "Latest event tuple, or nil if the animal has no activity."
  @type latest ::
          {:movement, Movement.t()}
          | {:service, Service.t()}
          | {:farrowing, Farrowing.t()}
          | {:weaning, Weaning.t()}
          | {:litter_event, LitterEvent.t()}
          | nil

  @doc """
  Returns the most recently inserted (`inserted_at` desc, `id` desc as
  tiebreaker) non-deleted activity for the animal. Operator-driven
  side-effect rows are excluded so the result is the user's last
  primary action:

    * wean movements (`reason = "wean"`) are skipped — `delete_weaning`
      cascades them, so they shouldn't be undoable on their own.
    * Soft-deleted rows in any table are skipped.

  For sows this scans Movement / Service / Farrowing / Weaning. For
  farrowings (the parent of LitterEvent) we also include LitterEvent
  rows whose farrowing belongs to this sow — the litter-event undo path
  reverts the count side-effect.

  Returns `nil` when the animal has no activity.
  """
  @spec latest_event(Scope.t(), Animal.t()) :: latest()
  def latest_event(%Scope{farm: farm}, %Animal{farm_id: fid} = animal) when fid == farm.id do
    candidates =
      [
        latest_movement(animal),
        latest_service(animal),
        latest_farrowing(animal),
        latest_weaning(animal),
        latest_litter_event(animal)
      ]
      |> Enum.reject(&is_nil/1)

    case candidates do
      [] ->
        nil

      list ->
        # Sort by event date first (what the user sees at the top of
        # the history view), then `inserted_at` (when the row was
        # written to the DB), then `kind_priority` so a same-transaction
        # parent record wins over its side-effect movement.
        Enum.max_by(list, fn {kind, row} ->
          {
            Date.to_gregorian_days(event_date(kind, row)),
            DateTime.to_unix(row.inserted_at, :microsecond),
            kind_priority(kind),
            row.id
          }
        end)
    end
  end

  defp event_date(:movement, %{moved_at: d}), do: d
  defp event_date(:service, %{served_at: d}), do: d
  defp event_date(:farrowing, %{farrowed_at: d}), do: d
  defp event_date(:weaning, %{weaned_at: d}), do: d
  defp event_date(:litter_event, %{occurred_at: d}), do: d

  defp kind_priority(:weaning), do: 4
  defp kind_priority(:farrowing), do: 3
  defp kind_priority(:service), do: 2
  defp kind_priority(:litter_event), do: 1
  defp kind_priority(:movement), do: 0

  @doc """
  Undoes the latest event for `animal`. Dispatches by kind:

    * `:movement` → `Animals.undo_last_movement/2`
    * `:service`  → `Breeding.delete_service/2`
    * `:farrowing` → `Breeding.delete_farrowing/2`
    * `:weaning`  → `Breeding.delete_weaning/2`
    * `:litter_event` → `Breeding.delete_litter_event/2`

  Returns `{:ok, kind, result}` on success, `{:error, :no_events}` when
  there's nothing to undo, or `{:error, kind, reason}` on failure.
  """
  @spec undo_latest(Scope.t(), Animal.t()) ::
          {:ok, atom(), term()} | {:error, :no_events} | {:error, atom(), term()}
  def undo_latest(%Scope{} = scope, %Animal{} = animal) do
    case latest_event(scope, animal) do
      nil ->
        {:error, :no_events}

      {:movement, _m} ->
        case Animals.undo_last_movement(scope, animal) do
          {:ok, m} -> {:ok, :movement, m}
          {:error, reason} -> {:error, :movement, reason}
        end

      {:service, s} ->
        case Breeding.delete_service(scope, s) do
          {:ok, s} -> {:ok, :service, s}
          {:error, reason} -> {:error, :service, reason}
        end

      {:farrowing, f} ->
        case Breeding.delete_farrowing(scope, f) do
          {:ok, f} -> {:ok, :farrowing, f}
          {:error, reason} -> {:error, :farrowing, reason}
        end

      {:weaning, w} ->
        case Breeding.delete_weaning(scope, w) do
          {:ok, w} -> {:ok, :weaning, w}
          {:error, reason} -> {:error, :weaning, reason}
        end

      {:litter_event, e} ->
        case Breeding.delete_litter_event(scope, e) do
          {:ok, _} -> {:ok, :litter_event, e}
          {:error, reason} -> {:error, :litter_event, reason}
        end
    end
  end

  # ── Per-table latest queries ─────────────────────────────────────

  defp latest_movement(%Animal{id: id}) do
    # Exclude movements that are cascade side-effects:
    #   * `wean` movements are deleted by `delete_weaning`.
    #   * `placement`/`pen_transfer` movements created by `record_farrowing`
    #     have `moved_at == farrowing.farrowed_at` and the same `to_pen_id`.
    sow_move_subquery =
      from(f in Farrowing,
        where: f.sow_id == ^id and is_nil(f.deleted_at),
        select: %{moved_at: f.farrowed_at, to_pen_id: f.pen_id}
      )

    Repo.one(
      from m in Movement,
        left_join: side in subquery(sow_move_subquery),
        on:
          side.moved_at == m.moved_at and
            side.to_pen_id == m.to_pen_id,
        where:
          m.animal_id == ^id and m.reason != "wean" and
            (m.reason not in ["placement", "pen_transfer"] or is_nil(side.to_pen_id)),
        order_by: [desc: m.inserted_at, desc: m.id],
        limit: 1
    )
    |> tag(:movement)
  end

  defp latest_service(%Animal{id: id}) do
    Repo.one(
      from s in Service,
        where: s.sow_id == ^id and is_nil(s.deleted_at),
        order_by: [desc: s.inserted_at, desc: s.id],
        limit: 1
    )
    |> tag(:service)
  end

  defp latest_farrowing(%Animal{id: id}) do
    Repo.one(
      from f in Farrowing,
        where: f.sow_id == ^id and is_nil(f.deleted_at),
        order_by: [desc: f.inserted_at, desc: f.id],
        limit: 1
    )
    |> tag(:farrowing)
  end

  defp latest_weaning(%Animal{id: id}) do
    Repo.one(
      from w in Weaning,
        join: f in Farrowing,
        on: f.id == w.farrowing_id,
        where: f.sow_id == ^id and is_nil(w.deleted_at),
        order_by: [desc: w.inserted_at, desc: w.id],
        limit: 1
    )
    |> tag(:weaning)
  end

  defp latest_litter_event(%Animal{id: id}) do
    Repo.one(
      from e in LitterEvent,
        join: f in Farrowing,
        on: f.id == e.farrowing_id,
        where: f.sow_id == ^id and is_nil(e.deleted_at),
        order_by: [desc: e.inserted_at, desc: e.id],
        limit: 1
    )
    |> tag(:litter_event)
  end

  defp tag(nil, _kind), do: nil
  defp tag(row, kind), do: {kind, row}
end
