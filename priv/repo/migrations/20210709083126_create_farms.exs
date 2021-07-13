defmodule Peggy.Repo.Migrations.CreateFarms do
  use Ecto.Migration

  def change do
    create table(:farms) do
      add :name, :string
      add :address1, :string
      add :address2, :string
      add :city, :string
      add :zipcode, :string
      add :state, :string
      add :country, :string
      add :weight_unit, :string

      timestamps()
    end

    create index(:farms, :name)

    create table(:farm_users) do
      add :role, :string, null: false
      add :farm_id, references(:farms, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end
    create unique_index(:farm_users, [:farm_id, :user_id])
    create index(:farm_users, [:farm_id])
    create index(:farm_users, [:user_id])

  end
end
