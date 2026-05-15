defmodule Peggy.Repo.Migrations.AddPromotionThresholdsToFarms do
  use Ecto.Migration

  # Per-farm thresholds that drive the "Promote batch animals" triage
  # screen. All measured in days from the batch's `dob` (= founding
  # farrowing date). Defaults are biological middle-of-the-road; settings
  # UI clamps the editable range and enforces ordering.
  def change do
    alter table(:farms) do
      add :weaner_to_grower_days, :integer, null: false, default: 70
      add :grower_to_finisher_days, :integer, null: false, default: 120
      add :finisher_overdue_days, :integer, null: false, default: 200
    end
  end
end
