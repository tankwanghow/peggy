defmodule Peggy.Repo.Migrations.AddWeaningSoftDelete do
  use Ecto.Migration

  def change do
    alter table(:breeding_weanings) do
      add :deleted_at, :utc_datetime
      add :deleted_by_id, references(:users, on_delete: :nilify_all)
    end

    create index(:breeding_weanings, [:deleted_at])

    # Replace the bare unique index on farrowing_id with a partial index that
    # only applies to non-deleted rows, so a deleted weaning can coexist with
    # a new/restored one for the same farrowing.
    drop_if_exists unique_index(:breeding_weanings, [:farrowing_id])

    create unique_index(:breeding_weanings, [:farrowing_id],
             where: "deleted_at IS NULL",
             name: :breeding_weanings_farrowing_id_active_index
           )
  end
end
