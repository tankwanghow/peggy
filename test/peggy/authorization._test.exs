defmodule Peggy.AuthorizationTest do
  use ExUnit.Case
  import Peggy.Authorization

  # can?(current_farm_user, :invite, user)


  # test "user_role_in_farm/2 should return :no_access, if not exists" do
  #   admin = user_fixture()
  #   user1 = user_fixture()
  #   assert {:ok, %Farm{} = farm} = Company.create_farm(@valid_attrs, admin)
  #   assert Company.user_role_in_farm(user1.id, farm.id) == :no_access
  # end
end
