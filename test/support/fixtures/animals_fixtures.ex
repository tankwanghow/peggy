defmodule Peggy.AnimalsFixtures do
  @moduledoc "Fixtures for the Animals context."

  alias Peggy.Animals

  def animal_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        tracking_type: "individual",
        ear_tag: "ET#{System.unique_integer([:positive])}",
        stage: "grower",
        sex: "female",
        breed: "Landrace"
      })

    {:ok, a} = Animals.create_animal(scope, attrs)
    a
  end

  def batch_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        tracking_type: "batch",
        stage: "weaner",
        quantity: 20
      })

    {:ok, a} = Animals.create_animal(scope, attrs)
    a
  end
end
