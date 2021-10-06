defmodule PeggyWeb.WelcomeControllerTest do
  use PeggyWeb.ConnCase, async: true

  test "not login page", %{conn: conn} do
    conn = get(conn, Routes.welcome_path(conn, :index))
    response = html_response(conn, 200)
    assert response =~ "id=\"welcome-title\""
    refute response =~ "id=\"navbar-company-name\""
    assert response =~ "id=\"app-name\""
    refute response =~ "href=\"/users/settings\""
    refute response =~ "href=\"/farms\""
    assert response =~ "href=\"/users/log_in\""
    refute response =~ "id=\"home-button\""
  end

  describe "logged in page, no active farm" do
    setup :register_and_log_in_user
    test "show user email", %{conn: conn} do
      conn = get(conn, Routes.welcome_path(conn, :index))
      response = html_response(conn, 200)
      assert response =~ "id=\"welcome-title\""
      refute response =~ "id=\"navbar-company-name\""
      assert response =~ "id=\"app-name\""
      assert response =~ "href=\"/users/settings\""
      assert response =~ "href=\"/farms\""
      assert response =~ "href=\"/users/log_out\""
      refute response =~ "id=\"home-button\""
    end
  end

  describe "logged in page, with active farm" do
    setup :user_set_active_farm
    test "show farm name and remove farms link", %{conn: conn, farm: farm} do
      conn = get(conn, Routes.welcome_path(conn, :index))
      response = html_response(conn, 200)
      assert response =~ "id=\"welcome-title\""
      assert response =~ "id=\"navbar-company-name\""
      refute response =~ "id=\"app-name\""
      assert response =~ "href=\"/users/settings\""
      refute response =~ "href=\"/farms\""
      assert response =~ "href=\"/users/log_out\""
      assert response =~ farm.name <> "</a>"
      assert response =~ "id=\"home-button\""
    end
  end
end
