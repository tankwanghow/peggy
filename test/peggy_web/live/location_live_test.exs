defmodule PeggyWeb.LocationLiveTest do
  use PeggyWeb.ConnCase

  import Phoenix.LiveViewTest
  alias Peggy.FarmFixtures
  alias Peggy.CompanyFixtures
  alias Peggy.UserAccountsFixtures
  alias Peggy.Company
  alias Peggy.Farm

  setup :register_and_log_in_user

  describe "Location Index View" do
    setup :user_set_active_farm

    setup %{conn: conn, user: user, farm: farm} do
      f1 = CompanyFixtures.farm_fixture(%{}, user)

      for _n <- 1..30 do
        FarmFixtures.location_fixture(get_session(conn, :current_farm_user))
      end

      locations = Farm.list_locations(get_session(conn, :current_farm_user))

      FarmFixtures.location_fixture(Company.get_farm_user(f1.id, user.id))
      %{conn: conn, user: user, farm: farm, farm1: f1, locations: locations}
    end

    test "Authorization", %{conn: conn, farm: farm, locations: locations} do
      user1 = UserAccountsFixtures.user_fixture()
      Company.allow_user_access_farm(user1.id, "guest", get_session(conn, :current_farm_user))
      conn = log_in_user(conn, user1)
      conn = post(conn, Routes.set_active_farm_path(conn, :create, %{id: farm.id}))
      {:ok, view, _html} = live(conn, Routes.location_index_path(conn, :index, farm.id))

      l = locations |> Enum.at(4)

      # test delete
      view
      |> element("a#location-delete-#{l.id}[phx-click=\"delete_location\"]")
      |> render_click

      assert view |> has_element?(".notification.is-danger", "Not Authorise")

      # test insert
      view
      |> form("#location-form", %{location: %{code: "a-location-code-new", capacity: 840}})
      |> render_submit

      assert view |> has_element?(".notification.is-danger", "Not Authorise")

      view |> element(".column input[value=\"#{l.code}\"]") |> render_click

      view
      |> form("#location-form", %{location: %{code: "a-location-code-update", capacity: 840}})
      |> render_submit

      assert view |> has_element?(".notification.is-danger", "Not Authorise")
    end

    test "Search Location", %{conn: conn, farm: farm, locations: locations} do
      {:ok, view, _html} = live(conn, Routes.location_index_path(conn, :index, farm.id))
      view |> form("#location-search-form", %{search: %{terms: ""}}) |> render_change

      TestHelper.assert_live_search(
        view,
        locations,
        :code,
        "",
        fn x -> ".column input[value=\"#{x}\"]" end,
        10
      )

      r = :rand.uniform(99)
      view |> form("#location-search-form", %{search: %{terms: "#{r}"}}) |> render_change

      TestHelper.assert_live_search(
        view,
        locations,
        :code,
        r,
        fn x -> ".column input[value=\"#{x}\"]" end,
        10
      )

      view |> form("#location-search-form", %{search: %{terms: "zzz"}}) |> render_change
      assert view |> has_element?("#footer .columns .column", "No More...")
    end

    test "Location Select and ClearNew Record", %{conn: conn, farm: farm, locations: locations} do
      {:ok, view, _html} = live(conn, Routes.location_index_path(conn, :index, farm.id))
      l = locations |> Enum.at(3)
      view |> element(".column input[value=\"#{l.code}\"]") |> render_click
      assert view |> has_element?("form#location-form input[value=\"#{l.code}\"]")
      assert view |> has_element?("form#location-form input[value=\"#{l.capacity}\"]")
      assert view |> has_element?("form#location-form select option[value=\"#{l.status}\"]")
      assert view |> has_element?("form#location-form input[value=\"#{l.note}\"]")
      assert view |> has_element?("form#location-form button[type=\"submit\"]")
      refute view |> has_element?("form#location-form button[type=\"submit\"]", "Insert")
      assert view |> has_element?("form#location-form a[phx-click=\"clear_new\"]")

      view |> element("form#location-form a[phx-click=\"clear_new\"]") |> render_click
      assert view |> has_element?("form#location-form input[value=\"\"]")
      assert view |> has_element?("form#location-form input[value=\"\"]")
      assert view |> has_element?("form#location-form select option[value=\"active\"]")
      assert view |> has_element?("form#location-form input[value=\"\"]")
      assert view |> has_element?("form#location-form button[type=\"submit\"]", "Insert")
      refute view |> has_element?("form#location-form a[phx-click=\"clear_new\"]")
    end

    test "Location Insert Record", %{conn: conn, farm: farm} do
      {:ok, view, _html} = live(conn, Routes.location_index_path(conn, :index, farm.id))

      # Invalid Attrs
      view |> form("#location-form", %{location: %{code: "", capacity: -1}}) |> render_change
      assert has_element?(view, "#code-invalid-feedback")
      assert has_element?(view, "#capacity-invalid-feedback")

      view |> form("#location-form", %{location: %{code: "", capacity: -1}}) |> render_submit

      assert has_element?(
               view,
               ".notification.is-danger"
             )

      # Valid Attrs

      view
      |> form("#location-form", %{location: %{code: "a-location-code-new", capacity: 999}})
      |> render_change

      refute has_element?(view, "#code-invalid-feedback")
      refute has_element?(view, "#capacity-invalid-feedback")

      view
      |> form("#location-form", %{location: %{code: "a-location-code-new", capacity: 840}})
      |> render_submit

      assert has_element?(
               view,
               ".column input[value=\"a-location-code-new\"]"
             )

      assert has_element?(
               view,
               ".notification.is-success"
             )

      assert Farm.list_locations(get_session(conn, :current_farm_user)) |> Enum.count() == 31
    end

    test "Location Update Record", %{conn: conn, farm: farm, locations: locations} do
      {:ok, view, _html} = live(conn, Routes.location_index_path(conn, :index, farm.id))
      l = locations |> Enum.at(3)
      view |> element(".column input[value=\"#{l.code}\"]") |> render_click

      # Invalid Attrs
      view |> form("#location-form", %{location: %{code: "", capacity: -1}}) |> render_change
      assert has_element?(view, "#code-invalid-feedback")
      assert has_element?(view, "#capacity-invalid-feedback")

      view |> form("#location-form", %{location: %{code: "", capacity: -1}}) |> render_submit

      assert has_element?(
               view,
               ".notification.is-danger"
             )

      # Valid Attrs

      view
      |> form("#location-form", %{location: %{code: "a-location-code-updated", capacity: 840}})
      |> render_change

      refute has_element?(view, "#code-invalid-feedback")
      refute has_element?(view, "#capacity-invalid-feedback")

      view
      |> form("#location-form", %{location: %{code: "a-location-code-updated", capacity: 840}})
      |> render_submit

      assert has_element?(
               view,
               ".column input#location-code-#{l.id}[value=\"a-location-code-updated\"]"
             )

      assert has_element?(
               view,
               ".notification.is-success"
             )
    end

    test "Location List layout", %{conn: conn, farm: farm} do
      {:ok, view, html} = live(conn, Routes.location_index_path(conn, :index, farm.id))
      assert has_element?(view, ".title")
      assert html =~ "Location List"
      assert has_element?(view, "#location-form")
      assert has_element?(view, "#location-search-form")
      assert has_element?(view, "#location-list-0")
      assert has_element?(view, "form#location-form button[type=\"submit\"]", "Insert")
    end

    test "Location List Click Delete Record", %{conn: conn, farm: farm, locations: locations} do
      {:ok, view, _html} = live(conn, Routes.location_index_path(conn, :index, farm.id))
      l = locations |> Enum.at(4)

      {:ok, fhtml} =
        view
        |> element("a#location-delete-#{l.id}[phx-click=\"delete_location\"]")
        |> render_click
        |> Floki.parse_document()

      assert fhtml |> Floki.find(".columns .column input[value=\"#{l.code}\"]") == []
      assert fhtml |> Floki.find("a[phx-click=\"delete_location\"]") |> Enum.count() == 10
      assert Farm.list_locations(get_session(conn, :current_farm_user)) |> Enum.count() == 29
      l = locations |> Enum.at(2)

      {:ok, fhtml} =
        view
        |> element("a#location-delete-#{l.id}[phx-click=\"delete_location\"]")
        |> render_click
        |> Floki.parse_document()

      assert fhtml |> Floki.find(".columns .column input[value=\"#{l.code}\"]") == []
      assert fhtml |> Floki.find("a[phx-click=\"delete_location\"]") |> Enum.count() == 10
      assert Farm.list_locations(get_session(conn, :current_farm_user)) |> Enum.count() == 28
    end

    test "Location List Table Infinite Scroll", %{conn: conn, farm: farm} do
      {:ok, view, html} = live(conn, Routes.location_index_path(conn, :index, farm.id))

      {:ok, fhtml} = html |> Floki.parse_document()
      assert fhtml |> Floki.find("a[phx-click=\"delete_location\"]") |> Enum.count() == 10

      # There is a bug that liveviewtest cause a missing location
      # did not know why
      {:ok, fhtml} = render_hook(view, "load-more") |> Floki.parse_document()
      assert fhtml |> Floki.find("a[phx-click=\"delete_location\"]") |> Enum.count() == 20

      {:ok, fhtml} = render_hook(view, "load-more") |> Floki.parse_document()
      assert fhtml |> Floki.find("a[phx-click=\"delete_location\"]") |> Enum.count() == 30
    end
  end
end
