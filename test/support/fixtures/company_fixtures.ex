defmodule Peggy.CompanyFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Peggy.UserAccounts` context.
  """

  def unique_farm_name, do: "farm#{System.unique_integer()}"
  def valid_user_password, do: "hello world!"

  def valid_farm_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: unique_farm_name(),
      address1: "some address1",
      address2: "some address2",
      city: "some city",
      country: "Malaysia",
      state: "some state",
      weight_unit: "some weight_unit",
      zipcode: "some zipcode"
    })
  end

  def farm_fixture(attrs \\ %{}, user) do
    {:ok, farm} =
      attrs
      |> valid_farm_attributes()
      |> Peggy.Company.create_farm(user)
    farm
  end
end
