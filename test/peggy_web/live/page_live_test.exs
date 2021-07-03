defmodule PeggyWeb.PageLiveTest do
  use PeggyWeb.ConnCase

  import Phoenix.LiveViewTest

  test "disconnected and connected render", %{conn: conn} do
    {:ok, page_live, disconnected_html} = live(conn, "/")
    assert disconnected_html =~ "Peggy"
    assert render(page_live) =~ "Peggy"
  end
end
