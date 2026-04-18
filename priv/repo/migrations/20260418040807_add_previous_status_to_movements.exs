defmodule Peggy.Repo.Migrations.AddPreviousStatusToMovements do
  use Ecto.Migration

  def change do
    alter table(:movements) do
      add :previous_status, :string
    end
  end
end
