defmodule Peggy.Repo.Migrations.AddFarrowingSoftDelete do
  use Ecto.Migration

  def change do
    alter table(:breeding_farrowings) do
      add :deleted_at, :utc_datetime
      add :deleted_by_id, references(:users, on_delete: :nilify_all)
    end

    create index(:breeding_farrowings, [:deleted_at])
  end
end
