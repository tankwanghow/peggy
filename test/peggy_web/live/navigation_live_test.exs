defmodule PeggyWeb.NavigationLiveTest do
  use PeggyWeb.ConnCase

  import Phoenix.LiveViewTest

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
end
