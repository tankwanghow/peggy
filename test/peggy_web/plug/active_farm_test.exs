defmodule PeggyWeb.ActiveFarmTest do
  use PeggyWeb.ConnCase, async: true

  setup :register_and_log_in_user

  setup %{conn: conn, user: user} do
    can_access_farm = Peggy.CompanyFixtures.farm_fixture(%{}, user)
    cannot_access_farm = Peggy.CompanyFixtures.farm_fixture(%{}, Peggy.UserAccountsFixtures.user_fixture())

    %{conn: conn, user: user, can_access_farm: can_access_farm, cannot_access_farm: cannot_access_farm}
  end

  test "should not set active farm, and show error", %{conn: conn, cannot_access_farm: farm} do
    conn = get(conn, "/farms/#{farm.id}/navigation")
    assert get_session(conn, :current_farm) == nil
    assert get_flash(conn, :error) == "Not authorise to access farm in the URL."
    assert redirected_to(conn) == "/"
  end

  test "should set active farm, and warn user", %{conn: conn, can_access_farm: farm} do
    conn = get(conn, "/farms/#{farm.id}/navigation")
    response = html_response(conn, 200)
    assert response =~ farm.name
    assert get_session(conn, :current_farm) == farm
    assert get_flash(conn, :warning) ==
             "#{farm.name} " <> "is active now."
    assert response =~ "Navigation Page"
  end
end
