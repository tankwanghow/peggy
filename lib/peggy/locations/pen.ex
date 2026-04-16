defmodule Peggy.Locations.Pen do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(active quarantine cleaning retired)

  schema "pens" do
    field :code, :string
    field :capacity, :integer, default: 0
    field :status, :string, default: "active"
    belongs_to :farm, Peggy.Farms.Farm
    belongs_to :house, Peggy.Locations.House
    has_many :animals, Peggy.Animals.Animal, foreign_key: :current_pen_id
    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(pen, attrs) do
    pen
    |> cast(attrs, [:code, :capacity, :status, :farm_id, :house_id])
    |> validate_required([:code, :capacity, :status, :farm_id, :house_id])
    |> validate_length(:code, min: 1, max: 40)
    |> validate_number(:capacity, greater_than_or_equal_to: 0)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:house_id, :code])
  end
end
