defmodule PeggyWeb.SetActiveFarmControllerTest do
  use PeggyWeb.ConnCase, async: true

  alias Peggy.CompanyFixtures

  setup :register_and_log_in_user

  describe "POST /set_active_farm" do

    test "set session current_farm", %{conn: conn, user: user} do
      farm = CompanyFixtures.farm_fixture(%{}, user)
      conn = post(conn, Routes.set_active_farm_path(conn, :create, %{id: farm.id}))
      assert get_session(conn, "current_farm") == farm
      assert conn.assigns.current_farm == farm
    end

    test "redirect to /farms", %{conn: conn, user: user} do
      farm = CompanyFixtures.farm_fixture(%{}, user)
      CompanyFixtures.farm_fixture(%{name: "other farm"}, user)
      conn = post(conn, Routes.set_active_farm_path(conn, :create, %{id: farm.id}))
      assert get_flash(conn, :warning) =~ "#{farm.name} is active now."
      {:ok, fhtml} = Floki.parse_document(html_response(conn, 200))
      assert Enum.count(Floki.find(fhtml, "div#active-farm")) == 1
      assert Floki.text(Floki.find(fhtml, "#navbar-company-name")) == farm.name
    end
  end

  describe "GET /set_active_farm" do

    test "clear session current_farm", %{conn: conn, user: user} do
      CompanyFixtures.farm_fixture(%{}, user)
      conn = get(conn, Routes.set_active_farm_path(conn, :new))
      assert get_session(conn, "current_farm") == nil
      assert get_session(conn, "page_title") == "Please select an active farm."
      assert conn.assigns.current_farm == nil
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
      conn = get(conn, Routes.set_active_farm_path(conn, :update, %{id: farm.id}))
      assert get_flash(conn, :success) =~ "Farm updated successfully"
      assert get_session(conn, "current_farm") == farm
      assert conn.assigns.current_farm == farm
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
