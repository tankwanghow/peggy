defmodule Peggy.Repo.Migrations.CreatePlacements do
  use Ecto.Migration

  def change do
    create table(:placements) do
      add :animal_id, references(:animals, on_delete: :delete_all), null: false
      add :pen_id, references(:pens, on_delete: :restrict), null: false
      add :quantity, :integer, null: false
      add :placed_at, :date, null: false
      add :removed_at, :date
      timestamps(type: :utc_datetime)
    end

    create index(:placements, [:animal_id])
    create index(:placements, [:pen_id])

    # One active row per (animal, pen). Closed rows (removed_at not null)
    # are history and can repeat.
    create unique_index(:placements, [:animal_id, :pen_id],
             where: "removed_at IS NULL",
             name: :placements_animal_id_pen_id_active_index
           )

    create constraint(:placements, :placements_quantity_positive, check: "quantity > 0")
  end
end
