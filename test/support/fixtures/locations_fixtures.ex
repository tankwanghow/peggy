defmodule Peggy.LocationsFixtures do
  @moduledoc "Fixtures for the Locations context."

  alias Peggy.Accounts.Scope
  alias Peggy.Locations

  def scope_for(user, farm) do
    membership = Peggy.Farms.get_membership(user, farm)
    Scope.put_farm(Scope.for_user(user), farm, membership)
  end

  def house_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        code: "H#{System.unique_integer([:positive])}",
        purpose: "grower"
      })

    {:ok, h} = Locations.create_house(scope, attrs)
    h
  end

  def pen_fixture(scope, house, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        code: "P#{System.unique_integer([:positive])}",
        capacity: 20,
        status: "active"
      })

    {:ok, p} = Locations.create_pen(scope, house, attrs)
    p
  end
end
