defmodule Peggy.Repo.Migrations.AddBreedingParametersToFarms do
  use Ecto.Migration

  # Per-farm breeding parameters. Defaults match the previously-hard-coded
  # values in `Peggy.Breeding` and `Peggy.Scheduler`, so existing farms
  # transparently keep current behaviour after this migration.
  def change do
    alter table(:farms) do
      add :gestation_days, :integer, null: false, default: 114
      add :lactation_days, :integer, null: false, default: 24
      add :minimum_sow_age_days, :integer, null: false, default: 365
      add :gestation_tolerance_days, :integer, null: false, default: 3
      add :collapse_window_days, :integer, null: false, default: 7
      add :recent_weaner_batch_days, :integer, null: false, default: 60
      add :wean_due_days, :integer, null: false, default: 21
    end
  end
end
