defmodule Peggy.Breeding.Weaning do
  use Ecto.Schema
  import Ecto.Changeset

  schema "breeding_weanings" do
    field :weaned_at, :date
    field :weaned_count, :integer
    field :avg_wean_weight_g, :integer
    field :notes, :string
    field :inferred, :boolean, default: false
    field :created_via, :string
    belongs_to :origin_audit, Peggy.Audit.AuditLog
    belongs_to :farm, Peggy.Farms.Farm
    belongs_to :farrowing, Peggy.Breeding.Farrowing
    belongs_to :destination_pen, Peggy.Locations.Pen
    belongs_to :batch_animal, Peggy.Animals.Animal
    field :deleted_at, :utc_datetime
    belongs_to :deleted_by, Peggy.Accounts.User
    timestamps(type: :utc_datetime)
  end

  def changeset(weaning, attrs) do
    weaning
    |> cast(attrs, [
      :weaned_at,
      :weaned_count,
      :avg_wean_weight_g,
      :notes,
      :inferred,
      :created_via,
      :origin_audit_id,
      :farrowing_id,
      :destination_pen_id,
      :batch_animal_id,
      :farm_id
    ])
    |> validate_required([:weaned_at, :weaned_count, :farrowing_id, :farm_id])
    # Large weaned litters (16–20) occur with hyperprolific sows and
    # cross-fostering; cap at 20 rather than 15 to admit them.
    |> validate_number(:weaned_count, greater_than_or_equal_to: 0, less_than_or_equal_to: 20)
    |> validate_number(:avg_wean_weight_g, greater_than: 0)
    |> unique_constraint(:farrowing_id,
      name: :breeding_weanings_farrowing_id_active_index
    )
  end
end
