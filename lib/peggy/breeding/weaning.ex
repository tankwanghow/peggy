defmodule Peggy.Breeding.Weaning do
  use Ecto.Schema
  import Ecto.Changeset

  schema "breeding_weanings" do
    field :weaned_at, :date
    field :weaned_count, :integer
    field :avg_wean_weight_g, :integer
    field :notes, :string
    belongs_to :farm, Peggy.Farms.Farm
    belongs_to :farrowing, Peggy.Breeding.Farrowing
    belongs_to :destination_pen, Peggy.Locations.Pen
    timestamps(type: :utc_datetime)
  end

  def changeset(weaning, attrs) do
    weaning
    |> cast(attrs, [
      :weaned_at,
      :weaned_count,
      :avg_wean_weight_g,
      :notes,
      :farrowing_id,
      :destination_pen_id,
      :farm_id
    ])
    |> validate_required([:weaned_at, :weaned_count, :farrowing_id, :farm_id])
    |> validate_number(:weaned_count, greater_than_or_equal_to: 0)
    |> validate_number(:avg_wean_weight_g, greater_than: 0)
    |> unique_constraint(:farrowing_id)
  end
end
