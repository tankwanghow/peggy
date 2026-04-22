defmodule Peggy.Breeding.LitterEvent do
  @moduledoc """
  Pre-wean piglet bookkeeping: deaths and fostering on/off.

  Piglets do not exist as `Animal` rows during lactation. Instead, each
  farrowing owns a ledger of `LitterEvent` rows, and surviving count is
  derived:

      surviving = born_alive
                + Σ foster_in
                − Σ foster_out
                − Σ death

  Fostering writes a pair of rows atomically: a `foster_out` on the
  source farrowing and a `foster_in` on the destination farrowing, each
  pointing at the other via `counterpart_farrowing_id`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(death foster_out foster_in)
  def kinds, do: @kinds

  schema "breeding_litter_events" do
    field :kind, :string
    field :quantity, :integer
    field :occurred_at, :date
    field :notes, :string
    belongs_to :farm, Peggy.Farms.Farm
    belongs_to :farrowing, Peggy.Breeding.Farrowing
    belongs_to :counterpart_farrowing, Peggy.Breeding.Farrowing
    belongs_to :created_by, Peggy.Accounts.User
    field :deleted_at, :utc_datetime
    belongs_to :deleted_by, Peggy.Accounts.User
    timestamps(type: :utc_datetime)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :kind,
      :quantity,
      :occurred_at,
      :notes,
      :farm_id,
      :farrowing_id,
      :counterpart_farrowing_id,
      :created_by_id
    ])
    |> validate_required([:kind, :quantity, :occurred_at, :farm_id, :farrowing_id])
    |> validate_inclusion(:kind, @kinds)
    |> validate_number(:quantity, greater_than: 0)
    |> validate_counterpart()
  end

  defp validate_counterpart(changeset) do
    kind = get_field(changeset, :kind)
    counterpart = get_field(changeset, :counterpart_farrowing_id)

    cond do
      kind == "death" and not is_nil(counterpart) ->
        add_error(changeset, :counterpart_farrowing_id, "must be nil for death events")

      kind in ["foster_out", "foster_in"] and is_nil(counterpart) ->
        add_error(changeset, :counterpart_farrowing_id, "is required for fostering events")

      true ->
        changeset
    end
  end
end
