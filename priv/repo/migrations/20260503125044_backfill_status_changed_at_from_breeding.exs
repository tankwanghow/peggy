defmodule Peggy.Repo.Migrations.BackfillStatusChangedAtFromBreeding do
  use Ecto.Migration

  @moduledoc """
  The previous migration seeded `status_changed_at = inserted_at` for
  every animal row. For animals imported from legacy data that
  understates time-in-status — a sow imported yesterday may actually
  have been served weeks ago.

  This migration replaces the seed with a more accurate value derived
  from the breeding tables, but only for rows where `status_changed_at`
  is still equal to `inserted_at` — i.e. rows that haven't seen any
  real status change since the prior backfill ran.

  - `served`  → latest open service's `served_at`
  - `lactating` → latest open farrowing's `farrowed_at` (no active weaning)

  Other statuses keep `inserted_at` as the honest fallback (no better
  source available in the schema).
  """

  def up do
    # Served sows: latest non-deleted open service's served_at.
    execute("""
    UPDATE animals a
    SET status_changed_at = (s.served_at::timestamp AT TIME ZONE 'UTC')
    FROM (
      SELECT DISTINCT ON (sow_id) sow_id, served_at
      FROM breeding_services
      WHERE result IS NULL AND deleted_at IS NULL
      ORDER BY sow_id, served_at DESC
    ) s
    WHERE a.id = s.sow_id
      AND a.status = 'served'
      AND a.status_changed_at = a.inserted_at;
    """)

    # Lactating sows: latest farrowing without an active weaning.
    execute("""
    UPDATE animals a
    SET status_changed_at = (f.farrowed_at::timestamp AT TIME ZONE 'UTC')
    FROM (
      SELECT DISTINCT ON (f.sow_id) f.sow_id, f.farrowed_at
      FROM breeding_farrowings f
      WHERE f.deleted_at IS NULL
        AND NOT EXISTS (
          SELECT 1 FROM breeding_weanings w
          WHERE w.farrowing_id = f.id AND w.deleted_at IS NULL
        )
      ORDER BY f.sow_id, f.farrowed_at DESC
    ) f
    WHERE a.id = f.sow_id
      AND a.status = 'lactating'
      AND a.status_changed_at = a.inserted_at;
    """)
  end

  def down do
    # No reverse — the prior values (inserted_at) are preserved for
    # non-served/non-lactating rows, and for the rest the precise
    # historical timestamp is unrecoverable from this direction.
    :ok
  end
end
