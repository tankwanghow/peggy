defmodule Peggy.Repo.Migrations.CreateLocations do
  use Ecto.Migration

  def change do
    create table(:houses) do
      add :farm_id, references(:farms, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :code, :string, null: false
      add :purpose, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:houses, [:farm_id])
    create unique_index(:houses, [:farm_id, :code])

    create table(:pens) do
      add :farm_id, references(:farms, on_delete: :delete_all), null: false
      add :house_id, references(:houses, on_delete: :delete_all), null: false
      add :code, :string, null: false
      add :capacity, :integer, null: false, default: 0
      add :status, :string, null: false, default: "active"
      timestamps(type: :utc_datetime)
    end

    create index(:pens, [:farm_id])
    create index(:pens, [:house_id])
    create unique_index(:pens, [:house_id, :code])
  end
end
