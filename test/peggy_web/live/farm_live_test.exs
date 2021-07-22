defmodule PeggyWeb.FarmLiveTest do
  use PeggyWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Peggy.Company

  setup :register_and_log_in_user

  @valid_attrs_1 %{
    address1: "some address1",
    address2: "some address2",
    city: "some city",
    country: "some country",
    name: "some name",
    state: "some state",
    weight_unit: "some weight_unit",
    zipcode: "some zipcode"
  }
  @valid_attrs_2 %{
    address1: "some updated address1",
    address2: "some updated address2",
    city: "some updated city",
    country: "some updated country",
    name: "some updated name",
    state: "some updated state",
    weight_unit: "some updated weight_unit",
    zipcode: "some updated zipcode"
  }
  @invalid_attrs %{
    address1: nil,
    address2: nil,
    city: nil,
    country: nil,
    name: nil,
    state: nil,
    weight_unit: nil,
    zipcode: nil
  }

  describe "FarmLive" do
    test "New Farm From Looks", %{conn: conn} do
      {:ok, view, html} = live(conn, Routes.farm_form_path(conn, :new))
      assert html =~ "Please Create a Farm.</p>"
      assert has_element?(view, "#farm-form_name")
      assert has_element?(view, "#farm-form_weight_unit")
      assert has_element?(view, "#farm-form_address1")
      assert has_element?(view, "#farm-form_address2")
      assert has_element?(view, "#farm-form_city")
      assert has_element?(view, "#farm-form_zipcode")
      assert has_element?(view, "#farm-form_state")
      assert has_element?(view, "#farm-form_country")
    end

    test "New Farm From with invalid attributes", %{conn: conn} do
      {:ok, view, html} = live(conn, Routes.farm_form_path(conn, :new))
      view |> form("#farm-form", %{farm: @invalid_attrs}) |> render_change()
      assert has_element?(view, "#name-invalid-feedback", "can't be blank")
      assert has_element?(view, "#address1-invalid-feedback", "can't be blank")
      refute has_element?(view, "#address2-invalid-feedback")
      assert has_element?(view, "#city-invalid-feedback", "can't be blank")
      assert has_element?(view, "#zipcode-invalid-feedback", "can't be blank")
      assert has_element?(view, "#state-invalid-feedback", "can't be blank")
      assert has_element?(view, "#country-invalid-feedback", "can't be blank")
    end

    test "New Farm From with valid attributes", %{conn: conn} do
      {:ok, view, html} = live(conn, Routes.farm_form_path(conn, :new))
      view |> form("#farm-form", %{farm: @valid_attrs_1}) |> render_change()
      refute has_element?(view, "#name-invalid-feedback")
      refute has_element?(view, "#address1-invalid-feedback")
      refute has_element?(view, "#address2-invalid-feedback")
      refute has_element?(view, "#city-invalid-feedback")
      refute has_element?(view, "#zipcode-invalid-feedback")
      refute has_element?(view, "#state-invalid-feedback")
      refute has_element?(view, "#country-invalid-feedback")
    end

    test "New Farm From with non-unique farm name for currently logged in user", %{conn: conn, user: user} do
      {:ok, farm} = Company.create_farm(@valid_attrs_1, user)
      {:ok, view, html} = live(conn, Routes.farm_form_path(conn, :new))
      view |> form("#farm-form", %{farm: @valid_attrs_1}) |> render_change()
      assert has_element?(view, "#name-invalid-feedback", "has already been taken")
    end

    test "User Farm Lists", %{conn: conn, user: user} do
      {:ok, _} = Company.create_farm(@valid_attrs_1, user)
      {:ok, _} = Company.create_farm(@valid_attrs_2, user)
      {:ok, view, html} = live(conn, Routes.farm_index_path(conn, :index))
      assert has_element?(view, ".title", "Farms Listing")
      assert has_element?(view, "")
    end
  end
end

#   test "updates farm in listing", %{conn: conn, farm: farm} do
#     {:ok, index_live, _html} = live(conn, Routes.farm_index_path(conn, :index))

#     assert index_live |> element("#farm-#{farm.id} a", "Edit") |> render_click() =~
#              "Edit Farm"

#     assert_patch(index_live, Routes.farm_index_path(conn, :edit, farm))

#     assert index_live
#            |> form("#farm-form", farm: @invalid_attrs)
#            |> render_change() =~ "can&#39;t be blank"

#     {:ok, _, html} =
#       index_live
#       |> form("#farm-form", farm: @update_attrs)
#       |> render_submit()
#       |> follow_redirect(conn, Routes.farm_index_path(conn, :index))

#     assert html =~ "Farm updated successfully"
#     assert html =~ "some updated address1"
#   end

#   test "deletes farm in listing", %{conn: conn, farm: farm} do
#     {:ok, index_live, _html} = live(conn, Routes.farm_index_path(conn, :index))

#     assert index_live |> element("#farm-#{farm.id} a", "Delete") |> render_click()
#     refute has_element?(index_live, "#farm-#{farm.id}")
#   end
# end

# describe "Show" do
#   setup [:create_farm]

#   test "displays farm", %{conn: conn, farm: farm} do
#     {:ok, _show_live, html} = live(conn, Routes.farm_show_path(conn, :show, farm))

#     assert html =~ "Show Farm"
#     assert html =~ farm.address1
#   end

#   test "updates farm within modal", %{conn: conn, farm: farm} do
#     {:ok, show_live, _html} = live(conn, Routes.farm_show_path(conn, :show, farm))

#     assert show_live |> element("a", "Edit") |> render_click() =~
#              "Edit Farm"

#     assert_patch(show_live, Routes.farm_show_path(conn, :edit, farm))

#     assert show_live
#            |> form("#farm-form", farm: @invalid_attrs)
#            |> render_change() =~ "can&#39;t be blank"

#     {:ok, _, html} =
#       show_live
#       |> form("#farm-form", farm: @update_attrs)
#       |> render_submit()
#       |> follow_redirect(conn, Routes.farm_show_path(conn, :show, farm))

#     assert html =~ "Farm updated successfully"
#     assert html =~ "some updated address1"
#   end
# end
