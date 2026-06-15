defmodule PeggyWeb.QRTest do
  use ExUnit.Case, async: true

  alias PeggyWeb.QR

  test "svg/1 returns an SVG element for a URL" do
    svg = QR.svg("https://example.com/invitations/abc")
    assert svg =~ "<svg"
    assert svg =~ "https://example.com/invitations/abc" or svg =~ "viewBox"
  end
end
