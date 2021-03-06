defmodule Peggy.Company.Farm do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias Peggy.Repo
  import PeggyWeb.Gettext

  schema "farms" do
    field :address1, :string
    field :address2, :string
    field :city, :string
    field :country, :string
    field :name, :string
    field :state, :string
    field :zipcode, :string

    field :weight_unit, :string, default: "KG"
    field :birth_to_wean, :integer, default: 28
    field :paired_to_farrow, :integer, default: 114
    field :wean_to_pair, :integer, default: 7
    field :paired_to_prefarrow, :integer, default: 100

    many_to_many :users, Peggy.UserAccounts.User,
      join_through: Peggy.Company.FarmUser,
      on_replace: :delete

    has_many :farm_user, Peggy.Company.FarmUser

    timestamps()
  end

  def changeset(farm, attrs, user) do
    nt_farm = farm

    farm =
      farm
      |> cast(attrs, [
        :name,
        :address1,
        :address2,
        :city,
        :zipcode,
        :state,
        :country,
        :weight_unit,
        :birth_to_wean,
        :paired_to_prefarrow,
        :paired_to_farrow,
        :wean_to_pair
      ])
      |> validate_required([
        :name,
        :address1,
        :city,
        :zipcode,
        :state,
        :country,
        :weight_unit,
        :birth_to_wean,
        :paired_to_prefarrow,
        :paired_to_farrow,
        :wean_to_pair
      ])
      |> validate_inclusion(:country, Peggy.Company.countries())

    if farm.changes[:name] do
      if Ecto.get_meta(nt_farm, :state) == :loaded do
        validate_unique_farm_name_by_user(farm, user, nt_farm.id)
      else
        validate_unique_farm_name_by_user(farm, user)
      end
    else
      farm
    end
  end

  defp validate_unique_farm_name_by_user(changeset, user, farm_id) do
    case Repo.exists?(farm_name_by_user_query(changeset.changes[:name], user, farm_id)) do
      true -> add_error(changeset, :name, gettext("has already been taken"))
      false -> changeset
    end
  end

  defp validate_unique_farm_name_by_user(changeset, user) do
    case Repo.exists?(farm_name_by_user_query(changeset.changes[:name], user)) do
      true -> add_error(changeset, :name, gettext("has already been taken"))
      false -> changeset
    end
  end

  defp farm_name_by_user_query(name, user, farm_id) do
    from f in Peggy.Company.Farm,
      join: fu in Peggy.Company.FarmUser,
      on: f.id == fu.farm_id,
      where: fu.user_id == ^user.id and f.name == ^name and f.id != ^farm_id,
      select: f
  end

  defp farm_name_by_user_query(name, user) do
    from f in Peggy.Company.Farm,
      join: fu in Peggy.Company.FarmUser,
      on: f.id == fu.farm_id,
      where: fu.user_id == ^user.id and f.name == ^name,
      select: f
  end
end
