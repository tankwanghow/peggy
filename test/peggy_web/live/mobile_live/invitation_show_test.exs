defmodule PeggyWeb.MobileLive.InvitationShowTest do
  use PeggyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Peggy.AccountsFixtures
  import Peggy.FarmsFixtures

  alias Peggy.Farms
  alias Peggy.Farms.Invitation

  defp pending_invitation do
    scope = farm_scope_fixture()

    {:ok, invitation} =
      Farms.invite(scope.farm, %{"email" => nil, "role" => "worker"}, scope.user)

    %{scope: scope, invitation: invitation, encoded: Invitation.encode_token(invitation.token)}
  end

  # Pin the UI to mobile so the device auto-router doesn't redirect the test
  # conn (which has no mobile user-agent) away from /m/invitations/*.
  defp mobile_conn(conn), do: Plug.Test.put_req_cookie(conn, "peggy_view", "mobile")

  test "anonymous user sees farm name, role badge, and two CTAs", %{conn: conn} do
    %{scope: scope, encoded: encoded} = pending_invitation()

    {:ok, _lv, html} = conn |> mobile_conn() |> live(~p"/m/invitations/#{encoded}")

    assert html =~ scope.farm.name
    assert html =~ "worker"
    assert html =~ "Create account"
    assert html =~ "Log in"
  end

  test "clicking create account shows the account creation form", %{conn: conn} do
    %{encoded: encoded} = pending_invitation()

    {:ok, lv, _html} = conn |> mobile_conn() |> live(~p"/m/invitations/#{encoded}")
    html = lv |> element("button[phx-click='pick_create']") |> render_click()

    assert html =~ "Username"
    assert html =~ "Password"
    assert html =~ "Email"
  end

  test "clicking log in shows the login form", %{conn: conn} do
    %{encoded: encoded} = pending_invitation()

    {:ok, lv, _html} = conn |> mobile_conn() |> live(~p"/m/invitations/#{encoded}")
    html = lv |> element("button[phx-click='pick_login']") |> render_click()

    assert html =~ "Username or email"
    refute html =~ "Email (optional)"
  end

  test "back button from create mode returns to choose", %{conn: conn} do
    %{encoded: encoded} = pending_invitation()

    {:ok, lv, _html} = conn |> mobile_conn() |> live(~p"/m/invitations/#{encoded}")
    lv |> element("button[phx-click='pick_create']") |> render_click()
    html = lv |> element("button[phx-click='pick_choose']") |> render_click()

    assert html =~ "Create account"
    assert html =~ "Log in"
  end

  test "invalid token shows error card", %{conn: conn} do
    {:ok, _lv, html} = conn |> mobile_conn() |> live(~p"/m/invitations/not-a-real-token")
    assert html =~ "Invitation not valid"
  end

  test "logged-in user sees single accept button", %{conn: conn} do
    %{encoded: encoded} = pending_invitation()
    user = user_fixture()

    {:ok, _lv, html} =
      conn |> log_in_user(user) |> mobile_conn() |> live(~p"/m/invitations/#{encoded}")

    assert html =~ "Accept invitation"
    refute html =~ "Create account"
  end
end
