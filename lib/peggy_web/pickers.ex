defmodule PeggyWeb.Pickers do
  @moduledoc """
  Builds `%{id, label}` item lists for the `<.autocomplete>` component.

  UI-neutral so both the desktop and phone UIs can use it without crossing
  LiveView module boundaries.
  """
  alias Peggy.{Animals, Locations}

  @doc "Active pens as autocomplete items labelled `HOUSE-PEN`."
  def pen_items(scope) do
    scope
    |> Locations.list_all_pens()
    |> Enum.map(&%{id: &1.id, label: "#{&1.house.code}-#{&1.code}"})
  end

  @doc "Present boars as autocomplete items labelled by ear tag."
  def boar_items(scope) do
    scope
    |> Animals.list_animals(status: "present")
    |> Enum.filter(&(&1.stage == "boar" and &1.ear_tag != nil))
    |> Enum.map(&%{id: &1.id, label: &1.ear_tag})
  end
end
