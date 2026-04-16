defmodule Peggy.Repo.Migrations.RemoveFromPenIdFromMovements do
  use Ecto.Migration

  def change do
    alter table(:movements) do
      remove :from_pen_id, references(:pens), null: true
    end
  end
end
