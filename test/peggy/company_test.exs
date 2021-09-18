defmodule Peggy.CompanyTest do
  use Peggy.DataCase

  alias Peggy.Company
  import Peggy.UserAccountsFixtures

  describe "farms" do
    alias Peggy.Company.Farm
    alias Peggy.Company.FarmUser

    @valid_attrs %{address1: "some address1", address2: "some address2", city: "some city", country: "Malaysia", name: "some name", state: "some state", weight_unit: "some weight_unit", zipcode: "some zipcode"}
    @update_attrs %{address1: "some updated address1", address2: "some updated address2", city: "some updated city", country: "Thailand", name: "some updated name", state: "some updated state", weight_unit: "some updated weight_unit", zipcode: "some updated zipcode"}
    @invalid_attrs %{address1: nil, address2: nil, city: nil, country: nil, name: nil, state: nil, weight_unit: nil, zipcode: nil}

    test "list_farms/1 returns all farms for user" do
      admin = user_fixture()
      user1 = user_fixture()
      assert {:ok, %Farm{} = farm} = Company.create_farm(@valid_attrs, admin)
      assert {:ok, %Farm{} = farm1} = Company.create_farm(@update_attrs, admin)
      farm_attrs = Map.merge(@valid_attrs, %{id: farm.id, default_farm: false})
      farm1_attrs = Map.merge(@update_attrs, %{id: farm1.id, default_farm: false})
      assert Company.list_farms(admin) == [farm_attrs, farm1_attrs]
      assert Company.list_farms(user1) == []
    end

    test "get_farm!/2 returns the farm with given id" do
      admin = user_fixture()
      user1 = user_fixture()
      assert {:ok, %Farm{} = farm} = Company.create_farm(@valid_attrs, admin)
      assert {:ok, %Farm{} = farm1} = Company.create_farm(@update_attrs, admin)
      assert Company.get_farm!(farm1.id, admin) == farm1
      assert_raise Ecto.NoResultsError, fn -> Company.get_farm!(farm.id, user1) end
    end

    test "admin cannot create a farms with the same name" do
      admin = user_fixture()
      assert {:ok, _} = Company.create_farm(@valid_attrs, admin)
      assert {:error, %Ecto.Changeset{}} = Company.create_farm(@valid_attrs, admin)
    end

    test "admin cannot update farm to a duplicated name" do
      admin = user_fixture()
      assert {:ok, _} = Company.create_farm(@valid_attrs, admin)
      assert {:ok, farm} = Company.create_farm(@update_attrs, admin)
      assert {:ok, _} = Company.update_farm(farm, %{name: "other name"}, admin)
      assert {:error, %Ecto.Changeset{}} = Company.update_farm(farm, @valid_attrs, admin)
    end

    test "create_farm/2 with valid data creates a farm" do
      admin = user_fixture()
      assert {:ok, %Farm{} = farm} = Company.create_farm(@valid_attrs, admin)
      assert farm.address1 == "some address1"
      assert farm.address2 == "some address2"
      assert farm.city == "some city"
      assert farm.country == "Malaysia"
      assert farm.name == "some name"
      assert farm.state == "some state"
      assert farm.weight_unit == "some weight_unit"
      assert farm.zipcode == "some zipcode"
      farm = Peggy.Repo.preload(farm, [:users, :farm_user])
      assert farm.users == [admin]
    end

    test "create_farm/2 with invalid data returns error changeset" do
      admin = user_fixture()
      assert {:error, %Ecto.Changeset{}} = Company.create_farm(@invalid_attrs, admin)
    end

    test "user are not allow to have 2 role in a farm" do
      admin = user_fixture()
      assert {:ok, %Farm{} = farm} = Company.create_farm(@valid_attrs, admin)
      assert_raise Ecto.ConstraintError, fn -> Company.allow_user_access_farm(admin, farm, "clerk", admin) end
    end

    test "user_role_in_farm/2 should return :no_access, if not exists" do
      admin = user_fixture()
      user1 = user_fixture()
      assert {:ok, %Farm{} = farm} = Company.create_farm(@valid_attrs, admin)
      assert Company.user_role_in_farm(user1, farm) == :no_access
    end

    test "farm creator should be the admin" do
      admin = user_fixture()
      assert {:ok, %Farm{} = farm} = Company.create_farm(@valid_attrs, admin)
      assert Company.user_role_in_farm(admin, farm) == "admin"
    end

    test "allow_user_access_farm/4 with role" do
      admin = user_fixture()
      user1 = user_fixture()
      assert {:ok, %Farm{} = farm} = Company.create_farm(@valid_attrs, admin)
      assert {:ok, %FarmUser{} = farm_user} = Company.allow_user_access_farm(user1, farm, "manager", admin)
      farm = Peggy.Repo.preload(farm, [:users, :farm_user])
      assert farm.users == [admin, user1]
      assert farm_user.role == "manager"
    end

    test "only allow admin to allow_user_access_farm" do
      admin = user_fixture()
      user1 = user_fixture()
      user2 = user_fixture()
      assert {:ok, %Farm{} = farm} = Company.create_farm(@valid_attrs, admin)
      Company.allow_user_access_farm(user1, farm, "manager", admin)
      assert_raise(RuntimeError, "Not Authorized", fn -> Company.allow_user_access_farm(user2, farm, "clerk", user1) end)
    end

    test "only admin can change user role" do
      admin = user_fixture()
      user1 = user_fixture()
      user2 = user_fixture()
      assert {:ok, %Farm{} = farm} = Company.create_farm(@valid_attrs, admin)
      assert {:ok, %FarmUser{} = farm_user} = Company.allow_user_access_farm(user1, farm, "manager", admin)
      assert {:ok, %FarmUser{} = farm_user1} = Company.allow_user_access_farm(user2, farm, "manager", admin)
      assert farm_user.role == "manager"
      assert farm_user1.role == "manager"
      assert {:ok, %FarmUser{} = farm_user} = Company.change_user_role_in_farm(user1, farm, "clerk", admin)
      assert farm_user.role == "clerk"
      assert_raise(RuntimeError, "Not Authorized", fn -> Company.change_user_role_in_farm(user2, farm, "clerk", user1) end)
    end

    test "user cannot change own role" do
      admin = user_fixture()
      assert {:ok, %Farm{} = farm} = Company.create_farm(@valid_attrs, admin)
      assert_raise(RuntimeError, "Cannot change own role", fn -> Company.change_user_role_in_farm(admin, farm, "clerk", admin) end)
      assert Company.user_role_in_farm(admin, farm) == "admin"
    end

    test "update_farm/3 with valid data updates the farm, if user is admin" do
      admin = user_fixture()
      assert {:ok, %Farm{} = farm} = Company.create_farm(@valid_attrs, admin)
      assert {:ok, %Farm{} = farm} = Company.update_farm(farm, @update_attrs, admin)
      assert farm.address1 == "some updated address1"
      assert farm.address2 == "some updated address2"
      assert farm.city == "some updated city"
      assert farm.country == "Thailand"
      assert farm.name == "some updated name"
      assert farm.state == "some updated state"
      assert farm.weight_unit == "some updated weight_unit"
      assert farm.zipcode == "some updated zipcode"
    end

    test "cannot update_farm/3 with valid data updates the farm, if user is not admin" do
      admin = user_fixture()
      user = user_fixture()
      assert {:ok, %Farm{} = farm} = Company.create_farm(@valid_attrs, admin)
      assert_raise(RuntimeError, "Not Authorized", fn -> Company.update_farm(farm, @update_attrs, user) end)
    end

    test "update_farm/3 with invalid data returns error changeset" do
      user = user_fixture()
      assert {:ok, %Farm{} = farm} = Company.create_farm(@valid_attrs, user)
      assert {:error, %Ecto.Changeset{}} = Company.update_farm(farm, @invalid_attrs, user)
      assert farm == Company.get_farm!(farm.id, user)
    end

    test "change_farm/3 returns a farm changeset, if user is admin" do
      admin = user_fixture()
      assert {:ok, %Farm{} = farm} = Company.create_farm(@valid_attrs, admin)
      assert %Ecto.Changeset{} = Company.change_farm(farm, admin)
    end

    test "delete_farm/2, if user is admin" do
      admin = user_fixture()
      assert {:ok, %Farm{} = farm} = Company.create_farm(@valid_attrs, admin)
      assert {:ok, _} = Company.delete_farm(farm, admin)
      assert_raise(Ecto.NoResultsError, fn -> Company.get_farm!(farm.id, admin) end)
    end

    test "delete_farm/2, if user is not admin" do
      admin = user_fixture()
      user = user_fixture()
      assert {:ok, %Farm{} = farm} = Company.create_farm(@valid_attrs, admin)
      assert_raise(RuntimeError, "Not Authorized", fn -> Company.delete_farm(farm, user) end)
    end

    test "update farm_user default_active_farm" do
      admin = user_fixture()
      assert {:ok, %Farm{} = farm} = Company.create_farm(@valid_attrs, admin)
      assert {:ok, %Farm{} = farm1} = Company.create_farm(@update_attrs, admin)
      assert nil == Company.get_default_farm(admin)
      assert {:ok, _} = Company.set_default_farm(admin.id, farm1.id)
      assert farm1 == Company.get_default_farm(admin)
      assert {:ok, _} = Company.set_default_farm(admin.id, farm.id)
      assert farm == Company.get_default_farm(admin)
    end

  end

  # describe "invite_users" do
  #   alias Peggy.Company.InviteUser

  #   @valid_attrs %{email: "some email", role: "manager"}
  #   @update_attrs %{email: "some updated email", role: "some updated role"}
  #   @invalid_attrs %{email: nil, role: nil}

  #   def invite_user_fixture(attrs \\ %{}) do
  #     {:ok, invite_user} =
  #       attrs
  #       |> Enum.into(@valid_attrs)
  #       |> Company.create_invite_user()

  #     invite_user
  #   end

  #   test "list_invite_users/0 returns all invite_users" do
  #     invite_user = invite_user_fixture()
  #     assert Company.list_invite_users() == [invite_user]
  #   end

  #   test "get_invite_user!/1 returns the invite_user with given id" do
  #     invite_user = invite_user_fixture()
  #     assert Company.get_invite_user!(invite_user.id) == invite_user
  #   end

  #   test "create_invite_user/1 with valid data creates a invite_user" do
  #     assert {:ok, %InviteUser{} = invite_user} = Company.create_invite_user(@valid_attrs)
  #     assert invite_user.email == "some email"
  #     assert invite_user.role == "manager"
  #   end

  #   test "create_invite_user/1 with invalid data returns error changeset" do
  #     assert {:error, %Ecto.Changeset{}} = Company.create_invite_user(@invalid_attrs)
  #   end

  #   test "update_invite_user/2 with valid data updates the invite_user" do
  #     invite_user = invite_user_fixture()
  #     assert {:ok, %InviteUser{} = invite_user} = Company.update_invite_user(invite_user, @update_attrs)
  #     assert invite_user.email == "some updated email"
  #     assert invite_user.role == "some updated role"
  #   end

  #   test "update_invite_user/2 with invalid data returns error changeset" do
  #     invite_user = invite_user_fixture()
  #     assert {:error, %Ecto.Changeset{}} = Company.update_invite_user(invite_user, @invalid_attrs)
  #     assert invite_user == Company.get_invite_user!(invite_user.id)
  #   end

  #   test "delete_invite_user/1 deletes the invite_user" do
  #     invite_user = invite_user_fixture()
  #     assert {:ok, %InviteUser{}} = Company.delete_invite_user(invite_user)
  #     assert_raise Ecto.NoResultsError, fn -> Company.get_invite_user!(invite_user.id) end
  #   end

  #   test "change_invite_user/1 returns a invite_user changeset" do
  #     invite_user = invite_user_fixture()
  #     assert %Ecto.Changeset{} = Company.change_invite_user(invite_user)
  #   end
  # end
end
