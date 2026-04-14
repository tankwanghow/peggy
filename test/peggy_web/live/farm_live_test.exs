defmodule PeggyWeb.FarmLiveTest do
  use PeggyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Peggy.AccountsFixtures
  import Peggy.FarmsFixtures

  describe "/farms" do
    test "lists only the current user's farms when they have more than one", %{conn: conn} do
      alice = user_fixture()
      bob = user_fixture()
      _a1 = farm_fixture(alice, name: "Alice Acres")
      _a2 = farm_fixture(alice, name: "Second Acres")
      _bob_farm = farm_fixture(bob, name: "Bob Barns")

      {:ok, _lv, html} = conn |> log_in_user(alice) |> live(~p"/farms")
      assert html =~ "Alice Acres"
      assert html =~ "Second Acres"
      refute html =~ "Bob Barns"
    end

    test "shows the picker even when the user has a single farm", %{conn: conn} do
      alice = user_fixture()
      farm = farm_fixture(alice, name: "Alice Acres")

      {:ok, _lv, html} = conn |> log_in_user(alice) |> live(~p"/farms")
      assert html =~ "Alice Acres"
      assert html =~ farm.slug
      assert html =~ "Create a farm"
    end
  end

  describe "/farms/:slug isolation" do
    test "non-member gets redirected to /farms", %{conn: conn} do
      alice = user_fixture()
      bob = user_fixture()
      alice_farm = farm_fixture(alice)

      assert {:error, {:redirect, %{to: "/farms"}}} =
               conn |> log_in_user(bob) |> live(~p"/farms/#{alice_farm.slug}")
    end

    test "member reaches the dashboard", %{conn: conn} do
      alice = user_fixture()
      farm = farm_fixture(alice, name: "Alice Acres")

      {:ok, _lv, html} = conn |> log_in_user(alice) |> live(~p"/farms/#{farm.slug}")
      assert html =~ "Alice Acres"
      assert html =~ "owner"
    end
  end

  describe "/farms/:slug/settings" do
    test "worker cannot see settings (redirected)", %{conn: conn} do
      owner = user_fixture()
      worker = user_fixture()
      farm = farm_fixture(owner)

      {:ok, invitation} =
        Peggy.Farms.invite(farm, %{"email" => worker.email, "role" => "worker"}, owner)

      {:ok, _} = Peggy.Farms.accept_invitation(invitation, worker)

      assert {:error, {:redirect, %{to: "/farms"}}} =
               conn |> log_in_user(worker) |> live(~p"/farms/#{farm.slug}/settings")
    end

    test "owner can edit farm profile", %{conn: conn} do
      owner = user_fixture()
      farm = farm_fixture(owner, name: "Original", unit_system: "metric")

      {:ok, lv, _html} = conn |> log_in_user(owner) |> live(~p"/farms/#{farm.slug}/settings")

      lv
      |> form("#farm-form", farm: %{name: "Renamed", unit_system: "imperial"})
      |> render_submit()

      reloaded = Peggy.Farms.get_farm_by_slug!(farm.slug)
      assert reloaded.name == "Renamed"
      assert reloaded.unit_system == "imperial"
    end

    test "owner can invite a member", %{conn: conn} do
      owner = user_fixture()
      farm = farm_fixture(owner)

      {:ok, lv, _html} = conn |> log_in_user(owner) |> live(~p"/farms/#{farm.slug}/settings")

      lv
      |> form("#invite-form", invitation: %{email: "new@example.com", role: "worker"})
      |> render_submit()

      assert has_element?(lv, "#invitations", "new@example.com")
    end
  end
end
