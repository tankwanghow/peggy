defmodule Peggy.BreedingFixtures do
  @moduledoc "Fixtures for the Breeding context."

  alias Peggy.Breeding
  import Peggy.LocationsFixtures

  def service_fixture(scope, sow, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        sow_id: sow.id,
        service_type: "natural",
        served_at: ~D[2026-01-01]
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
    farrowed_at = Map.get(attrs, :farrowed_at, Date.add(Date.utc_today(), -21))
    service_attrs = Map.take(attrs, [:boar_id, :served_at, :service_type])

    service_attrs =
      Map.merge(
        %{
          sow_id: sow.id,
          service_type: "natural",
          served_at: Date.add(farrowed_at, -Peggy.Breeding.gestation_days())
        },
        service_attrs
      )

    {:ok, service} = Breeding.record_service(scope, service_attrs)

    farrowing_attrs =
      attrs
      |> Map.drop([:boar_id, :served_at, :service_type])
      |> then(fn a -> Map.merge(%{farrowed_at: farrowed_at, born_alive: 10}, a) end)
      |> ensure_pen_id(scope, sow)

    {:ok, farrowing} = Breeding.record_farrowing(scope, service, farrowing_attrs)
    farrowing
  end

  defp ensure_pen_id(attrs, scope, sow) do
    cond do
      Map.has_key?(attrs, :pen_id) and not is_nil(attrs.pen_id) ->
        attrs

      not is_nil(sow.current_pen_id) ->
        Map.put(attrs, :pen_id, sow.current_pen_id)

      true ->
        u = System.unique_integer([:positive])
        house = house_fixture(scope, code: "FH#{u}", purpose: "farrowing")
        pen = pen_fixture(scope, house, code: "FP#{u}", capacity: 20)
        Map.put(attrs, :pen_id, pen.id)
    end
  end
end
