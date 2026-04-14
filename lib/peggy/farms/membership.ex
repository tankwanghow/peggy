defmodule Peggy.Farms.Membership do
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(owner manager worker vet)

  schema "memberships" do
    field :role, :string
    field :accepted_at, :utc_datetime
    field :is_default, :boolean, default: false

    belongs_to :user, Peggy.Accounts.User
    belongs_to :farm, Peggy.Farms.Farm
    belongs_to :invited_by, Peggy.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def roles, do: @roles

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:user_id, :farm_id, :role, :invited_by_id, :accepted_at])
    |> validate_required([:user_id, :farm_id, :role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:user_id, :farm_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:farm_id)
  end

  def role_changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role])
    |> validate_required([:role])
    |> validate_inclusion(:role, @roles)
  end
end
