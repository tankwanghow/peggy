defmodule Peggy.FarmsFixtures do
  @moduledoc "Fixtures for the Farms context."

  alias Peggy.Accounts.Scope
  alias Peggy.Farms

  import Peggy.AccountsFixtures

  def unique_farm_slug, do: "farm-#{System.unique_integer([:positive])}"

  def valid_farm_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Acme Farm",
      slug: unique_farm_slug(),
      timezone: "Asia/Kuala_Lumpur",
      unit_system: "metric"
    })
  end

  def farm_fixture(user, attrs \\ %{}) do
    {:ok, farm} = Farms.create_farm(user, valid_farm_attributes(attrs))
    farm
  end

  def farm_scope_fixture(attrs \\ %{}) do
    user = user_fixture()
    farm = farm_fixture(user, attrs)
    membership = Farms.get_membership(user, farm)
    Scope.put_farm(Scope.for_user(user), farm, membership)
  end

  def worker_scope_fixture(attrs \\ %{}) do
    owner_scope = farm_scope_fixture(attrs)
    worker = username_user_fixture()

    %Peggy.Farms.Membership{
      user_id: worker.id,
      farm_id: owner_scope.farm.id,
      role: "worker",
      accepted_at: DateTime.utc_now(:second)
    }
    |> Peggy.Farms.Membership.changeset(%{})
    |> Peggy.Repo.insert!()

    membership = Farms.get_membership(worker, owner_scope.farm)
    Scope.put_farm(Scope.for_user(worker), owner_scope.farm, membership)
  end
end
