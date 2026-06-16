defmodule PeggyWeb.MobileLive.InviteSessionTest do
  use PeggyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Peggy.FarmsFixtures

  alias Peggy.Farms

  defp mobile_conn(conn) do
    conn |> Plug.Test.put_req_cookie("peggy_view", "mobile")
  end

  test "manager sees QR SVG and roster heading", %{conn: conn} do
    scope = farm_scope_fixture()

    {:ok, _lv, html} =
      conn
      |> mobile_conn()
      |> log_in_user(scope.user)
      |> live(~p"/m/#{scope.farm.slug}/invite-session/worker")

    assert html =~ "<svg"
    assert html =~ "Joined so far"
  end

  test "worker is redirected to mobile farm home", %{conn: conn} do
    worker_scope = worker_scope_fixture()

    assert {:error, {:live_redirect, %{to: path}}} =
             conn
             |> mobile_conn()
             |> log_in_user(worker_scope.user)
             |> live(~p"/m/#{worker_scope.farm.slug}/invite-session/worker")

    assert path == ~p"/m/#{worker_scope.farm.slug}"
  end

  test "close button closes the session", %{conn: conn} do
    scope = farm_scope_fixture()

    {:ok, lv, _html} =
      conn
      |> mobile_conn()
      |> log_in_user(scope.user)
      |> live(~p"/m/#{scope.farm.slug}/invite-session/worker")

    html = lv |> element("button[phx-click='close']") |> render_click()
    assert html =~ "Session closed"
  end

  test "member_joined PubSub message inserts into roster", %{conn: conn} do
    scope = farm_scope_fixture()

    {:ok, lv, _html} =
      conn
      |> mobile_conn()
      |> log_in_user(scope.user)
      |> live(~p"/m/#{scope.farm.slug}/invite-session/worker")

    worker = member_fixture(scope.farm)
    membership = Farms.get_membership(worker, scope.farm) |> Peggy.Repo.preload(:user)
    send(lv.pid, {:member_joined, membership})

    html = render(lv)
    assert html =~ (worker.username || worker.email)
  end
end
