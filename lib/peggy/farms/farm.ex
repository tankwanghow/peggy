defmodule Peggy.Farms.Farm do
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(owner manager worker vet)a
  @unit_systems ~w(metric imperial)
  @plans ~w(free pro)

  schema "farms" do
    field :slug, :string
    field :name, :string
    field :timezone, :string, default: "Etc/UTC"
    field :unit_system, :string, default: "metric"
    field :plan, :string, default: "free"
    field :seat_limit, :integer, default: 5

    field :deleted_at, :utc_datetime
    belongs_to :deleted_by, Peggy.Accounts.User

    has_many :memberships, Peggy.Farms.Membership
    has_many :users, through: [:memberships, :user]

    timestamps(type: :utc_datetime)
  end

  def roles, do: @roles

  def changeset(farm, attrs) do
    farm
    |> cast(attrs, [:slug, :name, :timezone, :unit_system, :plan, :seat_limit])
    |> validate_required([:slug, :name, :timezone])
    |> update_change(:slug, &String.downcase/1)
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9-]*[a-z0-9]$/,
      message: "lowercase letters, digits, and hyphens only"
    )
    |> validate_length(:slug, min: 3, max: 40)
    |> validate_length(:name, min: 1, max: 120)
    |> validate_inclusion(:unit_system, @unit_systems)
    |> validate_inclusion(:plan, @plans)
    |> validate_number(:seat_limit, greater_than: 0)
    |> unique_constraint(:slug)
  end
end
