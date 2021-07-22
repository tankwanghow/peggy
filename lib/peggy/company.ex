defmodule Peggy.Company do
  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Peggy.Repo
  alias Peggy.Company.Farm
  alias Peggy.Company.FarmUser

  def list_farms(user) do
    Repo.all(from f in Farm,
             join: fu in FarmUser,
             on: fu.user_id == ^user.id and f.id == fu.farm_id,
             order_by: f.name)
  end

  def get_farm!(id, user) do
    Repo.get!((from f in Farm,
               join: fu in FarmUser,
               on: fu.user_id == ^user.id and f.id == fu.farm_id,
               select: f,
               order_by: f.name), id)
  end

  def create_farm(attrs \\ %{}, user) do
    Multi.new()
    |> Multi.insert(:farm, Farm.changeset(%Farm{}, attrs, user))
    |> Multi.insert(:farm_user, fn %{farm: farm} ->
        Ecto.build_assoc(farm, :farm_user, role: "admin", user_id: user.id) end)
    |> Peggy.Repo.transaction()
    |> case do
      {:ok, %{farm: farm}} -> {:ok, farm}
      {:error, :farm, changeset, _} -> {:error, changeset}
    end
  end

  def user_role_in_farm(user, farm) do
    roles = Repo.all(from fu in FarmUser,
                       where: fu.user_id == ^user.id and fu.farm_id == ^farm.id,
                       select: fu.role)
    case roles do
      [role] -> role
      _ -> :no_access
    end
  end

  def allow_user_access_farm(user, farm, role, admin) do
    if user_role_in_farm(admin, farm) == "admin" do
      %FarmUser{}
      |> FarmUser.changeset(%{user_id: user.id, farm_id: farm.id, role: role})
      |> Repo.insert()
    else
      raise "Not Authorized"
    end
  end

  def change_user_role_in_farm(user, farm, role, admin) do
    if(user == admin, do: raise "Cannot change own role")
    if user_role_in_farm(admin, farm) == "admin" do
      fu = Repo.get_by(FarmUser, farm_id: farm.id, user_id: user.id)
      FarmUser.changeset(fu, %{role: role})
      |> Repo.update
    else
      raise "Not Authorized"
    end
  end

  def update_farm(%Farm{} = farm, attrs, user) do
    if user_role_in_farm(user, farm) == "admin" do
      farm
      |> Farm.changeset(attrs, user)
      |> Repo.update()
    else
      raise "Not Authorized"
    end
  end

  def change_farm(%Farm{} = farm, attrs \\ %{}, user) do
    Farm.changeset(farm, attrs, user)
  end
end
