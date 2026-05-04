defmodule Peggy.Repo.Migrations.AddMountingTrackingToBreedingServices do
  use Ecto.Migration

  def up do
    alter table(:breeding_services) do
      add :last_serviced_at, :date
      add :mounting_count, :integer, default: 1, null: false
    end

    # Backfill: each existing row represents one mounting served on
    # `served_at`. The collapse logic from this point on increments
    # `mounting_count` and pushes `last_serviced_at` for re-services
    # within the configured window.
    execute(
      "UPDATE breeding_services SET last_serviced_at = served_at WHERE last_serviced_at IS NULL"
    )

    alter table(:breeding_services) do
      modify :last_serviced_at, :date, null: false
    end
  end

  def down do
    alter table(:breeding_services) do
      remove :last_serviced_at
      remove :mounting_count
    end
  end
end
