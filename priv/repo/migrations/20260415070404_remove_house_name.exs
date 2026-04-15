defmodule Peggy.Repo.Migrations.RemoveHouseName do
  use Ecto.Migration

  def change do
    alter table(:houses) do
      remove :name, :string, null: false
    end
  end
end
