defmodule Peggy.FarmFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Peggy.Farm` context.
  """

  @doc """
  Generate a location.
  """
  def location_fixture(farm_user, attrs \\ %{}) do
    {:ok, location} =
      attrs
      |> Enum.into(%{
        code: "location-#{:rand.uniform(999999999)}",
        note: "some note",
        capacity: :rand.uniform(100),
        farm_id: farm_user.farm_id,
        status: Enum.at(Peggy.Farm.Location.status, :rand.uniform(3) - 1)
      })
      |> Peggy.Farm.create_location(farm_user)
    location
  end
end
