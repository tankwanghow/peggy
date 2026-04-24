defmodule Peggy.Repo.Migrations.ReuseTagsForDepartedAnimals do
  use Ecto.Migration

  # Allow ear_tag / rfid to be reused once an animal departs (sold,
  # slaughtered, deceased, transferred, reversed). Replace the global
  # unique indexes with partial indexes scoped to present animals.
  @departed ~w(sold slaughtered deceased transferred reversed)

  def up do
    drop unique_index(:animals, [:farm_id, :ear_tag])
    drop unique_index(:animals, [:farm_id, :rfid])

    create unique_index(:animals, [:farm_id, :ear_tag],
             where: "status NOT IN ('#{Enum.join(@departed, "','")}')",
             name: :animals_farm_id_ear_tag_index
           )

    create unique_index(:animals, [:farm_id, :rfid],
             where: "status NOT IN ('#{Enum.join(@departed, "','")}')",
             name: :animals_farm_id_rfid_index
           )
  end

  def down do
    drop unique_index(:animals, [:farm_id, :ear_tag], name: :animals_farm_id_ear_tag_index)
    drop unique_index(:animals, [:farm_id, :rfid], name: :animals_farm_id_rfid_index)

    create unique_index(:animals, [:farm_id, :ear_tag])
    create unique_index(:animals, [:farm_id, :rfid])
  end
end
