defmodule PeggyWeb.MembershipLiveTest do
  use PeggyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Peggy.AccountsFixtures
  import Peggy.FarmsFixtures

  alias Peggy.Farms

  test "owner sees members and can invite", %{conn: conn} do
    scope = farm_scope_fixture()
    conn = log_in_user(conn, scope.user)
    _member = member_fixture(scope.farm)

    {:ok, view, _html} = live(conn, ~p"/farms/#{scope.farm.slug}/members")

    assert has_element?(view, "#members-list")
    assert has_element?(view, "#invite-form")

    html =
      view
      |> form("#invite-form", invitation: %{email: "new@example.com", role: "worker"})
      |> render_submit()

    assert has_element?(view, "#pending-invitations", "new@example.com")
    assert html =~ "Invitation sent to new@example.com"
  end

  test "owner can change a member's role", %{conn: conn} do
    scope = farm_scope_fixture()
    conn = log_in_user(conn, scope.user)
    member = member_fixture(scope.farm)
    membership = Farms.get_membership(member, scope.farm)

    {:ok, view, _html} = live(conn, ~p"/farms/#{scope.farm.slug}/members")

    view
    |> element("#member-#{membership.id} form")
    |> render_change(%{"membership_id" => membership.id, "role" => "manager"})

    assert Farms.get_membership(member, scope.farm).role == "manager"
  end

  test "owner can revoke a pending invitation", %{conn: conn} do
    scope = farm_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, invitation} =
      Farms.invite(
        scope.farm,
        %{"email" => "pending@example.com", "role" => "worker"},
        scope.user
      )

    {:ok, view, _html} = live(conn, ~p"/farms/#{scope.farm.slug}/members")

    assert has_element?(view, "#revoke-invite-#{invitation.id}")

    view |> element("#revoke-invite-#{invitation.id}") |> render_click()

    refute has_element?(view, "#pending-invitations", "pending@example.com")
    assert Farms.list_pending_invitations(scope.farm) == []
  end

  test "worker does not see management controls", %{conn: conn} do
    scope = worker_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} = live(conn, ~p"/farms/#{scope.farm.slug}/members")

    assert has_element?(view, "#members-list")
    refute has_element?(view, "#invite-form")
  end

  test "owner sees manager/worker QR invite links", %{conn: conn} do
    scope = farm_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, _view, html} = live(conn, ~p"/farms/#{scope.farm.slug}/members")

    assert html =~ ~p"/farms/#{scope.farm.slug}/invite-session/manager"
    assert html =~ ~p"/farms/#{scope.farm.slug}/invite-session/worker"
  end

  test "owner can create an email-less invite and see the shareable link", %{conn: conn} do
    scope = farm_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} = live(conn, ~p"/farms/#{scope.farm.slug}/members")

    view
    |> form("#invite-form", invitation: %{email: "", role: "worker"})
    |> render_submit()

    assert has_element?(view, "#invite-link a[href*='/invitations/']")
  end
end
