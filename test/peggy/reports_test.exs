defmodule Peggy.ReportsTest do
  use Peggy.DataCase, async: true

  import Peggy.AccountsFixtures
  import Peggy.FarmsFixtures
  import Peggy.LocationsFixtures
  import Peggy.AnimalsFixtures
  import Peggy.BreedingFixtures

  alias Peggy.{Breeding, Reports}

  setup do
    user = user_fixture()
    farm = farm_fixture(user)
    scope = scope_for(user, farm)
    house = house_fixture(scope, code: "H1", purpose: "farrowing")
    pen = pen_fixture(scope, house, code: "F1", capacity: 20)

    sow1 =
      animal_fixture(scope, ear_tag: "S1", stage: "sow", current_pen_id: pen.id)

    sow2 =
      animal_fixture(scope, ear_tag: "S2", stage: "sow", current_pen_id: pen.id)

    %{scope: scope, pen: pen, sow1: sow1, sow2: sow2}
  end

  test "summary with no events returns zero counts and nil KPIs", %{scope: scope} do
    s = Reports.summary(scope, %{from: ~D[2026-01-01], to: ~D[2026-03-31]})
    assert s.services_count == 0
    assert s.farrowings_count == 0
    assert s.weanings_count == 0
    assert is_nil(s.farrowing_rate)
    assert is_nil(s.avg_born_alive)
    assert is_nil(s.pre_wean_mortality)
  end

  test "farrowing rate counts only closed services", %{scope: scope, sow1: s1, sow2: s2} do
    # one closed → farrowing (success)
    _f =
      farrowing_fixture(scope, s1,
        service_type: "ai",
        farrowed_at: ~D[2026-02-01],
        born_alive: 10
      )

    # one closed → abortion (fail)
    {:ok, abort_svc} =
      Breeding.record_service(scope, %{
        sow_id: s2.id,
        service_type: "ai",
        served_at: ~D[2026-01-05]
      })

    {:ok, _} =
      Breeding.close_service(scope, abort_svc, "abortion", %{result_at: ~D[2026-01-20]})

    s = Reports.summary(scope, %{from: ~D[2025-01-01], to: ~D[2026-03-31]})
    assert s.services_count == 2
    assert_in_delta s.farrowing_rate, 0.5, 0.001
  end

  test "pre-wean mortality across paired farrow/wean", %{scope: scope, sow1: s1} do
    farrowing =
      farrowing_fixture(scope, s1,
        service_type: "ai",
        farrowed_at: ~D[2026-01-01],
        born_alive: 10
      )

    {:ok, _, _} =
      Breeding.record_weaning(scope, farrowing, %{
        weaned_at: ~D[2026-01-22],
        weaned_count: 8,
        batch_tag: "B1"
      })

    s = Reports.summary(scope, %{from: ~D[2026-01-01], to: ~D[2026-02-28]})
    assert s.farrowings_count == 1
    assert s.weanings_count == 1
    assert_in_delta s.pre_wean_mortality, 0.2, 0.001
    assert_in_delta s.avg_born_alive, 10.0, 0.001
    assert_in_delta s.avg_weaned, 8.0, 0.001
  end

  test "farm isolation: other farm's data is excluded", %{scope: scope, sow1: sow1} do
    _ =
      farrowing_fixture(scope, sow1,
        service_type: "ai",
        farrowed_at: ~D[2026-01-10],
        born_alive: 9
      )

    other_user = user_fixture()
    other_farm = farm_fixture(other_user)
    other_scope = scope_for(other_user, other_farm)

    s = Reports.summary(other_scope, %{from: ~D[2026-01-01], to: ~D[2026-12-31]})
    assert s.services_count == 0
    assert s.farrowings_count == 0
  end
end
