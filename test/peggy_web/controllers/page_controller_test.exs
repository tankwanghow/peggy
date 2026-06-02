defmodule PeggyWeb.PageControllerTest do
  use PeggyWeb.ConnCase, async: true

  test "desktop home renders the landing with an anonymous language switcher", %{conn: conn} do
    html =
      conn
      |> put_req_header("user-agent", "Mozilla (Macintosh)")
      |> get(~p"/")
      |> html_response(200)

    assert html =~ "Run your pig farm"
    assert html =~ "Bahasa Malaysia"
    assert html =~ "/locale/zh"
    refute html =~ ~s(id="mobile-home")
  end

  test "mobile visitor gets the mobile home with the switcher", %{conn: conn} do
    html =
      conn
      |> Plug.Test.put_req_cookie("peggy_view", "mobile")
      |> get(~p"/")
      |> html_response(200)

    assert html =~ ~s(id="mobile-home")
    assert html =~ "Run your pig farm"
    assert html =~ "Bahasa Malaysia"
  end
end
