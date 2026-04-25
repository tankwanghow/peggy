defmodule Peggy.Policy do
  @moduledoc """
  Role-based authorization. All checks go through `can?/3`.

  Roles (in decreasing power): :owner, :manager, :worker, :vet.

  Actions are atoms grouped by resource. Unknown (scope, action) pairs
  default to `false` — fail closed.
  """

  alias Peggy.Accounts.Scope

  @type action :: atom()

  @spec can?(Scope.t() | nil, action(), any()) :: boolean()
  def can?(scope, action, resource \\ nil)
  def can?(%Scope{role: role}, action, _resource) when is_atom(role), do: allowed?(role, action)
  def can?(_, _, _), do: false

  # --- Role matrix ---------------------------------------------------------
  # Edit here when adding new actions. Keep narrow: a new permission should
  # be an explicit clause, not a blanket catch-all.

  # Owner can do anything.
  defp allowed?(:owner, _), do: true

  # Manager: everything except destructive farm admin.
  defp allowed?(:manager, :manage_farm_settings), do: true
  defp allowed?(:manager, :invite_member), do: true
  defp allowed?(:manager, :change_member_role), do: true
  defp allowed?(:manager, :remove_member), do: true
  defp allowed?(:manager, :manage_locations), do: true
  defp allowed?(:manager, :manage_animals), do: true
  defp allowed?(:manager, :view_audit), do: true
  defp allowed?(:manager, :delete_farm), do: false
  defp allowed?(:manager, action), do: allowed?(:worker, action)

  # Worker: day-to-day data entry.
  defp allowed?(:worker, :view_farm), do: true
  defp allowed?(:worker, :view_locations), do: true
  defp allowed?(:worker, :view_animals), do: true
  defp allowed?(:worker, :record_movement), do: true
  defp allowed?(:worker, :record_breeding), do: true
  defp allowed?(:worker, :read_breeding), do: true
  defp allowed?(:worker, :view_reports), do: true
  defp allowed?(:worker, :record_data), do: true
  defp allowed?(:worker, _), do: false

  # Vet: read + write treatments/vaccinations only.
  defp allowed?(:vet, :view_farm), do: true
  defp allowed?(:vet, :view_locations), do: true
  defp allowed?(:vet, :view_animals), do: true
  defp allowed?(:vet, :read_breeding), do: true
  defp allowed?(:vet, :view_reports), do: true
  defp allowed?(:vet, :record_health), do: true
  defp allowed?(:vet, _), do: false

  defp allowed?(_, _), do: false
end
