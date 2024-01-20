defmodule Peggy.Repo.Migrations.CreateFarms do
  use Ecto.Migration

  def change do
    create table(:farms) do
      add :name, :string, null: false
      add :address1, :string
      add :address2, :string
      add :city, :string
      add :zipcode, :string
      add :state, :string
      add :country, :string, null: false
      add :timezone, :string, null: false
      add :email, :string
      add :tel, :string
      add :descriptions, :text
      timestamps(type: :timestamptz)
    end

    create index(:farms, :name)

    create table(:farm_user) do
      add :role, :string, null: false
      add :farm_id, references(:farms, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :default_farm, :boolean, default: false

      timestamps(type: :timestamptz)
    end

    create index(:farm_user, :farm_id)
    create index(:farm_user, :user_id)

    create unique_index(:farm_user, [:user_id, :farm_id],
             name: :farm_user_unique_farm_in_user
           )
  end
end
