defmodule PeggyWeb.Plugs.AutoRouteByDeviceTest do
  use PeggyWeb.ConnCase, async: true

  @mobile_ua "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"

  test "mobile UA on /invitations/:token redirects to /m/invitations/:token" do
    conn =
      build_conn()
      |> put_req_header("user-agent", @mobile_ua)
      |> get(~p"/invitations/sometoken")

    assert redirected_to(conn) == ~p"/m/invitations/sometoken"
  end

  test "desktop UA on /m/invitations/:token redirects to /invitations/:token" do
    conn = get(build_conn(), ~p"/m/invitations/sometoken")
    assert redirected_to(conn) == ~p"/invitations/sometoken"
  end

  test "mobile cookie on /invitations/:token redirects to /m/invitations/:token" do
    conn =
      build_conn()
      |> Plug.Test.put_req_cookie("peggy_view", "mobile")
      |> get(~p"/invitations/sometoken")

    assert redirected_to(conn) == ~p"/m/invitations/sometoken"
  end

  test "desktop cookie on /m/invitations/:token redirects to /invitations/:token" do
    conn =
      build_conn()
      |> Plug.Test.put_req_cookie("peggy_view", "desktop")
      |> get(~p"/m/invitations/sometoken")

    assert redirected_to(conn) == ~p"/invitations/sometoken"
  end
end
