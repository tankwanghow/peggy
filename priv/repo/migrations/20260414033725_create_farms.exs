defmodule Peggy.Repo.Migrations.CreateFarms do
  use Ecto.Migration

  def change do
    create table(:farms) do
      add :slug, :citext, null: false
      add :name, :string, null: false
      add :timezone, :string, null: false, default: "Etc/UTC"
      add :unit_system, :string, null: false, default: "metric"
      add :plan, :string, null: false, default: "free"
      add :seat_limit, :integer, null: false, default: 5

      timestamps(type: :utc_datetime)
    end

    create unique_index(:farms, [:slug])
  end
end
