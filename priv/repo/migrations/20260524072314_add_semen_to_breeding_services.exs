defmodule Peggy.Repo.Migrations.AddSemenToBreedingServices do
  use Ecto.Migration

  def change do
    alter table(:breeding_services) do
      add :semen, :string
    end
  end
end
