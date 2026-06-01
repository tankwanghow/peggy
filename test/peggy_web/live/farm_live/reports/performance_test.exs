defmodule PeggyWeb.FarmLive.Reports.PerformanceTest do
  use PeggyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Peggy.AccountsFixtures
  import Peggy.FarmsFixtures
  import Peggy.LocationsFixtures
  import Peggy.AnimalsFixtures
  import Peggy.BreedingFixtures

  setup %{conn: conn} do
    owner = user_fixture()
    farm = farm_fixture(owner)
    scope = scope_for(owner, farm)
    house = house_fixture(scope, code: "H1")
    pen = pen_fixture(scope, house, code: "P1", capacity: 50)
    sow = animal_fixture(scope, ear_tag: "S1", stage: "sow", current_pen_id: pen.id)

    farrowing_fixture(scope, sow,
      farrowed_at: Date.add(Date.utc_today(), -10),
      born_alive: 11,
      service_type: "ai"
    )

    %{conn: log_in_user(conn, owner), farm: farm}
  end

  test "renders the three section titles and a value", %{conn: conn, farm: farm} do
    {:ok, _lv, html} = live(conn, ~p"/farms/#{farm.slug}/reports/performance")
    assert html =~ "Service performance"
    assert html =~ "Farrowing performance"
    assert html =~ "Weaning performance"
    assert html =~ "Total services"
  end

  test "print view renders the matrix and an auto-print hook", %{conn: conn, farm: farm} do
    {:ok, _lv, html} = live(conn, ~p"/farms/#{farm.slug}/reports/performance/print")
    assert html =~ "Performance Analysis"
    assert html =~ "Service performance"
    assert html =~ "AutoPrint"
  end
end
