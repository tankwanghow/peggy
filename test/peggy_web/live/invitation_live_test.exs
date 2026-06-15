defmodule PeggyWeb.InvitationLiveTest do
  use PeggyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Peggy.AccountsFixtures
  import Peggy.FarmsFixtures

  alias Peggy.Farms
  alias Peggy.Farms.Invitation

  test "renders create and login forms for a valid token", %{conn: conn} do
    scope = farm_scope_fixture()

    {:ok, invitation} =
      Farms.invite(scope.farm, %{"role" => "worker"}, scope.user)

    encoded = Invitation.encode_token(invitation.token)

    {:ok, _view, html} = live(conn, ~p"/invitations/#{encoded}")

    assert html =~ "Create account"
    assert html =~ "Username"
    assert html =~ "Log in"
  end

  test "logged-in user sees one-click accept", %{conn: conn} do
    scope = farm_scope_fixture()
    user = username_user_fixture()

    {:ok, invitation} =
      Farms.invite(scope.farm, %{"role" => "worker"}, scope.user)

    encoded = Invitation.encode_token(invitation.token)

    {:ok, _view, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/invitations/#{encoded}")

    assert html =~ "Accept invitation"
    refute html =~ "Create account"
  end
end
