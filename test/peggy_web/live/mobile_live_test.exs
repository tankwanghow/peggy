defmodule PeggyWeb.MobileLiveTest do
  use PeggyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Peggy.AccountsFixtures
  import Peggy.FarmsFixtures
  import Peggy.LocationsFixtures
  import Peggy.AnimalsFixtures

  describe "/m/:slug/animals cull flag" do
    setup %{conn: conn} do
      owner = user_fixture()
      farm = farm_fixture(owner)
      scope = scope_for(owner, farm)
      house = house_fixture(scope, code: "H1")
      pen = pen_fixture(scope, house, code: "P1", capacity: 50)

      flagged = animal_fixture(scope, ear_tag: "CULLME", stage: "sow", current_pen_id: pen.id)
      {:ok, _} = Peggy.Animals.mark_for_cull(scope, flagged)

      _clean = animal_fixture(scope, ear_tag: "KEEPME", stage: "sow", current_pen_id: pen.id)

      # Pin the UI to mobile so the device auto-router doesn't bounce us
      # to the desktop route (the test conn has no mobile user-agent).
      conn =
        conn
        |> log_in_user(owner)
        |> Plug.Test.put_req_cookie("peggy_view", "mobile")

      %{conn: conn, farm: farm}
    end

    test "shows the cull indicator in the mobile animals list when a sow is flagged",
         %{conn: conn, farm: farm} do
      {:ok, _lv, html} = live(conn, ~p"/m/#{farm.slug}/animals")
      assert html =~ "CULLME"
      assert html =~ "KEEPME"
      assert html =~ "Flagged for culling"
    end
  end

  describe "/m/:slug/animals/:id detail card" do
    setup %{conn: conn} do
      owner = user_fixture()
      farm = farm_fixture(owner)
      scope = scope_for(owner, farm)
      house = house_fixture(scope, code: "H1")
      pen = pen_fixture(scope, house, code: "AA-21", capacity: 50)
      sow = animal_fixture(scope, ear_tag: "5157", stage: "sow", current_pen_id: pen.id)

      conn =
        conn
        |> log_in_user(owner)
        |> Plug.Test.put_req_cookie("peggy_view", "mobile")

      %{conn: conn, farm: farm, sow: sow}
    end

    test "renders identity, details, and actions in one sticky bar",
         %{conn: conn, farm: farm, sow: sow} do
      {:ok, _lv, html} = live(conn, ~p"/m/#{farm.slug}/animals/#{sow.id}")

      # Identity + details share the bar
      assert html =~ "5157"
      assert html =~ "Sow"
      assert html =~ "AA-21"
      assert html =~ "Parity"
      # Actions live in the same bar (back + edit)
      assert html =~ "mobile-animal-detail-back"
      assert html =~ ~s(aria-label="Edit")
      # The bar is sticky
      assert html =~ "sticky top-0"
    end
  end
end
