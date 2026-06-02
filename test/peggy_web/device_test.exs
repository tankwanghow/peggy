defmodule PeggyWeb.DeviceTest do
  use PeggyWeb.ConnCase, async: true

  test "peggy_view cookie overrides the user-agent" do
    assert PeggyWeb.Device.mobile?(Plug.Test.put_req_cookie(build_conn(), "peggy_view", "mobile"))

    desktop =
      build_conn()
      |> Plug.Test.put_req_cookie("peggy_view", "desktop")
      |> put_req_header("user-agent", "iPhone")

    refute PeggyWeb.Device.mobile?(desktop)
  end

  test "falls back to the user-agent when no cookie" do
    assert PeggyWeb.Device.mobile?(put_req_header(build_conn(), "user-agent", "Mozilla (iPhone)"))
    refute PeggyWeb.Device.mobile?(put_req_header(build_conn(), "user-agent", "Mozilla (Macintosh)"))
  end
end
