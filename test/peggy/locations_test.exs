defmodule Peggy.LocationsTest do
  use Peggy.DataCase, async: true

  import Peggy.AccountsFixtures
  import Peggy.FarmsFixtures
  import Peggy.LocationsFixtures

  alias Peggy.{Locations, Audit}

  setup do
    user = user_fixture()
    farm = farm_fixture(user)
    scope = scope_for(user, farm)
    %{user: user, farm: farm, scope: scope}
  end

  describe "houses and pens CRUD" do
    test "creates a tree and lists it", %{scope: scope} do
      house = house_fixture(scope, code: "N")
      _pen = pen_fixture(scope, house, code: "p1", capacity: 10)

      [h] = Locations.list_houses(scope)
      assert h.id == house.id
      assert [p] = h.pens
      assert p.capacity == 10
    end

    test "pen code must be unique per house, but reusable across houses", %{scope: scope} do
      h1 = house_fixture(scope, code: "h1")
      h2 = house_fixture(scope, code: "h2")

      {:ok, _} =
        Locations.create_pen(scope, h1, %{code: "x1", capacity: 5, status: "active"})

      assert {:error, _cs} =
               Locations.create_pen(scope, h1, %{code: "x1", capacity: 5, status: "active"})

      assert {:ok, _} =
               Locations.create_pen(scope, h2, %{code: "x1", capacity: 5, status: "active"})
    end

    test "validates pen capacity", %{scope: scope} do
      h = house_fixture(scope)

      assert {:error, cs} =
               Locations.create_pen(scope, h, %{code: "p", capacity: -1, status: "active"})

      assert %{capacity: _} = errors_on(cs)
    end

    test "validates house purpose", %{scope: scope} do
      assert {:error, cs} =
               Locations.create_house(scope, %{code: "h", purpose: "invalid"})

      assert %{purpose: _} = errors_on(cs)
    end
  end

  describe "scope isolation" do
    test "get_* functions are scoped to the farm", %{scope: scope} do
      h = house_fixture(scope)

      other_user = user_fixture()
      other_farm = farm_fixture(other_user)
      other_scope = scope_for(other_user, other_farm)

      assert_raise Ecto.NoResultsError, fn -> Locations.get_house!(other_scope, h.id) end
    end
  end

  describe "audit" do
    test "mutations write audit log rows", %{scope: scope} do
      h = house_fixture(scope, code: "n")
      p = pen_fixture(scope, h)
      {:ok, _} = Locations.update_house(scope, h, %{code: "n-renamed"})
      {:ok, _} = Locations.delete_pen(scope, p)

      rows = Audit.list(scope)
      actions = Enum.map(rows, & &1.action)
      assert "house.created" in actions
      assert "pen.created" in actions
      assert "house.updated" in actions
      assert "pen.deleted" in actions
    end

    test "audit rows are immutable at the DB level", %{scope: scope} do
      house_fixture(scope)
      [row | _] = Audit.list(scope)

      assert_raise Postgrex.Error, ~r/append-only/, fn ->
        Peggy.Repo.query!("UPDATE audit_logs SET action = 'tampered' WHERE id = $1", [row.id])
      end

      assert_raise Postgrex.Error, ~r/append-only/, fn ->
        Peggy.Repo.query!("DELETE FROM audit_logs WHERE id = $1", [row.id])
      end
    end
  end
end
