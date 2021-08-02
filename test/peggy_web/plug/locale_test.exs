defmodule PeggyWeb.LocaleTest do
  use PeggyWeb.ConnCase, async: true

  test "default locale will be using English", %{conn: conn} do
    conn = get(conn, "/")
    response = html_response(conn, 200)

    assert response =~ "中文"
    assert get_session(conn, :locale) == "en"
    assert %{assigns: %{locale: "en"}} = conn
  end

  test "will accept locale if input from URL params", %{conn: conn} do
    conn = get(conn, "/?locale=zh")
    response = html_response(conn, 200)

    assert response =~ "English"
    assert get_session(conn, :locale) == "zh"
    assert %{assigns: %{locale: "zh"}} = conn
  end

  test "will not accept unknown locale", %{conn: conn} do
    conn = get(conn, "/?locale=unknown")
    response = html_response(conn, 200)

    assert response =~ "中文"
    assert get_session(conn, :locale) == "en"
    assert %{assigns: %{locale: "en"}} = conn
  end
end
