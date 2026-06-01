defmodule PeggyWeb.LocalizationTest do
  use PeggyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Peggy.AccountsFixtures

  test "language switcher shows the three languages for a logged-in user", %{conn: conn} do
    {:ok, _lv, html} = conn |> log_in_user(user_fixture()) |> live(~p"/farms")
    assert html =~ "Bahasa Malaysia"
    assert html =~ "中文"
    assert html =~ "/locale/ms"
    assert html =~ "/locale/zh"
  end
end
