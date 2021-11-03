defmodule Peggy.Authorization do
  import Ecto.Query, warn: false
  import PeggyWeb.Gettext

  alias Peggy.Repo

  @allow {:allow, gettext("Authorized")}
  @forbid {:forbid, gettext("Not Authorise")}

  def can?(farm_user, :create_sow), do: forbid_role(["guest", "disable"], role(farm_user))
  def can?(farm_user, :update_sow), do: forbid_role(["guest", "disable"], role(farm_user))
  def can?(farm_user, :delete_sow), do: forbid_role(["guest", "disable"], role(farm_user))

  def can?(farm_user, :create_location), do: forbid_role(["guest", "disable"], role(farm_user))
  def can?(farm_user, :update_location), do: forbid_role(["guest", "disable"], role(farm_user))
  def can?(farm_user, :delete_location), do: forbid_role(["guest", "disable"], role(farm_user))

  def can?(farm_user, :see_user_list), do: allow_role("admin", role(farm_user))

  def can?(user_id, :delete_farm, farm_id), do: allow_role("admin", user_role_in_farm(user_id, farm_id))
  def can?(user_id, :update_farm, farm_id), do: allow_role("admin", user_role_in_farm(user_id, farm_id))

  def can?(farm_user, :allow_farm_access_to, user_id) do
    if user_role_in_farm(farm_user.user_id, farm_user.farm_id) == "admin" do
      if farm_user.user_id == user_id do
        {:forbid, gettext("Cannot invite yourself")}
      else
        @allow
      end
    else
      @forbid
    end
  end

  def can?(farm_user, :change_role_of, user_id) do
    if user_role_in_farm(farm_user.user_id, farm_user.farm_id) == "admin" do
      if farm_user.user_id == user_id do
        {:forbid, gettext("Cannot change own role")}
      else
        @allow
      end
    else
      @forbid
    end
  end

  def user_role_in_farm(user_id, farm_id) do
    role =
      Repo.one(
        from fu in Peggy.Company.FarmUser,
          where: fu.user_id == ^user_id and fu.farm_id == ^farm_id,
          select: fu.role
      )

    if role == "disable" || role == nil do
      :no_access
    else
      role
    end
  end

  defp allow_role(role, test_role) when is_binary(role) do
    if role == test_role, do: @allow, else: @forbid
  end

  defp allow_role(roles, role) when is_list(roles) do
    if Enum.find(roles, fn r -> r == role end), do: @allow, else: @forbid
  end

  defp forbid_role(role, test_role) when is_binary(role) do
    if role != test_role, do: @allow, else: @forbid
  end

  defp forbid_role(roles, role) when is_list(roles) do
    if Enum.find(roles, fn r -> r == role end), do: @forbid, else: @allow
  end

  defp role(farm_user) when farm_user == nil do
    :no_access
  end

  defp role(farm_user) do
    farm_user.role
  end
end
