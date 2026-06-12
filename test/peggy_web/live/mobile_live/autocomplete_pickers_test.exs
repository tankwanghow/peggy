defmodule PeggyWeb.MobileLive.AutocompletePickersTest do
  @moduledoc """
  Drives the mobile movement form's To-pen autocomplete picker.

  The client-side `<.autocomplete>` hook writes the chosen pen id into a
  hidden input named `to_pen_id` and dispatches an input event so the
  enclosing form's `phx-change` fires. That hook is JS-only, so the
  correct test seam is to send the id param directly via
  `render_change/3` + `render_submit/3`, simulating what the hook writes.
  """
  use PeggyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Peggy.AccountsFixtures
  import Peggy.FarmsFixtures
  import Peggy.LocationsFixtures
  import Peggy.AnimalsFixtures
  import Peggy.BreedingFixtures

  alias Peggy.Animals
  alias Peggy.Breeding
  alias Peggy.FarmClock

  describe "serviceable move sheet — To pen autocomplete" do
    setup %{conn: conn} do
      owner = user_fixture()
      farm = farm_fixture(owner)
      scope = scope_for(owner, farm)

      house = house_fixture(scope, code: "EB")
      from_pen = pen_fixture(scope, house, code: "11", capacity: 50)
      to_pen = pen_fixture(scope, house, code: "12", capacity: 50)

      sow =
        animal_fixture(scope,
          ear_tag: "5157",
          stage: "sow",
          status: "open",
          current_pen_id: from_pen.id
        )

      conn =
        conn
        |> log_in_user(owner)
        |> Plug.Test.put_req_cookie("peggy_view", "mobile")

      %{conn: conn, farm: farm, scope: scope, sow: sow, to_pen: to_pen}
    end

    test "selecting a To pen records the movement into that pen", ctx do
      %{conn: conn, farm: farm, scope: scope, sow: sow, to_pen: to_pen} = ctx

      {:ok, lv, _html} = live(conn, ~p"/m/#{farm.slug}/breeding/serviceable")

      # Open the action sheet for the sow, then switch to the move form.
      lv |> element("#serviceable-#{sow.id}") |> render_click()
      render_click(lv, "action_move", %{})

      today = FarmClock.today(scope) |> to_string()

      # Hidden input carries the chosen pen id, mirroring the JS hook.
      change_params = %{
        "movement" => %{"reason" => "pen_transfer", "moved_at" => today},
        "from_pen_id" => Integer.to_string(sow.current_pen_id),
        "to_pen_id" => Integer.to_string(to_pen.id)
      }

      render_change(lv, "move_validate", change_params)
      render_submit(lv, "move_save", change_params)

      reloaded = Animals.get_animal!(scope, sow.id)
      assert reloaded.current_pen_id == to_pen.id
    end
  end

  describe "register sheet — pen autocomplete" do
    setup %{conn: conn} do
      owner = user_fixture()
      farm = farm_fixture(owner)
      scope = scope_for(owner, farm)

      house = house_fixture(scope, code: "EB")
      pen = pen_fixture(scope, house, code: "12", capacity: 50)

      conn =
        conn
        |> log_in_user(owner)
        |> Plug.Test.put_req_cookie("peggy_view", "mobile")

      %{conn: conn, farm: farm, scope: scope, pen: pen}
    end

    test "registering with a chosen pen sets current_pen_id", ctx do
      %{conn: conn, farm: farm, scope: scope, pen: pen} = ctx

      {:ok, lv, _html} = live(conn, ~p"/m/#{farm.slug}/animals")

      lv |> element("button[phx-click=register_open]") |> render_click()

      # Hidden input carries the chosen pen id, mirroring the JS hook.
      save_params = %{
        "animal" => %{
          "tracking_type" => "individual",
          "ear_tag" => "NEW-1",
          "stage" => "sow"
        },
        "pen_id" => Integer.to_string(pen.id)
      }

      # register_save push_navigates to the new animal's detail page.
      assert {:error, {:live_redirect, %{to: to}}} =
               render_submit(lv, "register_save", save_params)

      assert to =~ ~r{/m/#{farm.slug}/animals/\d+\z}

      animal =
        scope
        |> Animals.list_animals(status: "present")
        |> Enum.find(&(&1.ear_tag == "NEW-1"))

      assert animal
      assert animal.current_pen_id == pen.id
    end
  end

  describe "animals list — search clear button and result count" do
    setup %{conn: conn} do
      owner = user_fixture()
      farm = farm_fixture(owner)
      scope = scope_for(owner, farm)

      house = house_fixture(scope, code: "EB")
      pen = pen_fixture(scope, house, code: "12", capacity: 50)

      animal_fixture(scope, ear_tag: "FINDME", stage: "sow", current_pen_id: pen.id)
      animal_fixture(scope, ear_tag: "OTHER", stage: "sow", current_pen_id: pen.id)

      conn =
        conn
        |> log_in_user(owner)
        |> Plug.Test.put_req_cookie("peggy_view", "mobile")

      %{conn: conn, farm: farm, scope: scope}
    end

    test "searching filters the list and clear button resets it", ctx do
      %{conn: conn, farm: farm} = ctx

      {:ok, lv, html} = live(conn, ~p"/m/#{farm.slug}/animals")

      assert html =~ "FINDME"
      assert html =~ "OTHER"

      # Search narrows the card stream to the matching ear tag.
      render_change(lv, "search", %{"q" => "FINDME"})
      filtered = render(lv)
      assert filtered =~ "FINDME"
      refute filtered =~ "OTHER"

      # Clear button resets the search → all animals visible again.
      lv |> element("button[phx-click='clear_search']") |> render_click()
      cleared = render(lv)
      assert cleared =~ "FINDME"
      assert cleared =~ "OTHER"
    end
  end

  describe "gestating re-service sheet — boar autocomplete" do
    setup %{conn: conn} do
      owner = user_fixture()
      farm = farm_fixture(owner)
      scope = scope_for(owner, farm)

      house = house_fixture(scope, code: "GB")
      pen = pen_fixture(scope, house, code: "21", capacity: 50)

      sow =
        animal_fixture(scope,
          ear_tag: "SOW-21",
          stage: "sow",
          status: "open",
          current_pen_id: pen.id
        )

      boar =
        animal_fixture(scope,
          ear_tag: "BOAR-9",
          stage: "boar",
          status: "active",
          current_pen_id: pen.id
        )

      # Open (un-resulted) service → puts the sow on the gestating tab.
      service =
        service_fixture(scope, sow, %{service_type: "ai", served_at: ~D[2026-05-01]})

      conn =
        conn
        |> log_in_user(owner)
        |> Plug.Test.put_req_cookie("peggy_view", "mobile")

      %{conn: conn, farm: farm, scope: scope, sow: sow, boar: boar, service: service}
    end

    test "picking a boar records the re-service with that boar_id", ctx do
      %{conn: conn, farm: farm, scope: scope, sow: sow, boar: boar, service: service} = ctx

      {:ok, lv, _html} = live(conn, ~p"/m/#{farm.slug}/breeding/gestating")

      # Open the action sheet for the sow's service, then the re-service form.
      lv |> element("#service-#{service.id}") |> render_click()
      render_click(lv, "action_re_service", %{})

      today = FarmClock.today(scope) |> to_string()

      # Hidden input carries the chosen boar id, mirroring the JS hook.
      save_params = %{
        "service_type" => "natural",
        "boar_id" => Integer.to_string(boar.id),
        "served_at" => today,
        "sow_tag" => sow.ear_tag
      }

      render_submit(lv, "service_save", save_params)

      services = Breeding.list_services_for_animal(scope, boar.id)
      assert Enum.any?(services, &(&1.boar_id == boar.id))
    end
  end

  describe "lactating wean sheet — sow destination pen" do
    setup %{conn: conn} do
      owner = user_fixture()
      farm = farm_fixture(owner)
      scope = scope_for(owner, farm)

      house = house_fixture(scope, code: "16B")
      lactating_pen = pen_fixture(scope, house, code: "101", capacity: 20)
      dry_pen = pen_fixture(scope, house, code: "102", capacity: 40)
      boar = animal_fixture(scope, ear_tag: "BOAR-W", stage: "boar")

      sow =
        animal_fixture(scope,
          ear_tag: "5157",
          stage: "sow",
          current_pen_id: lactating_pen.id
        )

      farrowing =
        farrowing_fixture(scope, sow,
          boar_id: boar.id,
          born_alive: 11,
          pen_id: lactating_pen.id
        )

      conn =
        conn
        |> log_in_user(owner)
        |> Plug.Test.put_req_cookie("peggy_view", "mobile")

      %{
        conn: conn,
        farm: farm,
        scope: scope,
        sow: sow,
        farrowing: farrowing,
        dry_pen: dry_pen
      }
    end

    test "destination pen picker uses hidden id input (not freetext)", ctx do
      %{conn: conn, farm: farm, farrowing: farrowing} = ctx

      {:ok, lv, _html} = live(conn, ~p"/m/#{farm.slug}/breeding/lactating")

      render_click(lv, "open_actions", %{"farrowing-id" => Integer.to_string(farrowing.id)})
      html = render_click(lv, "action_wean", %{})

      # Hidden input carries pen id; visible input is label-only (no name).
      assert html =~ ~s(id="mobile-wean-dest-pen-)
      assert html =~ ~s(name="weaning[destination_pen_id]")
      assert html =~ ~s(type="hidden")
      refute html =~ ~s(data-ac-freetext="true")
    end

    test "weaning with destination pen moves the sow", ctx do
      %{conn: conn, farm: farm, scope: scope, sow: sow, farrowing: farrowing, dry_pen: dry_pen} =
        ctx

      {:ok, lv, _html} = live(conn, ~p"/m/#{farm.slug}/breeding/lactating")

      render_click(lv, "open_actions", %{"farrowing-id" => Integer.to_string(farrowing.id)})
      render_click(lv, "action_wean", %{})

      today = FarmClock.today(scope) |> Date.to_iso8601()

      render_submit(lv, "save_wean", %{
        "weaning" => %{
          "weaned_at" => today,
          "weaned_count" => "11",
          "batch_tag" => "W#{String.replace(today, "-", "")}",
          "destination_pen_id" => Integer.to_string(dry_pen.id)
        }
      })

      reloaded = Animals.get_animal!(scope, sow.id)
      assert reloaded.current_pen_id == dry_pen.id
      refute Breeding.latest_open_farrowing_for_sow(scope, sow.id)
    end
  end
end
