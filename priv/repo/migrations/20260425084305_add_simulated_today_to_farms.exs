defmodule Peggy.Repo.Migrations.AddSimulatedTodayToFarms do
  use Ecto.Migration

  def change do
    alter table(:farms) do
      add :simulated_today, :date
    end
  end
end
