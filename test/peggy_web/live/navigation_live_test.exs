defmodule PeggyWeb.NavigationLiveTest do
  use PeggyWeb.ConnCase

  import Phoenix.LiveViewTest
  alias Peggy.Company

  setup :register_and_log_in_user

  describe "Nagivation Live has active farm" do
    setup :user_set_active_farm

    test "New Farm From Looks", %{conn: conn, farm: farm} do
      {:ok, view, html} = live(conn, Routes.navigation_index_path(conn, :index, farm.id))
      assert has_element?(view, "#navigation-title")
      assert html =~ "Navigation Page"
      refute has_element?(view, "#home-button")
    end
  end

  describe "force logout" do
    setup %{conn: conn, user: user} do
      {:ok, user1} =
        Peggy.UserAccountsFixtures.user_fixture()
        |> Peggy.UserAccounts.User.confirm_changeset()
        |> Peggy.Repo.update()

      {:ok, user2} =
        Peggy.UserAccountsFixtures.user_fixture()
        |> Peggy.UserAccounts.User.confirm_changeset()
        |> Peggy.Repo.update()

      farm = Peggy.CompanyFixtures.farm_fixture(%{}, user)

      Company.allow_user_access_farm(user1.id, "guest", Company.get_farm_user(farm.id, user.id))
      Company.allow_user_access_farm(user2.id, "guest", Company.get_farm_user(farm.id, user.id))

      %{conn: conn, user: user, farm: farm, user1: user1, user2: user2}
    end

    test "correct user", %{conn: conn, user1: user1, farm: farm} do
      conn = log_in_user(conn, user1)
      {:ok, view, _html} = live_isolated(conn, PeggyWeb.UserRoleLive, session: %{"current_farm_user" => Company.get_farm_user(farm.id, user1.id)})

      send(view.pid, {:log_out_user, %{ farm_id: farm.id, user_id: user1.id }})

      assert_redirect(view, "/users/force_logout")
    end

    test "incorrect user", %{conn: conn, user1: user1, user: user, farm: farm} do
      conn = log_in_user(conn, user1)
      {:ok, view, _html} = live_isolated(conn, PeggyWeb.UserRoleLive, session: %{"current_farm_user" => Company.get_farm_user(farm.id, user1.id)})

      send(view.pid, {:log_out_user, %{ farm_id: farm.id, user_id: user.id }})

      refute_redirected(view, "/users/force_logout")
    end
  end
end
