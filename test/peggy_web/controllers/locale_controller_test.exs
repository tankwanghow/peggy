defmodule PeggyWeb.LocaleControllerTest do
  use PeggyWeb.ConnCase, async: true

  import Peggy.AccountsFixtures

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  test "updates the user's locale and redirects to the referring path", %{conn: conn} do
    conn =
      conn
      |> put_req_header("referer", "http://localhost:4000/farms?x=1")
      |> get(~p"/locale/ms")

    assert redirected_to(conn) == "/farms?x=1"
    assert Peggy.Repo.reload(conn.assigns.current_scope.user).locale == "ms"
  end

  test "ignores an unsupported locale", %{conn: conn} do
    conn = conn |> put_req_header("referer", "http://localhost:4000/farms") |> get(~p"/locale/xx")
    assert redirected_to(conn) == "/farms"
    assert Peggy.Repo.reload(conn.assigns.current_scope.user).locale == "en"
  end

  test "falls back to / for an external referer (no open redirect)", %{conn: conn} do
    conn = conn |> put_req_header("referer", "https://evil.example.com/farms") |> get(~p"/locale/ms")
    assert redirected_to(conn) == "/"
  end
end
