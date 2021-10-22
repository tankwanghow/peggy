defmodule Peggy.Authorization do
  import Ecto.Query, warn: false
  import PeggyWeb.Gettext

  alias Peggy.Repo

  @allow {:allow, gettext("Authorized")}
  @forbid {:forbid, gettext("Not Authorise")}
  @forbid_user_disabled {:forbid, gettext("User has been Disabled")}

  def can?(farm_user, :cud_location) do
    if Enum.find(["guest", "disable"], fn x -> x == farm_user.role end), do: @forbid, else: @allow
  end

  def can?("disable", _action), do: @forbid_user_disabled
  def can?(_role, _action), do: @forbid

  def can?(user_id, :delete_farm, farm_id) do
    if user_role_in_farm(user_id, farm_id) == "admin" do
      @allow
    else
      @forbid
    end
  end

  def can?(user_id, :update_farm, farm_id) do
    if user_role_in_farm(user_id, farm_id) == "admin" do
      @allow
    else
      @forbid
    end
  end

  def can?(current_farm_user, :allow_farm_access_to, user_id) do
    if user_role_in_farm(current_farm_user.user_id, current_farm_user.farm_id) == "admin" do
      if current_farm_user.user_id == user_id do
        {:forbid, gettext("Cannot invite yourself")}
      else
        @allow
      end
    else
      @forbid
    end
  end

  def can?(current_farm_user, :change_role_of, user_id) do
    if user_role_in_farm(current_farm_user.user_id, current_farm_user.farm_id) == "admin" do
      if current_farm_user.user_id == user_id do
        {:forbid, gettext("Cannot change own role")}
      else
        @allow
      end
    else
      @forbid
    end
  end

  def can?("disable", _action, _resource), do: @forbid_user_disabled
  def can?(_role, _action, _resource), do: @forbid

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

  def is_user_admin?(user_id, farm_id) do
    user_role_in_farm(user_id, farm_id) == "admin"
  end

  defp allow_if_role_not_disable(farm_user), do: if farm_user.role != "disable", do: @allow, else: @forbid_user_disabled
end
