defmodule Peggy.Repo.Migrations.CreateLocations do
  use Ecto.Migration

  def change do
    create table(:locations) do
      add :code, :string
      add :note, :text
      add :capacity, :integer
      add :status, :string
      add :farm_id, references(:farms, on_delete: :delete_all)

      timestamps()
    end

    create index(:locations, [:farm_id])
    create unique_index(:locations, [:code, :farm_id])
  end
end
