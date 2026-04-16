defmodule Peggy.Animals.Placement do
  @moduledoc """
  Current placement of a batch animal in a specific pen.

  Batches can be split across multiple pens — each row is one slice of
  the batch. Sum of active placements' `quantity` equals the batch's
  `animals.quantity`. Individual animals use `animals.current_pen_id`
  directly and do not have placement rows.

  A placement is "closed" by setting `removed_at` rather than deleted,
  so historical movements stay referenceable.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "placements" do
    field :quantity, :integer
    field :placed_at, :date
    field :removed_at, :date
    belongs_to :animal, Peggy.Animals.Animal
    belongs_to :pen, Peggy.Locations.Pen
    timestamps(type: :utc_datetime)
  end

  def changeset(placement, attrs) do
    placement
    |> cast(attrs, [:animal_id, :pen_id, :quantity, :placed_at, :removed_at])
    |> validate_required([:animal_id, :pen_id, :quantity, :placed_at])
    |> validate_number(:quantity, greater_than: 0)
  end
end
