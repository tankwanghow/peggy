defmodule PeggyWeb.InviteSessionLiveTest do
  use PeggyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Peggy.AccountsFixtures
  import Peggy.FarmsFixtures

  alias Peggy.Farms

  test "owner opens a worker session: sees QR and a live roster updates", %{conn: conn} do
    scope = farm_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, html} = live(conn, ~p"/farms/#{scope.farm.slug}/invite-session/worker")

    assert html =~ "<svg"
    assert html =~ "/invitations/"

    joiner = username_user_fixture(%{username: "scannerjoe"})
    inv = Peggy.Repo.get_by!(Farms.Invitation, farm_id: scope.farm.id, reusable: true)
    {:ok, _} = Farms.accept_invitation(joiner, inv.token)

    assert render(view) =~ "scannerjoe"
  end

  test "a worker cannot open a session", %{conn: conn} do
    scope = worker_scope_fixture()
    conn = log_in_user(conn, scope.user)

    assert {:error, {:live_redirect, %{to: to}}} =
             live(conn, ~p"/farms/#{scope.farm.slug}/invite-session/worker")

    assert to == ~p"/farms/#{scope.farm.slug}/settings"
  end
end
