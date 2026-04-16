defmodule Peggy.Animals.Animal do
  use Ecto.Schema
  import Ecto.Changeset

  @tracking_types ~w(individual batch)
  @stages ~w(piglet weaner grower finisher sow boar cull)
  @sexes ~w(male female unknown)
  @statuses ~w(active sold slaughtered deceased transferred)

  schema "animals" do
    field :tracking_type, :string
    field :ear_tag, :string
    field :rfid, :string
    field :breed, :string
    field :stage, :string
    field :sex, :string
    field :dob, :date
    field :quantity, :integer, default: 1
    field :status, :string, default: "active"
    field :notes, :string
    belongs_to :farm, Peggy.Farms.Farm
    belongs_to :sire, __MODULE__
    belongs_to :dam, __MODULE__
    belongs_to :current_pen, Peggy.Locations.Pen
    has_many :movements, Peggy.Animals.Movement
    has_many :placements, Peggy.Animals.Placement
    timestamps(type: :utc_datetime)
  end

  def tracking_types, do: @tracking_types
  def stages, do: @stages
  def sexes, do: @sexes
  def statuses, do: @statuses

  @doc """
  Stage options offered by the UI for a given tracking type.

  Individuals are typically breeding stock (sow, boar) or culls;
  batches move through the piglet → weaner → grower → finisher
  lifecycle. Schema-level validation still accepts any stage in
  `@stages` — this helper only narrows the dropdown.
  """
  def stages_for("individual"), do: ~w(sow boar cull)
  def stages_for("batch"), do: ~w(piglet weaner grower finisher)
  def stages_for(_), do: @stages

  def changeset(animal, attrs) do
    animal
    |> cast(attrs, [
      :tracking_type,
      :ear_tag,
      :rfid,
      :breed,
      :stage,
      :sex,
      :dob,
      :quantity,
      :status,
      :notes,
      :sire_id,
      :dam_id,
      :current_pen_id,
      :farm_id
    ])
    |> validate_required([:tracking_type, :stage, :status, :farm_id])
    |> validate_inclusion(:tracking_type, @tracking_types)
    |> validate_inclusion(:stage, @stages)
    |> validate_inclusion(:status, @statuses)
    |> validate_type_specific()
    |> validate_length(:ear_tag, min: 1, max: 40)
    |> validate_length(:rfid, min: 1, max: 60)
    |> validate_length(:breed, min: 1, max: 60)
    |> unsafe_validate_unique([:farm_id, :ear_tag], Peggy.Repo, error_key: :ear_tag)
    |> unsafe_validate_unique([:farm_id, :rfid], Peggy.Repo, error_key: :rfid)
    |> unique_constraint(:ear_tag, name: :animals_farm_id_ear_tag_index)
    |> unique_constraint(:rfid, name: :animals_farm_id_rfid_index)
  end

  defp validate_type_specific(cs) do
    case get_field(cs, :tracking_type) do
      "individual" ->
        cs
        |> validate_required([:ear_tag, :sex])
        |> validate_inclusion(:sex, @sexes)
        |> force_change(:quantity, 1)

      "batch" ->
        cs
        |> validate_required([:quantity])
        |> validate_batch_quantity()

      _ ->
        cs
    end
  end

  # Active batches need >1 animals (a batch of 1 should be individual).
  # Once a batch has departed (sold/slaughtered/etc.) quantity is allowed
  # to drop to 0 so we can close out the row cleanly.
  defp validate_batch_quantity(cs) do
    qty = get_field(cs, :quantity)
    status = get_field(cs, :status)

    cond do
      is_integer(qty) and qty > 1 -> cs
      is_integer(qty) and qty >= 0 and status != "active" -> cs
      true -> add_error(cs, :quantity, "must be greater than 1 for batch animals")
    end
  end
end
