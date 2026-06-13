defmodule PeggyWeb.ManifestControllerTest do
  use PeggyWeb.ConnCase, async: true

  test "serves a manifest with absolute icon URLs", %{conn: conn} do
    conn = get(conn, ~p"/manifest.webmanifest")

    assert json_response(conn, 200)["name"] == "Peggy"

    icons = json_response(conn, 200)["icons"]
    assert length(icons) == 2
    assert Enum.all?(icons, &String.starts_with?(&1["src"], "http"))

    purposes =
      icons
      |> Enum.map(& &1["purpose"])
      |> Enum.uniq()

    assert purposes == ["any"]
  end
end