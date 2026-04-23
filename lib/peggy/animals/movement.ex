defmodule Peggy.Animals.Movement do
  use Ecto.Schema
  import Ecto.Changeset

  @reasons ~w(placement pen_transfer sale slaughter death farm_transfer adjustment_loss adjustment_gain wean)

  schema "movements" do
    field :reason, :string
    field :quantity, :integer, default: 1
    field :moved_at, :date
    field :notes, :string
    field :previous_status, :string
    belongs_to :farm, Peggy.Farms.Farm
    belongs_to :animal, Peggy.Animals.Animal
    belongs_to :from_pen, Peggy.Locations.Pen
    belongs_to :to_pen, Peggy.Locations.Pen
    belongs_to :weaning, Peggy.Breeding.Weaning
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
      :previous_status,
      :animal_id,
      :farm_id,
      :from_pen_id,
      :to_pen_id,
      :weaning_id
    ])
    |> validate_required([:reason, :quantity, :moved_at, :animal_id, :farm_id])
    |> validate_inclusion(:reason, @reasons)
    |> validate_number(:quantity, greater_than: 0)
    |> validate_wean_requires_weaning()
  end

  defp validate_wean_requires_weaning(cs) do
    case {get_field(cs, :reason), get_field(cs, :weaning_id)} do
      {"wean", nil} ->
        add_error(cs, :weaning_id, "wean movements may only be created by a weaning operation")

      {reason, wid} when reason != "wean" and not is_nil(wid) ->
        add_error(cs, :reason, "weaning_id is only allowed for wean movements")

      _ ->
        cs
    end
  end
end
