defmodule Peggy.Breeding.Farrowing do
  use Ecto.Schema
  import Ecto.Changeset

  schema "breeding_farrowings" do
    field :farrowed_at, :date
    field :born_alive, :integer
    field :stillborn, :integer, default: 0
    field :mummified, :integer, default: 0
    field :total_birth_weight_g, :integer
    field :notes, :string
    belongs_to :farm, Peggy.Farms.Farm
    belongs_to :service, Peggy.Breeding.Service
    belongs_to :sow, Peggy.Animals.Animal
    belongs_to :pen, Peggy.Locations.Pen
    has_one :weaning, Peggy.Breeding.Weaning
    has_many :piglets, Peggy.Animals.Animal, foreign_key: :farrowing_id
    timestamps(type: :utc_datetime)
  end

  def changeset(farrowing, attrs) do
    farrowing
    |> cast(attrs, [
      :farrowed_at,
      :born_alive,
      :stillborn,
      :mummified,
      :total_birth_weight_g,
      :notes,
      :service_id,
      :sow_id,
      :pen_id,
      :farm_id
    ])
    |> validate_required([:farrowed_at, :born_alive, :service_id, :sow_id, :farm_id])
    |> validate_number(:born_alive, greater_than_or_equal_to: 0)
    |> validate_number(:stillborn, greater_than_or_equal_to: 0)
    |> validate_number(:mummified, greater_than_or_equal_to: 0)
    |> validate_number(:total_birth_weight_g, greater_than: 0)
    |> unique_constraint(:service_id)
  end
end
