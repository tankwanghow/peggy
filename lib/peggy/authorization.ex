defmodule Peggy.Authorization do
  import Ecto.Query, warn: false

  def roles do
    ~w(guest admin manager supervisor operator clerk disable)
  end

  @allow true
  @forbid false

  def can?(user, :see_user_list, farm), do: allow_role("admin", farm, user)
  def can?(user, :manage_rouge_user, farm), do: allow_role("admin", farm, user)
  def can?(user, :invite_farm, farm), do: allow_role("admin", farm, user)
  def can?(user, :add_user_to_farm, farm), do: allow_role("admin", farm, user)
  def can?(user, :delete_user_from_farm, farm), do: allow_role("admin", farm, user)
  def can?(user, :delete_farm, farm), do: allow_role("admin", farm, user)
  def can?(user, :update_farm, farm), do: allow_role("admin", farm, user)
  def can?(user, :reset_user_password, farm), do: allow_role("admin", farm, user)

  def can?(admin, :change_user_role, farm, user) do
    if user_role_in_farm(admin.id, farm.id) == "admin" do
      if admin.id == user.id do
        @forbid
      else
        @allow
      end
    else
      @forbid
    end
  end

  defp user_role_in_farm(user_id, farm_id) do
    role = Util.attempt(Peggy.Sys.get_farm_user(farm_id, user_id), :role)

    if role == nil do
      "disable"
    else
      role
    end
  end

  defp allow_role(role, farm, user) when is_binary(role) do
    test_role = user_role_in_farm(user.id, farm.id)
    if role == test_role, do: @allow, else: @forbid
  end

  # defp allow_roles(roles, farm, user) when is_list(roles) do
  #   test_role = user_role_in_farm(user.id, farm.id)
  #   if Enum.find(roles, fn r -> r == test_role end), do: @allow, else: @forbid
  # end

  # defp forbid_roles(roles, farm, user) when is_list(roles) do
  #   test_role = user_role_in_farm(user.id, farm.id)
  #   if Enum.find(roles, fn r -> r == test_role end), do: @forbid, else: @allow
  # end

  # defp forbid_role(role, farm, user) when is_binary(role) do
  #   test_role = user_role_in_farm(user.id, farm.id)
  #   if role == test_role, do: @forbid, else: @allow
  # end
end
