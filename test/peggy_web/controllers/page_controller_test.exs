defmodule PeggyWeb.PageControllerTest do
  use PeggyWeb.ConnCase

  test "GET / shows the landing page for anonymous visitors", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    assert response =~ "Run your pig farm"
    assert response =~ ~p"/users/register"
  end

  test "GET / redirects logged-in users to /farms", %{conn: conn} do
    user = Peggy.AccountsFixtures.user_fixture()
    conn = conn |> log_in_user(user) |> get(~p"/")
    assert redirected_to(conn) == ~p"/farms"
  end
end
