defmodule Peggy.Repo.Migrations.AddFarmSoftDelete do
  use Ecto.Migration

  def change do
    alter table(:farms) do
      add :deleted_at, :utc_datetime
      add :deleted_by_id, references(:users, on_delete: :nilify_all)
    end

    create index(:farms, [:deleted_at])
  end
end
