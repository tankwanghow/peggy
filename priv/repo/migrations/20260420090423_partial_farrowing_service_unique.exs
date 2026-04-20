defmodule Peggy.Repo.Migrations.PartialFarrowingServiceUnique do
  use Ecto.Migration

  def change do
    # Replace the bare unique index on service_id with a partial index that
    # only applies to non-deleted rows. A soft-deleted farrowing must not
    # block re-recording a new farrowing for the same service.
    drop_if_exists unique_index(:breeding_farrowings, [:service_id])

    create unique_index(:breeding_farrowings, [:service_id],
             where: "deleted_at IS NULL",
             name: :breeding_farrowings_service_id_active_index
           )
  end
end
