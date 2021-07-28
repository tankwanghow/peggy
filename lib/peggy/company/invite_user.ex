defmodule Peggy.Company.InviteUser do
  use Ecto.Schema
  import Ecto.Changeset

  schema "invite_users" do
    field :email, :string
    field :role, :string
    belongs_to :farm, Peggy.Company.Farm

    timestamps()
  end

  @doc false
  def changeset(invite_user, attrs) do
    invite_user
    |> cast(attrs, [:email, :role])
    |> validate_required([:email, :role])
    |> validate_inclusion(:role, Peggy.Company.roles)
  end
end
