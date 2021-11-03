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
      add :birth_to_wean, :integer, default: 28, null: false
      add :paired_to_farrow, :integer, default: 114, null: false
      add :wean_to_pair, :integer, default: 7, null: false
      add :paired_to_prefarrow, :integer, default: 100, null: false
      timestamps()
    end

    create index(:farms, :name)

    create table(:farm_user) do
      add :role, :string, null: false
      add :farm_id, references(:farms, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :default_farm, :boolean, null: false, default: false

      timestamps()
    end
    create unique_index(:farm_user, [:farm_id, :user_id])
    create index(:farm_user, :farm_id)
    create index(:farm_user, :user_id)

  end
end
