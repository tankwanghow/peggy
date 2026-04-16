defmodule Peggy.Repo.Migrations.AddFromPenIdToMovements do
  use Ecto.Migration

  def change do
    # Nullable — required for batch movements, left null for individuals
    # (their "from" is implied by the prior movement row).
    alter table(:movements) do
      add :from_pen_id, references(:pens, on_delete: :restrict)
    end

    create index(:movements, [:from_pen_id])
  end
end
