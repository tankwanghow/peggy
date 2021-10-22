defmodule PeggyWeb.LocationLiveTest do
  use PeggyWeb.ConnCase

  import Phoenix.LiveViewTest
  import Peggy.FarmFixtures

  @create_attrs %{capacity: 42, code: "some code", note: "some note", status: "active"}
  @update_attrs %{capacity: 43, code: "some updated code", note: "some updated note", status: "maintenance"}
  @invalid_attrs %{capacity: nil, code: nil, note: nil, status: nil}

  defp create_location(_) do
    location = location_fixture()
    %{location: location}
  end


end
