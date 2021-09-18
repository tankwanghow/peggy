defmodule PeggyWeb.FarmLiveTest do
  use PeggyWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Peggy.Company

  setup :register_and_log_in_user

  @valid_attrs_1 %{
    address1: "some address1",
    address2: "some address2",
    city: "some city",
    country: "Malaysia",
    name: "some name",
    state: "some state",
    weight_unit: "some weight_unit",
    zipcode: "some zipcode"
  }
  @valid_attrs_2 %{
      address1: "some updated address1",
      address2: "some updated address2",
      city: "some updated city",
      country: "Guatemala",
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

  describe "FarmLive Edit Form" do
    setup %{conn: conn, user: user} do
      {:ok, farm} = Company.create_farm(@valid_attrs_1, user)
      Company.create_farm(@valid_attrs_2, user)
      %{conn: conn, user: user, farm: farm}
    end

    test "edit with invalid attributes", %{conn: conn, farm: farm} do
      {:ok, view, _html} = live(conn, Routes.farm_form_path(conn, :edit, farm))
      view |> form("#farm-form", %{farm: @invalid_attrs}) |> render_change()
      assert has_element?(view, "#name-invalid-feedback", "can't be blank")
      assert has_element?(view, "#address1-invalid-feedback", "can't be blank")
      refute has_element?(view, "#address2-invalid-feedback")
      assert has_element?(view, "#city-invalid-feedback", "can't be blank")
      assert has_element?(view, "#zipcode-invalid-feedback", "can't be blank")
      assert has_element?(view, "#state-invalid-feedback", "can't be blank")
      assert has_element?(view, "#country-invalid-feedback", "can't be blank")
    end

    test "edit Farm From with valid attributes", %{conn: conn, farm: farm} do
      {:ok, view, _html} = live(conn, Routes.farm_form_path(conn, :edit, farm))
      view |> form("#farm-form", %{farm: @valid_attrs_1}) |> render_change()
      refute has_element?(view, "#name-invalid-feedback")
      refute has_element?(view, "#address1-invalid-feedback")
      refute has_element?(view, "#address2-invalid-feedback")
      refute has_element?(view, "#city-invalid-feedback")
      refute has_element?(view, "#zipcode-invalid-feedback")
      refute has_element?(view, "#state-invalid-feedback")
      refute has_element?(view, "#country-invalid-feedback")
    end
  end

  describe "FarmLive New Form" do
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
      {:ok, view, _html} = live(conn, Routes.farm_form_path(conn, :new))
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
      {:ok, view, _html} = live(conn, Routes.farm_form_path(conn, :new))
      view |> form("#farm-form", %{farm: @valid_attrs_1}) |> render_change()
      refute has_element?(view, "#name-invalid-feedback")
      refute has_element?(view, "#address1-invalid-feedback")
      refute has_element?(view, "#address2-invalid-feedback")
      refute has_element?(view, "#city-invalid-feedback")
      refute has_element?(view, "#zipcode-invalid-feedback")
      refute has_element?(view, "#state-invalid-feedback")
      refute has_element?(view, "#country-invalid-feedback")
    end

    test "New Farm From with non-unique farm name for currently logged in user", %{
      conn: conn,
      user: user
    } do
      {:ok, _farm} = Company.create_farm(@valid_attrs_1, user)
      {:ok, view, _html} = live(conn, Routes.farm_form_path(conn, :new))
      view |> form("#farm-form", %{farm: @valid_attrs_1}) |> render_change()
      assert has_element?(view, "#name-invalid-feedback", "has already been taken")
    end

    test "Submit New Farm From with valid attributes", %{conn: conn} do
      {:ok, view, _html} = live(conn, Routes.farm_form_path(conn, :new))
      view |> form("#farm-form", %{farm: @valid_attrs_1}) |> render_submit()
      flash = assert_redirect(view, "/farms")
      assert flash["success"] == "Farm created successfully"
    end

    test "Submit New Farm From with invalid attributes", %{conn: conn} do
      {:ok, view, _html} = live(conn, Routes.farm_form_path(conn, :new))
      v = view |> form("#farm-form", %{farm: @invalid_attrs}) |> render_submit()
    end
  end

  describe "Farm List Index" do
    test "User Farm Lists, no farm", %{conn: conn} do
      {:ok, view, html} = live(conn, Routes.farm_index_path(conn, :index))
      assert has_element?(view, "#page-title", "You have to Create a Farm to procced.")
      assert html =~ "href=\"/farms/new"
      refute html =~ "Set Active"
      refute html =~ "Current Active"
      refute html =~ "id=\"navbar-company-name\""
      assert html =~ "id=\"app-name\""
    end

    test "User Farm List, with farms and no active farm", %{conn: conn, user: user} do
      Company.create_farm(@valid_attrs_1, user)
      Company.create_farm(@valid_attrs_2, user)
      {:ok, view, html} = live(conn, Routes.farm_index_path(conn, :index))
      assert has_element?(view, "#page-title", "Please select an active farm.")
      assert html =~ "href=\"/farms/new"
      {:ok, fhtml} = Floki.parse_document(html)
      assert Enum.count(Floki.find(fhtml, "a.set-active")) == 2
      refute html =~ "Current Active"
      assert Enum.count(Floki.find(fhtml, "a.farm-edit-link")) == 2
    end

    test "User Farm List, with farms and click active farm", %{conn: conn, user: user} do
      {:ok, farm} = Company.create_farm(@valid_attrs_1, user)
      Company.create_farm(@valid_attrs_2, user)
      {:ok, view, _html} = live(conn, Routes.farm_index_path(conn, :index))

      assert {:error, {:redirect, %{to: "/set_active_farm?id=#{farm.id}"}}} ==
               view |> element("a#set-active-#{farm.id}") |> render_click()
    end
  end
end
