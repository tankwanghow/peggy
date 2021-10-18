defmodule PeggyWeb.SetActiveFarmControllerTest do
  use PeggyWeb.ConnCase, async: true

  alias Peggy.CompanyFixtures

  setup :register_and_log_in_user

  describe "POST /set_active_farm" do

    test "set session current_farm", %{conn: conn, user: user} do
      farm = CompanyFixtures.farm_fixture(%{}, user)
      farm_user = Peggy.Company.get_farm_user(farm.id, user.id)
      conn = post(conn, Routes.set_active_farm_path(conn, :create, %{id: farm.id}))
      assert get_session(conn, "current_farm_user") == farm_user
      assert conn.assigns.current_farm_user == farm_user
    end

    test "redirect to /farms/:id/navigation", %{conn: conn, user: user} do
      farm = CompanyFixtures.farm_fixture(%{}, user)
      CompanyFixtures.farm_fixture(%{name: "other farm"}, user)
      conn = post(conn, Routes.set_active_farm_path(conn, :create, %{id: farm.id}))
      assert get_flash(conn, :warning) =~ "#{farm.name} is active now."
      assert redirected_to(conn) == Routes.navigation_index_path(conn, :index, farm.id)
    end
  end

  describe "GET /set_active_farm" do

    test "clear session current_farm", %{conn: conn, user: user} do
      CompanyFixtures.farm_fixture(%{}, user)
      conn = get(conn, Routes.set_active_farm_path(conn, :new))
      assert get_session(conn, "current_farm_user") == nil
      assert get_session(conn, "page_title") == "Please select an active farm."
      assert conn.assigns.current_farm_user == nil
    end

    test "redirect to /farms", %{conn: conn, user: user} do
      CompanyFixtures.farm_fixture(%{}, user)
      conn = get(conn, Routes.set_active_farm_path(conn, :new))
      {:ok, fhtml} = Floki.parse_document(html_response(conn, 200))
      assert Enum.count(Floki.find(fhtml, "div#active-farm")) == 0
      assert Floki.text(Floki.find(fhtml, "#app-name")) == "Peggy"
    end
  end

  describe "GET /update_active_farm" do
    test "set session data", %{conn: conn, user: user} do
      farm = CompanyFixtures.farm_fixture(%{}, user)
      farm_user = Peggy.Company.get_farm_user(farm.id, user.id)
      conn = get(conn, Routes.set_active_farm_path(conn, :update, %{id: farm.id}))
      assert get_flash(conn, :success) =~ "Farm updated successfully"
      assert get_session(conn, "current_farm_user") == farm_user
      assert conn.assigns.current_farm_user == farm_user
    end

    test "redirect to /farms", %{conn: conn, user: user} do
      farm = CompanyFixtures.farm_fixture(%{}, user)
      conn = get(conn, Routes.set_active_farm_path(conn, :update, %{id: farm.id}))
      {:ok, fhtml} = Floki.parse_document(html_response(conn, 200))
      assert Enum.count(Floki.find(fhtml, "div#active-farm")) == 1
      assert Floki.text(Floki.find(fhtml, "#navbar-company-name")) == farm.name
    end
  end

end
