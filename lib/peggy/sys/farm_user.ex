defmodule Peggy.Sys.FarmUser do
  use Peggy.Schema
  import Ecto.Changeset
  import PeggyWeb.Gettext

  schema "farm_user" do
    field :role, :string
    field :default_farm, :boolean, default: false
    belongs_to :farm, Peggy.Sys.Farm
    belongs_to :user, Peggy.UserAccounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(farm_user, attrs) do
    farm_user
    |> cast(attrs, [:role, :default_farm, :farm_id, :user_id])
    |> unique_constraint(:email,
      name: :farm_user_unique_user_in_farm,
      message: gettext("already in farm")
    )
    |> validate_required([:role, :farm_id, :user_id])
    |> validate_inclusion(:role, Peggy.Authorization.roles(),
      message: gettext("not in list")
    )
  end
end
