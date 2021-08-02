defmodule PeggyWeb.PageLiveTest do
  use PeggyWeb.ConnCase

  import Phoenix.LiveViewTest

  test "disconnected and connected render", %{conn: conn} do
    {:ok, page_live, disconnected_html} = live(conn, "/")
    assert disconnected_html =~ "Peggy"
    assert render(page_live) =~ "Peggy"
  end

  test "not login page", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")
    assert has_element?(view, "#welcome-title")
    refute html =~ "id=\"navbar-company-name\""
    assert html =~ "id=\"app-name\""
    refute html =~ "href=\"/users/settings\""
    refute html =~ "href=\"/farms\""
    assert html =~ "href=\"/users/log_in\""
  end

  describe "logged in page, no active farm" do
    setup :register_and_log_in_user
    test "show user email", %{conn: conn, user: user} do
      {:ok, view, html} = live(conn, "/")
      assert has_element?(view, "#welcome-title")
      refute html =~ "id=\"navbar-company-name\""
      assert html =~ "id=\"app-name\""
      assert html =~ "href=\"/users/settings\""
      assert html =~ "href=\"/farms\""
      assert html =~ "href=\"/users/log_out\""
    end
  end

  describe "logged in page, with active farm" do
    setup :user_set_active_farm
    test "show farm name and remove farms link", %{conn: conn, farm: farm} do
      {:ok, view, html} = live(conn, "/")
      assert has_element?(view, "#welcome-title")
      assert html =~ "id=\"navbar-company-name\""
      refute html =~ "id=\"app-name\""
      assert html =~ "href=\"/users/settings\""
      refute html =~ "href=\"/farms\""
      assert html =~ "href=\"/users/log_out\""
      assert html =~ farm.name <> "</a>"
    end
  end
end
