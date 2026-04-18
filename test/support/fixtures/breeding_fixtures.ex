defmodule Peggy.BreedingFixtures do
  @moduledoc "Fixtures for the Breeding context."

  alias Peggy.Breeding

  def service_fixture(scope, sow, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        sow_id: sow.id,
        service_type: "natural",
        served_at: Date.add(Date.utc_today(), -100)
      })

    {:ok, s} = Breeding.record_service(scope, attrs)
    s
  end

  @doc """
  Creates a service then records a farrowing for it.
  Returns the farrowing (with piglets discarded).
  """
  def farrowing_fixture(scope, sow, attrs \\ []) do
    attrs = Map.new(attrs)
    service_attrs = Map.take(attrs, [:boar_id, :served_at, :service_type])

    service_attrs =
      Map.merge(
        %{
          sow_id: sow.id,
          service_type: "natural",
          served_at: Date.add(Date.utc_today(), -120)
        },
        service_attrs
      )

    {:ok, service} = Breeding.record_service(scope, service_attrs)

    farrowing_attrs =
      attrs
      |> Map.drop([:boar_id, :served_at, :service_type])
      |> then(fn a ->
        Map.merge(
          %{farrowed_at: Date.add(Date.utc_today(), -21), born_alive: 10},
          a
        )
      end)

    {:ok, farrowing, _piglets} = Breeding.record_farrowing(scope, service, farrowing_attrs)
    farrowing
  end
end
