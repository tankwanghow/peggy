defmodule Peggy.Repo.Migrations.AddWeaningIdToMovements do
  use Ecto.Migration

  def change do
    alter table(:movements) do
      add :weaning_id, references(:breeding_weanings, on_delete: :nilify_all)
    end

    create index(:movements, [:weaning_id])
  end
end
