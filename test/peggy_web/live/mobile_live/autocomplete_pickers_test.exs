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

  alias Peggy.Animals
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
end
