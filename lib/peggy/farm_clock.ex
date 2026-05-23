defmodule Peggy.FarmClock do
  @moduledoc """
  Returns the "today" date a farm uses for date-based calculations
  (gestation day, lactation length, age, due-to-wean, dashboards).

  Each farm may pin a `simulated_today` — useful for legacy data
  imports where the real-world dates are years behind, or for demo
  / testing scenarios. When unset, the system clock is used.

  This **does not** affect `inserted_at`/`updated_at`, audit
  timestamps, or any datetime that represents wall-clock time —
  those always reflect real time. Only date-of-day calculations
  consult this module.
  """

  alias Peggy.Accounts.Scope
  alias Peggy.Farms.Farm

  @doc """
  Returns the farm's "today" — the calendar date in the farm's
  configured `timezone`. Precedence:

    1. `simulated_today` if set (already a fixed date)
    2. `Date` derived from `DateTime.now(farm.timezone)`
    3. `Date.utc_today/0` (fallback when no farm or unknown zone)

  Accepts a `%Scope{}`, a `%Farm{}`, or `nil`.
  """
  @spec today(Scope.t() | Farm.t() | nil) :: Date.t()
  def today(%Scope{farm: %Farm{} = farm}), do: today(farm)
  def today(%Farm{simulated_today: %Date{} = d}), do: d

  def today(%Farm{timezone: tz}) when is_binary(tz) and tz != "" do
    case DateTime.now(tz) do
      {:ok, dt} -> DateTime.to_date(dt)
      _ -> Date.utc_today()
    end
  end

  def today(_), do: Date.utc_today()

  @doc "True when the farm has a non-nil `simulated_today`."
  @spec simulated?(Scope.t() | Farm.t() | nil) :: boolean()
  def simulated?(%Scope{farm: %Farm{} = farm}), do: simulated?(farm)
  def simulated?(%Farm{simulated_today: %Date{}}), do: true
  def simulated?(_), do: false
end
