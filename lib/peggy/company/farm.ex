defmodule Peggy.Company.Farm do
  use Ecto.Schema
  import Ecto.Changeset

  schema "farms" do
    field :address1, :string
    field :address2, :string
    field :city, :string
    field :country, :string
    field :name, :string
    field :state, :string
    field :weight_unit, :string
    field :zipcode, :string

    timestamps()
  end

  @doc false
  def changeset(farm, attrs) do
    farm
    |> cast(attrs, [:name, :address1, :address2, :city, :zipcode, :state, :country, :weight_unit])
    |> validate_required([:name, :address1, :city, :zipcode, :state, :country, :weight_unit])
  end

  def create_changeset(farm, attrs) do
    farm
    |> cast(attrs, [:name, :address1, :address2, :city, :zipcode, :state, :country, :weight_unit])
    |> validate_required([:name, :address1, :city, :zipcode, :state, :country, :weight_unit])
  end
end
