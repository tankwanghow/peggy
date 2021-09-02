defmodule PeggyWeb.InviteUserLiveTest do
  use PeggyWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Peggy.Company

  @create_attrs %{email: "some email", role: "some role"}
  @update_attrs %{email: "some updated email", role: "some updated role"}
  @invalid_attrs %{email: nil, role: nil}

  defp fixture(:invite_user) do
    {:ok, invite_user} = Company.create_invite_user(@create_attrs)
    invite_user
  end

  defp create_invite_user(_) do
    invite_user = fixture(:invite_user)
    %{invite_user: invite_user}
  end

  # describe "Index" do
  #   setup [:create_invite_user]

  #   test "lists all invite_users", %{conn: conn, invite_user: invite_user} do
  #     {:ok, _index_live, html} = live(conn, Routes.invite_user_index_path(conn, :index))

  #     assert html =~ "Listing Invite users"
  #     assert html =~ invite_user.email
  #   end

  #   test "saves new invite_user", %{conn: conn} do
  #     {:ok, index_live, _html} = live(conn, Routes.invite_user_index_path(conn, :index))

  #     assert index_live |> element("a", "New Invite user") |> render_click() =~
  #              "New Invite user"

  #     assert_patch(index_live, Routes.invite_user_index_path(conn, :new))

  #     assert index_live
  #            |> form("#invite_user-form", invite_user: @invalid_attrs)
  #            |> render_change() =~ "can&#39;t be blank"

  #     {:ok, _, html} =
  #       index_live
  #       |> form("#invite_user-form", invite_user: @create_attrs)
  #       |> render_submit()
  #       |> follow_redirect(conn, Routes.invite_user_index_path(conn, :index))

  #     assert html =~ "Invite user created successfully"
  #     assert html =~ "some email"
  #   end

  #   test "updates invite_user in listing", %{conn: conn, invite_user: invite_user} do
  #     {:ok, index_live, _html} = live(conn, Routes.invite_user_index_path(conn, :index))

  #     assert index_live |> element("#invite_user-#{invite_user.id} a", "Edit") |> render_click() =~
  #              "Edit Invite user"

  #     assert_patch(index_live, Routes.invite_user_index_path(conn, :edit, invite_user))

  #     assert index_live
  #            |> form("#invite_user-form", invite_user: @invalid_attrs)
  #            |> render_change() =~ "can&#39;t be blank"

  #     {:ok, _, html} =
  #       index_live
  #       |> form("#invite_user-form", invite_user: @update_attrs)
  #       |> render_submit()
  #       |> follow_redirect(conn, Routes.invite_user_index_path(conn, :index))

  #     assert html =~ "Invite user updated successfully"
  #     assert html =~ "some updated email"
  #   end

  #   test "deletes invite_user in listing", %{conn: conn, invite_user: invite_user} do
  #     {:ok, index_live, _html} = live(conn, Routes.invite_user_index_path(conn, :index))

  #     assert index_live |> element("#invite_user-#{invite_user.id} a", "Delete") |> render_click()
  #     refute has_element?(index_live, "#invite_user-#{invite_user.id}")
  #   end
  # end

  # describe "Show" do
  #   setup [:create_invite_user]

  #   test "displays invite_user", %{conn: conn, invite_user: invite_user} do
  #     {:ok, _show_live, html} = live(conn, Routes.invite_user_show_path(conn, :show, invite_user))

  #     assert html =~ "Show Invite user"
  #     assert html =~ invite_user.email
  #   end

  #   test "updates invite_user within modal", %{conn: conn, invite_user: invite_user} do
  #     {:ok, show_live, _html} = live(conn, Routes.invite_user_show_path(conn, :show, invite_user))

  #     assert show_live |> element("a", "Edit") |> render_click() =~
  #              "Edit Invite user"

  #     assert_patch(show_live, Routes.invite_user_show_path(conn, :edit, invite_user))

  #     assert show_live
  #            |> form("#invite_user-form", invite_user: @invalid_attrs)
  #            |> render_change() =~ "can&#39;t be blank"

  #     {:ok, _, html} =
  #       show_live
  #       |> form("#invite_user-form", invite_user: @update_attrs)
  #       |> render_submit()
  #       |> follow_redirect(conn, Routes.invite_user_show_path(conn, :show, invite_user))

  #     assert html =~ "Invite user updated successfully"
  #     assert html =~ "some updated email"
  #   end
  # end
end
