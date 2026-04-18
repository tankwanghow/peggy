defmodule Peggy.Repo.Migrations.CreateBreedingTables do
  use Ecto.Migration

  def change do
    # ── Services ──────────────────────────────────────────────────────
    create table(:breeding_services) do
      add :farm_id, references(:farms, on_delete: :delete_all), null: false
      add :sow_id, references(:animals, on_delete: :restrict), null: false
      add :boar_id, references(:animals, on_delete: :restrict)
      add :service_type, :string, null: false
      add :served_at, :date, null: false
      add :technician_user_id, references(:users, on_delete: :nilify_all)
      add :result, :string
      add :result_at, :date
      add :result_notes, :text
      add :notes, :text
      timestamps(type: :utc_datetime)
    end

    create index(:breeding_services, [:farm_id])
    create index(:breeding_services, [:sow_id])
    create index(:breeding_services, [:boar_id])
    create index(:breeding_services, [:farm_id, :sow_id, :served_at])

    # Fast lookup for gestating sows (open services)
    execute(
      "CREATE INDEX breeding_services_open_index ON breeding_services (farm_id, sow_id) WHERE result IS NULL",
      "DROP INDEX breeding_services_open_index"
    )

    # ── Farrowings ────────────────────────────────────────────────────
    create table(:breeding_farrowings) do
      add :farm_id, references(:farms, on_delete: :delete_all), null: false
      add :service_id, references(:breeding_services, on_delete: :restrict), null: false
      add :sow_id, references(:animals, on_delete: :restrict), null: false
      add :pen_id, references(:pens, on_delete: :restrict)
      add :farrowed_at, :date, null: false
      add :born_alive, :integer, null: false
      add :stillborn, :integer, null: false, default: 0
      add :mummified, :integer, null: false, default: 0
      add :total_birth_weight_g, :integer
      add :notes, :text
      timestamps(type: :utc_datetime)
    end

    create index(:breeding_farrowings, [:farm_id])
    create index(:breeding_farrowings, [:sow_id])
    create unique_index(:breeding_farrowings, [:service_id])
    create index(:breeding_farrowings, [:farrowed_at])

    create constraint(:breeding_farrowings, :breeding_farrowings_born_alive_non_neg,
             check: "born_alive >= 0"
           )

    create constraint(:breeding_farrowings, :breeding_farrowings_stillborn_non_neg,
             check: "stillborn >= 0"
           )

    create constraint(:breeding_farrowings, :breeding_farrowings_mummified_non_neg,
             check: "mummified >= 0"
           )

    # ── Weanings ──────────────────────────────────────────────────────
    create table(:breeding_weanings) do
      add :farm_id, references(:farms, on_delete: :delete_all), null: false
      add :farrowing_id, references(:breeding_farrowings, on_delete: :restrict), null: false
      add :weaned_at, :date, null: false
      add :weaned_count, :integer, null: false
      add :avg_wean_weight_g, :integer
      add :destination_pen_id, references(:pens, on_delete: :restrict)
      add :notes, :text
      timestamps(type: :utc_datetime)
    end

    create index(:breeding_weanings, [:farm_id])
    create unique_index(:breeding_weanings, [:farrowing_id])

    create constraint(:breeding_weanings, :breeding_weanings_weaned_count_non_neg,
             check: "weaned_count >= 0"
           )

    # ── Add farrowing_id to animals ───────────────────────────────────
    alter table(:animals) do
      add :farrowing_id, references(:breeding_farrowings, on_delete: :nilify_all)
    end

    create index(:animals, [:farrowing_id])
  end
end
