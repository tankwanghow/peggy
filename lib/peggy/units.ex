defmodule Peggy.Units do
  @moduledoc """
  Unit formatting helpers that branch on a farm's `unit_system`
  (`"metric"` or `"imperial"`).

  Conversions follow the storage units the schema uses:

    * Weights are stored in **grams** (`*_weight_g` columns) and render
      as `g` (metric) or `lb` (imperial).
    * Lengths and temperatures are stored in metric base units (m, °C).

  Pass a `Peggy.Farms.Farm`, `Peggy.Accounts.Scope`, or a raw
  `unit_system` string. `nil` → metric.
  """

  alias Peggy.Accounts.Scope
  alias Peggy.Farms.Farm

  @type system :: String.t()
  @type ref :: system() | Farm.t() | Scope.t() | nil

  # ── Public formatters ────────────────────────────────────────────

  @doc "Format a weight stored in grams. Imperial → pounds."
  @spec format_weight_g(number() | nil, ref()) :: String.t()
  def format_weight_g(nil, _), do: ""

  def format_weight_g(g, ref) when is_number(g) do
    case unit_system(ref) do
      "imperial" -> "#{Float.round(g / 453.592, 1)} lb"
      _ -> "#{g} g"
    end
  end

  @doc "Unit label for grams-stored weights — `g` or `lb`."
  @spec weight_g_unit(ref()) :: String.t()
  def weight_g_unit(ref) do
    case unit_system(ref) do
      "imperial" -> "lb"
      _ -> "g"
    end
  end

  @spec format_weight(number() | nil, ref()) :: String.t()
  def format_weight(nil, _), do: ""

  def format_weight(kg, ref) when is_number(kg) do
    case unit_system(ref) do
      "imperial" -> "#{Float.round(kg * 2.20462, 1)} lb"
      _ -> "#{Float.round(kg * 1.0, 1)} kg"
    end
  end

  @spec format_length(number() | nil, ref()) :: String.t()
  def format_length(nil, _), do: ""

  def format_length(m, ref) when is_number(m) do
    case unit_system(ref) do
      "imperial" -> "#{Float.round(m * 3.28084, 1)} ft"
      _ -> "#{Float.round(m * 1.0, 1)} m"
    end
  end

  @spec format_temperature(number() | nil, ref()) :: String.t()
  def format_temperature(nil, _), do: ""

  def format_temperature(c, ref) when is_number(c) do
    case unit_system(ref) do
      "imperial" -> "#{Float.round(c * 9 / 5 + 32, 1)} °F"
      _ -> "#{Float.round(c * 1.0, 1)} °C"
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────

  @spec unit_system(ref()) :: system()
  def unit_system(%Scope{farm: %Farm{} = farm}), do: unit_system(farm)
  def unit_system(%Farm{unit_system: s}) when is_binary(s) and s != "", do: s
  def unit_system(s) when is_binary(s) and s != "", do: s
  def unit_system(_), do: "metric"
end
