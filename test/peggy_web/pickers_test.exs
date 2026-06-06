defmodule PeggyWeb.PickersTest do
  use Peggy.DataCase, async: true
  import Peggy.AccountsFixtures
  import Peggy.FarmsFixtures
  import Peggy.LocationsFixtures
  import Peggy.AnimalsFixtures

  setup do
    owner = user_fixture()
    farm = farm_fixture(owner)
    scope = scope_for(owner, farm)
    %{scope: scope}
  end

  test "pen_items/1 returns %{id, label: HOUSE-PEN} for active pens", %{scope: scope} do
    house = house_fixture(scope, code: "EB")
    pen = pen_fixture(scope, house, code: "12", capacity: 10)

    items = PeggyWeb.Pickers.pen_items(scope)

    assert %{id: pen.id, label: "EB-12"} in items
  end

  test "boar_items/1 returns present boars by ear_tag", %{scope: scope} do
    house = house_fixture(scope, code: "EB")
    pen = pen_fixture(scope, house, code: "12", capacity: 10)
    boar = animal_fixture(scope, ear_tag: "BOAR1", stage: "boar", current_pen_id: pen.id)
    _sow = animal_fixture(scope, ear_tag: "SOW1", stage: "sow", current_pen_id: pen.id)

    items = PeggyWeb.Pickers.boar_items(scope)

    assert items == [%{id: boar.id, label: "BOAR1"}]
  end
end
