defmodule Peggy.Company.FarmUser do
  use Ecto.Schema
  import Ecto.Changeset

  schema "farm_users" do
    field :role, :string
    field :farm_id, :id
    field :user_id, :id

    timestamps()
  end

  @doc false
  def changeset(farm_user, attrs) do
    farm_user
    |> cast(attrs, [:role])
    |> validate_required([:role])
  end
end
