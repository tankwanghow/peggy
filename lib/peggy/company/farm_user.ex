defmodule Peggy.Company.FarmUser do
  use Ecto.Schema
  import Ecto.Changeset

  schema "farm_user" do
    field :role, :string
    belongs_to :farm, Peggy.Company.Farm
    belongs_to :user, Peggy.UserAccounts.User

    timestamps()
  end

  @doc false
  def changeset(farm_user, attrs) do
    farm_user
    |> cast(attrs, [:role, :farm_id, :user_id])
    |> validate_required([:role, :farm_id, :user_id])
    |> validate_inclusion(:role, Peggy.Company.roles)
  end
end
