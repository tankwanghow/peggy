defmodule PeggyWeb.InviteUserLiveTest do
    use PeggyWeb.ConnCase

    import Phoenix.LiveViewTest

    alias Peggy.Company

  setup :register_and_log_in_user

  describe "Invite User New" do
    setup %{conn: conn, user: user} do
      farm = Peggy.CompanyFixtures.farm_fixture(%{}, user)
      Peggy.CompanyFixtures.farm_fixture(%{}, user)
      %{conn: conn, user: user, farm: farm}
    end

    test "invite must have email and role fields is required", %{conn: conn, farm: farm} do
      {:ok, view, _html} = live(conn, Routes.invite_user_new_path(conn, :new, farm.id))
      assert has_element?(view, "input#invite-form_email[required][type=email]")
      assert has_element?(view, "select#invite-form_role[required]")
      assert has_element?(view, "#invite-to-company", farm.name)
    end

    test "not allow to invite self", %{conn: conn, user: user, farm: farm} do
      {:ok, view, _html} = live(conn, Routes.invite_user_new_path(conn, :new, farm.id))
      html = view |> form("#invite-form", %{invite_user: %{email: user.email, role: "clerk"}}) |> render_submit()
      assert html =~ "Cannot invite yourself"
    end

    test "only admin can invite user", %{conn: conn, user: user, farm: farm} do
      otheruser = Peggy.UserAccountsFixtures.user_fixture()
      Company.allow_user_access_farm(otheruser, farm, "clerk", user)
      conn = log_in_user(conn, otheruser)
      {:ok, view, _html} = live(conn, Routes.invite_user_new_path(conn, :new, farm.id))
      html = view |> form("#invite-form", %{invite_user: %{email: user.email, role: "clerk"}}) |> render_submit()
      assert html =~ "Only Admin allow to invite"
    end

    test "send email to invited unregister user", %{conn: conn, farm: farm} do
      {:ok, view, _html} = live(conn, Routes.invite_user_new_path(conn, :new, farm.id))
      html = view |> form("#invite-form", %{invite_user: %{email: "a@a.a", role: "clerk"}}) |> render_submit()
      assert html =~ "Invitation email has been sent to new user - a@a.a"
      refute (user = Peggy.UserAccounts.get_user_by_email("a@a.a")) == nil
      assert Peggy.Company.user_role_in_farm(user, farm) == "clerk"
    end

    test "send email to invited registered user", %{conn: conn, farm: farm} do
      otheruser = Peggy.UserAccountsFixtures.user_fixture()
      {:ok, otheruser} = Peggy.UserAccounts.User.confirm_changeset(otheruser) |> Peggy.Repo.update()
      {:ok, view, _html} = live(conn, Routes.invite_user_new_path(conn, :new, farm.id))
      html = view |> form("#invite-form", %{invite_user: %{email: otheruser.email, role: "clerk"}}) |> render_submit()
      assert html =~ "Invitation email has been sent to existing user - #{otheruser.email}"
      assert Peggy.Company.user_role_in_farm(otheruser, farm) == "clerk"
    end

    test "resend Invitation to user already allow to access farm", %{conn: conn, user: user, farm: farm} do
      otheruser = Peggy.UserAccountsFixtures.user_fixture()
      Company.allow_user_access_farm(otheruser, farm, "clerk", user)
      {:ok, view, _html} = live(conn, Routes.invite_user_new_path(conn, :new, farm.id))
      html = view |> form("#invite-form", %{invite_user: %{email: otheruser.email, role: "clerk"}}) |> render_submit()
      assert html =~ "Resended Invitation, because " <> otheruser.email <> " already invited."
    end
  end
end
