defmodule Peggy.Units do
  @moduledoc """
  Unit formatting helpers that branch on a farm's `unit_system`
  (`"metric"` or `"imperial"`). Phase 1 stubs — real conversion tables
  land when the feature work needs them.
  """

  @type system :: String.t()

  @spec format_weight(number() | nil, system()) :: String.t()
  def format_weight(nil, _), do: ""
  def format_weight(kg, "imperial") when is_number(kg), do: "#{Float.round(kg * 2.20462, 1)} lb"
  def format_weight(kg, _metric) when is_number(kg), do: "#{Float.round(kg * 1.0, 1)} kg"

  @spec format_length(number() | nil, system()) :: String.t()
  def format_length(nil, _), do: ""
  def format_length(m, "imperial") when is_number(m), do: "#{Float.round(m * 3.28084, 1)} ft"
  def format_length(m, _metric) when is_number(m), do: "#{Float.round(m * 1.0, 1)} m"

  @spec format_temperature(number() | nil, system()) :: String.t()
  def format_temperature(nil, _), do: ""
  def format_temperature(c, "imperial") when is_number(c), do: "#{Float.round(c * 9 / 5 + 32, 1)} °F"
  def format_temperature(c, _metric) when is_number(c), do: "#{Float.round(c * 1.0, 1)} °C"
end
