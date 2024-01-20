defmodule Peggy.Sys.Farm do
  use Peggy.Schema
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
    field :timezone, :string
    field :email, :string
    field :tel, :string
    field :descriptions, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(farm, attrs, user) do
    farm
    |> cast(attrs, [
      :name,
      :address1,
      :address2,
      :city,
      :zipcode,
      :state,
      :country,
      :timezone,
      :email,
      :tel,
      :descriptions
    ])
    |> validate_required([
      :name,
      :country,
      :timezone
    ])
    |> validate_inclusion(:country, Peggy.Sys.countries(), message: gettext("not in list"))
    |> validate_inclusion(:timezone, Tzdata.zone_list(), message: gettext("not in list"))
    |> validate_unique_by_user(:name, user)
  end

  def validate_unique_by_user(changeset, field, user) do
    {_, name} = fetch_field(changeset, field)
    {_, id} = fetch_field(changeset, :id)

    if Repo.exists?(farm_name_by_user_query(name || "", id, user)) do
      add_error(changeset, field, gettext("has already been taken"))
    else
      changeset
    end
  end

  defp farm_name_by_user_query(name, farm_id, user) when is_nil(farm_id) do
    from f in Peggy.Sys.Farm,
      join: fu in Peggy.Sys.FarmUser,
      on: f.id == fu.farm_id,
      where: fu.user_id == ^user.id and f.name == ^name,
      select: f
  end

  defp farm_name_by_user_query(name, farm_id, user) do
    from f in Peggy.Sys.Farm,
      join: fu in Peggy.Sys.FarmUser,
      on: f.id == fu.farm_id,
      where: fu.user_id == ^user.id and f.name == ^name and f.id != ^farm_id,
      select: f
  end
end
