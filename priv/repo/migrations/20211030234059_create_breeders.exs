defmodule Peggy.Repo.Migrations.CreateBreeders do
  use Ecto.Migration

  def change do
    create table(:sows) do
      add :code, :string, null: false
      add :breed, :string
      add :parity, :integer
      add :location_id, references(:locations, on_delete: :nilify_all)
      add :farm_id, references(:farms, on_delete: :delete_all), null: false
      add :dob, :date
      add :cull_date, :date
      add :status, :string, null: false
      timestamps()
    end
    create index(:sows, :farm_id)
    create unique_index(:sows, [:code, :farm_id])

    create table(:boars) do
      add :name, :string, null: false
      add :breed, :string
      add :location_id, references(:locations, on_delete: :nilify_all)
      add :farm_id, references(:farms, on_delete: :delete_all), null: false
      add :dob, :date
      add :cull_date, :date
      timestamps()
    end

    create index(:boars, :farm_id)
    create unique_index(:boars, [:name, :farm_id])
  end
end
