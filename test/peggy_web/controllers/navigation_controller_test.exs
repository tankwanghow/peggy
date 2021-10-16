defmodule PeggyWeb.NavigationControllerTest do
  use PeggyWeb.ConnCase, async: true

  setup :register_and_log_in_user

  describe "Nagivation Live has active farm" do
    test "Look and Feels", %{conn: conn, user: user} do
      farm = Peggy.CompanyFixtures.farm_fixture(%{}, user)
      conn = get(conn, Routes.navigation_path(conn, :index, farm.id))
      response = html_response(conn, 200)
      assert response =~ "id=\"navigation-title\""
      assert response =~ "Navigation Page"
      refute response =~ "id=\"home-button\""
    end

    test "Admin Look and Feels", %{conn: conn, user: user} do
      farm = Peggy.CompanyFixtures.farm_fixture(%{}, user)
      conn = get(conn, Routes.navigation_path(conn, :index, farm.id))
      response = html_response(conn, 200)
      assert response =~ "Invite User"
    end

    test "Non-Admin Look and Feels", %{conn: conn, user: user} do
      farm = Peggy.CompanyFixtures.farm_fixture(%{}, user)
      otheruser = Peggy.UserAccountsFixtures.user_fixture()
      Peggy.Company.allow_user_access_farm(otheruser.id, "guest", Peggy.Company.get_farm_user(farm.id, user.id))
      conn = get(log_in_user(conn, otheruser), Routes.navigation_path(conn, :index, farm.id))
      response = html_response(conn, 200)
      refute response =~ "Invite User"
    end
  end
end
