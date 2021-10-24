defmodule Peggy.Farm.Location do
  use Ecto.Schema
  import Ecto.Changeset
  import PeggyWeb.Gettext

  def status do
    ["active", "fixing", "remove"]
  end

  schema "locations" do
    field :capacity, :integer, default: 1
    field :code, :string
    field :note, :string
    field :status, :string, default: "active"
    belongs_to :farm, Peggy.Company.Farm

    timestamps()
  end

  @doc false
  def changeset(location, attrs) do
    location
    |> cast(attrs, [:code, :note, :capacity, :status, :farm_id])
    |> validate_required([:status, :farm_id])
    |> validate_required(:code)
    |> validate_required(:capacity)
    |> validate_inclusion(:status, status())
    |> validate_inclusion(:capacity, 1..10000)
    |> unsafe_validate_unique([:code, :farm_id], Peggy.Repo)
  end
end
