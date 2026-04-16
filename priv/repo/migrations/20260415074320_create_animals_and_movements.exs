defmodule Peggy.Repo.Migrations.CreateAnimalsAndMovements do
  use Ecto.Migration

  def change do
    create table(:animals) do
      add :farm_id, references(:farms, on_delete: :delete_all), null: false
      add :tracking_type, :string, null: false
      add :ear_tag, :string
      add :rfid, :string
      add :breed, :string
      add :stage, :string, null: false
      add :sex, :string
      add :dob, :date
      add :quantity, :integer, default: 1, null: false
      add :status, :string, null: false, default: "active"
      add :sire_id, references(:animals, on_delete: :nilify_all)
      add :dam_id, references(:animals, on_delete: :nilify_all)
      add :current_pen_id, references(:pens, on_delete: :nilify_all)
      add :notes, :text
      timestamps(type: :utc_datetime)
    end

    create index(:animals, [:farm_id])
    create index(:animals, [:current_pen_id])
    create index(:animals, [:sire_id])
    create index(:animals, [:dam_id])
    create index(:animals, [:farm_id, :stage])
    create index(:animals, [:farm_id, :status])

    execute(
      "CREATE UNIQUE INDEX animals_farm_id_ear_tag_index ON animals (farm_id, ear_tag) WHERE ear_tag IS NOT NULL",
      "DROP INDEX animals_farm_id_ear_tag_index"
    )

    execute(
      "CREATE UNIQUE INDEX animals_farm_id_rfid_index ON animals (farm_id, rfid) WHERE rfid IS NOT NULL",
      "DROP INDEX animals_farm_id_rfid_index"
    )

    create table(:movements) do
      add :farm_id, references(:farms, on_delete: :delete_all), null: false
      add :animal_id, references(:animals, on_delete: :delete_all), null: false
      add :from_pen_id, references(:pens, on_delete: :nilify_all)
      add :to_pen_id, references(:pens, on_delete: :nilify_all)
      add :reason, :string, null: false
      add :quantity, :integer, default: 1, null: false
      add :moved_at, :utc_datetime, null: false
      add :notes, :text
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:movements, [:farm_id])
    create index(:movements, [:animal_id])
    create index(:movements, [:moved_at])
  end
end
