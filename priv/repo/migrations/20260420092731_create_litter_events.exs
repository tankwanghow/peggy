defmodule Peggy.Repo.Migrations.CreateLitterEvents do
  use Ecto.Migration

  def change do
    create table(:breeding_litter_events) do
      add :farm_id, references(:farms, on_delete: :delete_all), null: false

      add :farrowing_id, references(:breeding_farrowings, on_delete: :restrict), null: false

      add :kind, :string, null: false
      add :quantity, :integer, null: false
      add :occurred_at, :date, null: false

      add :counterpart_farrowing_id,
          references(:breeding_farrowings, on_delete: :nilify_all)

      add :notes, :text

      add :created_by_id, references(:users, on_delete: :nilify_all)
      add :deleted_at, :utc_datetime
      add :deleted_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:breeding_litter_events, [:farm_id])
    create index(:breeding_litter_events, [:farrowing_id])
    create index(:breeding_litter_events, [:counterpart_farrowing_id])
    create index(:breeding_litter_events, [:deleted_at])

    create constraint(:breeding_litter_events, :breeding_litter_events_quantity_positive,
             check: "quantity > 0"
           )

    create constraint(:breeding_litter_events, :breeding_litter_events_kind_valid,
             check: "kind IN ('death', 'foster_out', 'foster_in')"
           )

    # Fostering events must have a counterpart; deaths must not.
    create constraint(:breeding_litter_events, :breeding_litter_events_counterpart_consistent,
             check: """
             (kind = 'death' AND counterpart_farrowing_id IS NULL)
             OR
             (kind IN ('foster_out', 'foster_in') AND counterpart_farrowing_id IS NOT NULL)
             """
           )
  end
end
