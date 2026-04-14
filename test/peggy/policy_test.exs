defmodule Peggy.PolicyTest do
  use ExUnit.Case, async: true

  alias Peggy.Accounts.Scope
  alias Peggy.Policy

  defp scope(role), do: %Scope{role: role}

  test "owner can do anything" do
    assert Policy.can?(scope(:owner), :delete_farm)
    assert Policy.can?(scope(:owner), :manage_farm_settings)
    assert Policy.can?(scope(:owner), :whatever_new_action)
  end

  test "manager can manage settings but not delete farm" do
    assert Policy.can?(scope(:manager), :manage_farm_settings)
    assert Policy.can?(scope(:manager), :invite_member)
    assert Policy.can?(scope(:manager), :record_data)
    refute Policy.can?(scope(:manager), :delete_farm)
  end

  test "worker can view and record, nothing else" do
    assert Policy.can?(scope(:worker), :view_farm)
    assert Policy.can?(scope(:worker), :record_data)
    refute Policy.can?(scope(:worker), :invite_member)
    refute Policy.can?(scope(:worker), :manage_farm_settings)
  end

  test "vet can view and record health only" do
    assert Policy.can?(scope(:vet), :view_farm)
    assert Policy.can?(scope(:vet), :record_health)
    refute Policy.can?(scope(:vet), :record_data)
    refute Policy.can?(scope(:vet), :invite_member)
  end

  test "nil scope denies everything" do
    refute Policy.can?(nil, :view_farm)
    refute Policy.can?(%Scope{role: nil}, :view_farm)
  end
end
