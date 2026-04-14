defmodule Peggy.FarmsTest do
  use Peggy.DataCase, async: true

  import Peggy.AccountsFixtures
  import Peggy.FarmsFixtures

  alias Peggy.Farms
  alias Peggy.Farms.{Farm, Membership}

  describe "create_farm/2" do
    test "creates a farm and an owner membership in one transaction" do
      user = user_fixture()
      assert {:ok, %Farm{} = farm} = Farms.create_farm(user, valid_farm_attributes())

      membership = Farms.get_membership(user, farm)
      assert %Membership{role: "owner", accepted_at: %DateTime{}} = membership
    end

    test "validates slug format and uniqueness" do
      user = user_fixture()
      attrs = valid_farm_attributes(slug: "Bad Slug!")
      assert {:error, changeset} = Farms.create_farm(user, attrs)
      assert "lowercase letters, digits, and hyphens only" in errors_on(changeset).slug

      farm = farm_fixture(user)
      assert {:error, changeset} = Farms.create_farm(user, valid_farm_attributes(slug: farm.slug))
      assert "has already been taken" in errors_on(changeset).slug
    end
  end

  describe "list_farms_for_user/1" do
    test "returns only farms where the user has an accepted membership" do
      alice = user_fixture()
      bob = user_fixture()
      alice_farm = farm_fixture(alice)
      _bob_farm = farm_fixture(bob)

      assert [%Farm{id: id}] = Farms.list_farms_for_user(alice)
      assert id == alice_farm.id
    end
  end

  describe "default farm" do
    test "set_default_farm swaps the flag and returns via get_default_farm" do
      user = user_fixture()
      f1 = farm_fixture(user, name: "One")
      f2 = farm_fixture(user, name: "Two")

      assert is_nil(Farms.get_default_farm(user))

      :ok = Farms.set_default_farm(user, f1)
      assert Farms.get_default_farm(user).id == f1.id

      :ok = Farms.set_default_farm(user, f2)
      assert Farms.get_default_farm(user).id == f2.id
    end

    test "set_default_farm refuses non-members" do
      alice = user_fixture()
      bob = user_fixture()
      bobs_farm = farm_fixture(bob)

      assert {:error, :not_a_member} = Farms.set_default_farm(alice, bobs_farm)
    end
  end

  describe "seat limit" do
    test "invite rejects when seats are full" do
      owner = user_fixture()
      {:ok, farm} = Farms.create_farm(owner, valid_farm_attributes(seat_limit: 1))

      assert {:error, :seat_limit_reached} =
               Farms.invite(farm, %{"email" => "new@example.com", "role" => "worker"}, owner)
    end

    test "pending invitations count against the cap" do
      owner = user_fixture()
      {:ok, farm} = Farms.create_farm(owner, valid_farm_attributes(seat_limit: 2))

      {:ok, _} =
        Farms.invite(farm, %{"email" => "a@example.com", "role" => "worker"}, owner)

      assert {:error, :seat_limit_reached} =
               Farms.invite(farm, %{"email" => "b@example.com", "role" => "worker"}, owner)
    end

    test "accept rejects when cap was filled after the invitation" do
      owner = user_fixture()
      invitee = user_fixture(email: "late#{System.unique_integer([:positive])}@example.com")
      {:ok, farm} = Farms.create_farm(owner, valid_farm_attributes(seat_limit: 2))

      {:ok, invitation} =
        Farms.invite(farm, %{"email" => invitee.email, "role" => "worker"}, owner)

      # Simulate cap shrinking after invite
      {:ok, _} = Farms.update_farm(farm, %{seat_limit: 1})
      invitation = Peggy.Repo.preload(invitation, :farm)

      assert {:error, :seat_limit_reached} = Farms.accept_invitation(invitation, invitee)
    end
  end

  describe "invitations" do
    test "invite + accept creates a membership for the invitee" do
      owner = user_fixture()
      farm = farm_fixture(owner)
      invitee = user_fixture(email: "invitee#{System.unique_integer([:positive])}@example.com")

      {:ok, invitation} =
        Farms.invite(farm, %{"email" => invitee.email, "role" => "worker"}, owner)

      encoded = Peggy.Farms.Invitation.encode_token(invitation.token)
      {:ok, fetched} = Farms.get_invitation_by_token(encoded)
      assert fetched.id == invitation.id

      {:ok, %Membership{role: "worker"}} = Farms.accept_invitation(fetched, invitee)

      assert [%Farm{id: farm_id}] = Farms.list_farms_for_user(invitee)
      assert farm_id == farm.id

      # Cannot accept twice
      assert :error = Farms.get_invitation_by_token(encoded)
    end

    test "expired invitation is rejected" do
      owner = user_fixture()
      farm = farm_fixture(owner)

      {:ok, invitation} =
        Farms.invite(farm, %{"email" => "x@example.com", "role" => "worker"}, owner)

      past = DateTime.add(DateTime.utc_now(:second), -1, :second)

      Peggy.Repo.update_all(
        from(i in Peggy.Farms.Invitation, where: i.id == ^invitation.id),
        set: [expires_at: past]
      )

      encoded = Peggy.Farms.Invitation.encode_token(invitation.token)
      assert :error = Farms.get_invitation_by_token(encoded)
    end
  end
end
