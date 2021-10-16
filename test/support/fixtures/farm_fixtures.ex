defmodule Peggy.FarmFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Peggy.Farm` context.
  """

  @doc """
  Generate a location.
  """
  def location_fixture(attrs \\ %{}) do
    {:ok, location} =
      attrs
      |> Enum.into(%{
        location_code: "some location_code",
        note: "some note"
      })
      |> Peggy.Farm.create_location()

    location
  end
end
