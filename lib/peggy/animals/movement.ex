defmodule Peggy.Animals.Movement do
  use Ecto.Schema
  import Ecto.Changeset

  @reasons ~w(placement pen_transfer sale slaughter death farm_transfer adjustment_loss adjustment_gain)

  schema "movements" do
    field :reason, :string
    field :quantity, :integer, default: 1
    field :moved_at, :date
    field :notes, :string
    belongs_to :farm, Peggy.Farms.Farm
    belongs_to :animal, Peggy.Animals.Animal
    belongs_to :from_pen, Peggy.Locations.Pen
    belongs_to :to_pen, Peggy.Locations.Pen
    timestamps(type: :utc_datetime, updated_at: false)
  end

  def reasons, do: @reasons

  def changeset(movement, attrs) do
    movement
    |> cast(attrs, [
      :reason,
      :quantity,
      :moved_at,
      :notes,
      :animal_id,
      :farm_id,
      :from_pen_id,
      :to_pen_id
    ])
    |> validate_required([:reason, :quantity, :moved_at, :animal_id, :farm_id])
    |> validate_inclusion(:reason, @reasons)
    |> validate_number(:quantity, greater_than: 0)
  end
end
