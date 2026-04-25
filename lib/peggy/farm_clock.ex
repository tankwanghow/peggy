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
  Returns the farm's "today". Falls back to `Date.utc_today/0` when:

    * `simulated_today` is `nil`
    * the input is `nil` (no farm in scope yet)

  Accepts a `%Scope{}`, a `%Farm{}`, or `nil`.
  """
  @spec today(Scope.t() | Farm.t() | nil) :: Date.t()
  def today(%Scope{farm: %Farm{} = farm}), do: today(farm)
  def today(%Farm{simulated_today: %Date{} = d}), do: d
  def today(_), do: Date.utc_today()

  @doc "True when the farm has a non-nil `simulated_today`."
  @spec simulated?(Scope.t() | Farm.t() | nil) :: boolean()
  def simulated?(%Scope{farm: %Farm{} = farm}), do: simulated?(farm)
  def simulated?(%Farm{simulated_today: %Date{}}), do: true
  def simulated?(_), do: false
end
