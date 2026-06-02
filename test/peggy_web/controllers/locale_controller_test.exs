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
    conn =
      conn |> put_req_header("referer", "https://evil.example.com/farms") |> get(~p"/locale/ms")

    assert redirected_to(conn) == "/"
  end

  test "an anonymous visitor sets the peggy_locale cookie and is redirected", %{} do
    conn =
      build_conn()
      |> put_req_header("referer", "http://localhost:4000/")
      |> get(~p"/locale/zh")

    assert redirected_to(conn) == "/"
    assert conn.resp_cookies["peggy_locale"].value == "zh"
  end

  test "a logged-in user gets both the cookie and a persisted user.locale", %{conn: conn} do
    conn = conn |> put_req_header("referer", "http://localhost:4000/farms") |> get(~p"/locale/ms")
    assert conn.resp_cookies["peggy_locale"].value == "ms"
    assert Peggy.Repo.reload(conn.assigns.current_scope.user).locale == "ms"
  end
end
