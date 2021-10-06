defmodule PeggyWeb.NavigationControllerTest do
  use PeggyWeb.ConnCase, async: true

  setup :register_and_log_in_user

  describe "Nagivation Live has active farm" do
    setup :user_set_active_farm

    test "New Farm From Looks", %{conn: conn, farm: farm} do
      conn = get(conn, Routes.navigation_path(conn, :index, farm.id))
      response = html_response(conn, 200)
      assert response =~ "id=\"navigation-title\""
      assert response =~ "Navigation Page"
      refute response =~ "id=\"home-button\""
    end
  end

  
end
