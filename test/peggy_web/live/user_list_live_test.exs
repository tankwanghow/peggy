defmodule PeggyWeb.UserListLiveTest do
  use PeggyWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Peggy.Company

  setup :register_and_log_in_user

  describe "User List" do
    setup %{conn: conn, user: user} do
      {:ok, user1} =
        Peggy.UserAccountsFixtures.user_fixture()
        |> Peggy.UserAccounts.User.confirm_changeset()
        |> Peggy.Repo.update()

      {:ok, user2} =
        Peggy.UserAccountsFixtures.user_fixture()
        |> Peggy.UserAccounts.User.confirm_changeset()
        |> Peggy.Repo.update()

      farm = Peggy.CompanyFixtures.farm_fixture(%{}, user)

      Company.allow_user_access_farm(user1, farm, "guest", user)
      Company.allow_user_access_farm(user2, farm, "guest", user)

      %{conn: conn, user: user, farm: farm, user1: user1, user2: user2}
    end

    test "unchange is passed _target have no user id", %{
      conn: conn,
      farm: farm,
      user1: user1,
      user2: user2
    } do
      {:ok, view, vhtml} = live(conn, Routes.user_index_path(conn, :index, farm.id))

      html =
        view
        |> element("form#user-list")
        |> render_change(%{
          "user_#{user1.id}" => %{id: user1.id, role: "manager"},
          "user_#{user2.id}" => %{id: user2.id, role: "admin"},
          _target: ["user", "role"]
        })

      {:ok, fhtml} = Floki.parse_document(html)
      {:ok, vhtml} = Floki.parse_document(vhtml)

      assert Floki.find(fhtml, "form#user-list") == Floki.find(vhtml, "form#user-list")

    end

    test "admin can see the user list", %{
      conn: conn,
      user: user,
      farm: farm,
      user1: user1,
      user2: user2
    } do
      {:ok, view, html} = live(conn, Routes.user_index_path(conn, :index, farm.id))
      {:ok, fhtml} = Floki.parse_document(html)
      assert view |> has_element?(".title", "User List")
      assert fhtml |> Floki.find("select") |> Enum.count() == 2
      assert fhtml |> Floki.find("input[type=hidden][value=#{user1.id}") |> Enum.count() == 1
      assert fhtml |> Floki.find("input[type=hidden][value=#{user2.id}") |> Enum.count() == 1
      assert fhtml |> Floki.find("input[type=hidden][value=#{user.id}") |> Enum.count() == 0
    end

    test "not admin cannot see the user list", %{
      conn: conn,
      farm: farm
    } do
      {:ok, view, html} = live(conn, Routes.user_index_path(conn, :index, farm.id))
      {:ok, fhtml} = Floki.parse_document(html)
      assert view |> has_element?(".title", "User List")
      assert fhtml |> Floki.find("card") |> Enum.count() == 0
    end

    test "admin can update role", %{
      conn: conn,
      farm: farm,
      user1: user1,
      user2: user2
    } do
      {:ok, view, _html} = live(conn, Routes.user_index_path(conn, :index, farm.id))

      html =
        view
        |> element("form#user-list")
        |> render_change(%{
          "user_#{user1.id}" => %{id: user1.id, role: "manager"},
          "user_#{user2.id}" => %{id: user2.id, role: "admin"},
          _target: ["user_#{user1.id}", "role"]
        })

      {:ok, fhtml} = Floki.parse_document(html)

      assert fhtml
             |> Floki.find("#live-flash .notification.is-success")
             |> Floki.text()
             |> String.trim() ==
               "Successfully updated user role to manager"

      assert fhtml |> Floki.find("#user_#{user1.id}_role option[selected]") |> Floki.text() ==
               "manager"

      assert fhtml |> Floki.find("#user_#{user2.id}_role option[selected]") |> Floki.text() ==
               "guest"
    end

    test "admin cannot update own role", %{
      conn: conn,
      farm: farm,
      user: user,
      user1: user1,
      user2: user2
    } do
      Company.change_user_role_in_farm(user1.id, farm, "admin", user.id)

      conn = log_in_user(conn, user1)

      {:ok, view, _html} = live(conn, Routes.user_index_path(conn, :index, farm.id))

      html =
        view
        |> element("form#user-list")
        |> render_change(%{
          "user_#{user1.id}" => %{id: user1.id, role: "manager"},
          "user_#{user2.id}" => %{id: user2.id, role: "supervisor"},
          _target: ["user_#{user1.id}", "role"]
        })

      {:ok, fhtml} = Floki.parse_document(html)

      assert fhtml
             |> Floki.find("#live-flash .notification.is-danger")
             |> Floki.text()
             |> String.trim() ==
               "Cannot change own role Failed to change user to manager"

      assert fhtml |> Floki.find("#user_#{user.id}_role option[selected]") |> Floki.text() ==
               "admin"

      assert fhtml |> Floki.find("#user_#{user2.id}_role option[selected]") |> Floki.text() ==
               "guest"

      assert fhtml |> Floki.find("input[type=hidden][value=#{user1.id}") |> Enum.count() == 0
    end

    test "non admin cannot update role", %{
      conn: conn,
      farm: farm,
      user: user,
      user1: user1,
      user2: user2
    } do
      Company.change_user_role_in_farm(user1.id, farm, "admin", user.id)

      conn = log_in_user(conn, user1)

      {:ok, view, _html} = live(conn, Routes.user_index_path(conn, :index, farm.id))

      Company.change_user_role_in_farm(user1.id, farm, "manager", user.id)

      html =
        view
        |> element("form#user-list")
        |> render_change(%{
          "user_#{user.id}" => %{id: user.id, role: "manager"},
          "user_#{user2.id}" => %{id: user2.id, role: "supervisor"},
          _target: ["user_#{user.id}", "role"]
        })

      {:ok, fhtml} = Floki.parse_document(html)

      assert fhtml
             |> Floki.find("#live-flash .notification.is-danger")
             |> Floki.text()
             |> String.trim() ==
               "Not Authorise Failed to change user to manager"

      assert fhtml |> Floki.find("card") |> Enum.count() == 0
    end
  end
end
