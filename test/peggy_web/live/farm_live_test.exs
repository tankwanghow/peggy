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

  describe "FarmLive Delete" do
    setup %{conn: conn, user: user} do
      {:ok, farm} = Company.create_farm(@valid_attrs_1, user)
      Company.create_farm(@valid_attrs_2, user)
      %{conn: conn, user: user, farm: farm}
    end

    test "deleting farm", %{conn: conn, user: user, farm: farm} do
      {:ok, view, _html} = live(conn, Routes.farm_form_path(conn, :edit, farm))

      view |> element("#delete-farm") |> render_click()

      flash = assert_redirect(view, "/farms")
      assert flash["success"] == "Farm Deleted successfully"

      assert Company.get_farm(farm.id, user) == nil
    end

    test "deleteing current active farm", %{conn: conn, farm: farm} do
      conn = post(conn, Routes.set_active_farm_path(conn, :create, %{id: farm.id}))
      {:ok, view, _html} = live(conn, Routes.farm_form_path(conn, :edit, farm))

      view |> element("#delete-farm") |> render_click()

      flash = assert_redirect(view, "/clear_set_active_farm")
      assert flash["success"] == "Farm Deleted successfully"
    end

    test "deleting farm, not admin user", %{conn: conn, user: user, farm: farm} do
      user1 = Peggy.UserAccountsFixtures.user_fixture()

      Company.allow_user_access_farm(
        user1.id,
        "guest",
        Peggy.Company.get_farm_user(farm.id, user.id)
      )

      conn = log_in_user(conn, user1)

      {:ok, view, _html} = live(conn, Routes.farm_form_path(conn, :edit, farm.id))

      html = view |> element("#delete-farm") |> render_click()

      assert html =~ "Editing Farm."
      assert html =~ "Failed to Delete Farm"
      assert html =~ "Not Authorise"
    end
  end

  describe "FarmLive Edit Form" do
    setup %{conn: conn, user: user} do
      {:ok, farm} = Company.create_farm(@valid_attrs_1, user)
      Company.create_farm(@valid_attrs_2, user)
      %{conn: conn, user: user, farm: farm}
    end

    test "Submit Edit Farm From with valid attributes, not admin user", %{
      conn: conn,
      user: user,
      farm: farm
    } do
      user1 = Peggy.UserAccountsFixtures.user_fixture()

      Company.allow_user_access_farm(
        user1.id,
        "guest",
        Peggy.Company.get_farm_user(farm.id, user.id)
      )

      conn = log_in_user(conn, user1)
      {:ok, view, _html} = live(conn, Routes.farm_form_path(conn, :edit, farm))

      html =
        view
        |> form("#farm-form", %{farm: %{name: "stuff", city: "fire", country: "Malaysia"}})
        |> render_submit()

      assert html =~ "Editing Farm."
      assert html =~ "Failed to Update Farm"
      assert html =~ "Not Authorise"
    end

    test "Submit Edit Farm From with invalid attributes", %{conn: conn, farm: farm} do
      {:ok, view, _html} = live(conn, Routes.farm_form_path(conn, :edit, farm))
      html = view |> form("#farm-form", %{farm: @invalid_attrs}) |> render_submit()
      assert html =~ "Editing Farm."
    end

    test "submit edit current active farm with valid attributes", %{conn: conn, farm: farm} do
      conn = post(conn, Routes.set_active_farm_path(conn, :create, %{id: farm.id}))
      {:ok, view, _html} = live(conn, Routes.farm_form_path(conn, :edit, farm))

      view
      |> form("#farm-form", %{farm: %{name: "stuff", city: "fire", country: "Malaysia"}})
      |> render_submit()

      flash = assert_redirect(view, "/update_active_farm?id=#{farm.id}")
      assert flash["success"] == "Farm updated successfully"
    end

    test "Submit Edit Farm From with valid attributes", %{conn: conn, farm: farm} do
      {:ok, view, _html} = live(conn, Routes.farm_form_path(conn, :edit, farm))

      view
      |> form("#farm-form", %{farm: %{name: "stuff", city: "fire", country: "Malaysia"}})
      |> render_submit()

      flash = assert_redirect(view, "/farms")
      assert flash["success"] == "Farm updated successfully"
    end

    test "Edit Farm From with non-unique farm name for currently logged in user", %{
      conn: conn,
      farm: farm
    } do
      
      {:ok, view, _html} = live(conn, Routes.farm_form_path(conn, :edit, farm))
      view |> form("#farm-form", %{farm: @valid_attrs_2}) |> render_change()
      assert has_element?(view, "#name-invalid-feedback", "has already been taken")
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
      html = view |> form("#farm-form", %{farm: @invalid_attrs}) |> render_submit()
      assert html =~ "Please Create a Farm."
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
      assert Enum.count(Floki.find(fhtml, "a.set-active-button")) == 2
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

    test "User Farm List, click Set Default", %{conn: conn, user: user} do
      {:ok, farm1} = Company.create_farm(@valid_attrs_1, user)
      {:ok, farm2} = Company.create_farm(@valid_attrs_2, user)
      {:ok, view, html} = live(conn, Routes.farm_index_path(conn, :index))
      {:ok, fhtml} = Floki.parse_document(html)
      assert Enum.count(Floki.find(fhtml, "a.farm-edit-link")) == 2

      refute has_element?(view, "#default-farm-#{farm1.id}")
      refute has_element?(view, "#default-farm-#{farm2.id}")

      view |> element("a#set-default-farm-#{farm1.id}") |> render_click()
      assert has_element?(view, "#default-farm-#{farm1.id}")
      refute has_element?(view, "#default-farm-#{farm2.id}")

      view |> element("a#set-default-farm-#{farm2.id}") |> render_click()
      assert has_element?(view, "#default-farm-#{farm2.id}")
      refute has_element?(view, "#default-farm-#{farm1.id}")
    end
  end
end
