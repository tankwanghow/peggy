defmodule PeggyWeb.LocaleTest do
  use PeggyWeb.ConnCase, async: true

  alias Peggy.Accounts.{Scope, User}

  defp run(conn), do: PeggyWeb.Locale.call(conn, [])

  test "anonymous + peggy_locale cookie uses that locale and stores it in the session" do
    conn =
      build_conn()
      |> Plug.Test.put_req_cookie("peggy_locale", "ms")
      |> Plug.Test.init_test_session(%{})
      |> run()

    assert Gettext.get_locale(PeggyWeb.Gettext) == "ms"
    assert Plug.Conn.get_session(conn, :locale) == "ms"
  end

  test "logged-in user.locale wins over the cookie" do
    _conn =
      build_conn()
      |> Plug.Test.put_req_cookie("peggy_locale", "ms")
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.assign(:current_scope, %Scope{user: %User{locale: "zh"}})
      |> run()

    assert Gettext.get_locale(PeggyWeb.Gettext) == "zh"
  end

  test "no user and no cookie falls back to en" do
    _conn = build_conn() |> Plug.Test.init_test_session(%{}) |> run()
    assert Gettext.get_locale(PeggyWeb.Gettext) == "en"
  end
end
