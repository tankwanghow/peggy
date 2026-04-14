defmodule Peggy.FarmsFixtures do
  @moduledoc "Fixtures for the Farms context."

  alias Peggy.Farms

  def unique_farm_slug, do: "farm-#{System.unique_integer([:positive])}"

  def valid_farm_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Acme Farm",
      slug: unique_farm_slug(),
      timezone: "Asia/Kuala_Lumpur",
      unit_system: "metric"
    })
  end

  def farm_fixture(user, attrs \\ %{}) do
    {:ok, farm} = Farms.create_farm(user, valid_farm_attributes(attrs))
    farm
  end
end
