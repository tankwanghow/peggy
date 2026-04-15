defmodule Peggy.Locations.House do
  use Ecto.Schema
  import Ecto.Changeset

  @purposes ~w(breeding gestation farrowing nursery grower finisher quarantine hospital)

  schema "houses" do
    field :code, :string
    field :purpose, :string
    belongs_to :farm, Peggy.Farms.Farm
    has_many :pens, Peggy.Locations.Pen
    timestamps(type: :utc_datetime)
  end

  def purposes, do: @purposes

  def changeset(house, attrs) do
    house
    |> cast(attrs, [:code, :purpose, :farm_id])
    |> validate_required([:code, :purpose, :farm_id])
    |> validate_length(:code, min: 1, max: 40)
    |> validate_inclusion(:purpose, @purposes)
    |> unique_constraint([:farm_id, :code])
  end
end
