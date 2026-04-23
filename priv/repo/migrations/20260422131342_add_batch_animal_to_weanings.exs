defmodule Peggy.Repo.Migrations.AddBatchAnimalToWeanings do
  use Ecto.Migration

  @doc """
  Introduces the searchable, poolable weaner-batch model.

    * adds `weanings.batch_animal_id` pointing at the weaner-batch `animals`
      row this weaning contributed to
    * backfills existing weanings by locating the batch via
      `animals.farrowing_id = weanings.farrowing_id`
    * backfills a synthetic `ear_tag` on any weaner-batch animal that
      still lacks one (`W<id>`), so the new "required ear_tag on batches"
      validation does not break historical data
  """
  def up do
    alter table(:breeding_weanings) do
      add :batch_animal_id, references(:animals, on_delete: :nilify_all)
    end

    create index(:breeding_weanings, [:batch_animal_id])

    flush()

    # Backfill: weaner batch animals missing an ear_tag get `W<id>`.
    execute("""
    UPDATE animals
    SET ear_tag = 'W' || id
    WHERE tracking_type = 'batch'
      AND stage = 'weaner'
      AND (ear_tag IS NULL OR ear_tag = '')
    """)

    # Backfill: point each weaning at the batch animal linked to its farrowing.
    execute("""
    UPDATE breeding_weanings w
    SET batch_animal_id = a.id
    FROM animals a
    WHERE a.farrowing_id = w.farrowing_id
      AND a.tracking_type = 'batch'
      AND a.stage = 'weaner'
      AND w.batch_animal_id IS NULL
    """)
  end

  def down do
    drop index(:breeding_weanings, [:batch_animal_id])

    alter table(:breeding_weanings) do
      remove :batch_animal_id
    end
  end
end
