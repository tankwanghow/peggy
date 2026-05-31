defmodule Peggy.Repo.Migrations.AddMarkedCullToAnimals do
  use Ecto.Migration

  # `marked_cull` is an *intent* flag orthogonal to lifecycle status: a
  # flagged sow keeps her real status (served/lactating/dry/…) and her
  # reproductive cycle continues until an actual departure movement.
  def change do
    alter table(:animals) do
      add :marked_cull, :boolean, null: false, default: false
      add :marked_cull_at, :utc_datetime
    end

    create index(:animals, [:farm_id, :marked_cull])
  end
end
