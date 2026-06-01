defmodule Peggy.Reports.PerformanceAnalysisTest do
  use Peggy.DataCase, async: true

  alias Peggy.Reports.PerformanceAnalysis, as: PA

  describe "calendar_months/2" do
    test "splits a full year into 12 labelled month buckets" do
      months = PA.calendar_months(~D[2025-01-01], ~D[2025-12-31])
      assert length(months) == 12
      assert hd(months) == %{label: "01-01-25", from: ~D[2025-01-01], to: ~D[2025-01-31]}
      assert List.last(months) == %{label: "01-12-25", from: ~D[2025-12-01], to: ~D[2025-12-31]}
    end

    test "clips partial first and last months to the range" do
      months = PA.calendar_months(~D[2025-01-15], ~D[2025-02-10])
      assert months == [
               %{label: "15-01-25", from: ~D[2025-01-15], to: ~D[2025-01-31]},
               %{label: "01-02-25", from: ~D[2025-02-01], to: ~D[2025-02-10]}
             ]
    end
  end

  describe "build/2 dataset" do
    setup do
      user = Peggy.AccountsFixtures.user_fixture()
      farm = Peggy.FarmsFixtures.farm_fixture(user)
      scope = Peggy.LocationsFixtures.scope_for(user, farm)
      house = Peggy.LocationsFixtures.house_fixture(scope, code: "H1")
      pen = Peggy.LocationsFixtures.pen_fixture(scope, house, code: "P1", capacity: 50)
      sow = Peggy.AnimalsFixtures.animal_fixture(scope, ear_tag: "S1", stage: "sow", current_pen_id: pen.id)
      %{scope: scope, sow: sow}
    end

    test "build/2 returns periods and three sections", %{scope: scope, sow: sow} do
      Peggy.BreedingFixtures.service_fixture(scope, sow, served_at: ~D[2025-03-10], service_type: "ai")
      result = build_year(scope)
      assert length(result.periods) == 12
      assert Enum.map(result.sections, & &1.key) == [:service, :farrowing, :weaning]
    end

    test "end-to-end: a March service + farrowing + weaning lands in the right columns", %{scope: scope, sow: sow} do
      f = Peggy.BreedingFixtures.farrowing_fixture(scope, sow, farrowed_at: ~D[2025-03-20], born_alive: 11, service_type: "ai")
      {:ok, _, _} = Peggy.Breeding.record_weaning(scope, f, %{weaned_at: ~D[2025-04-14], weaned_count: 10, batch_tag: "W-E2E"})

      result = build_year(scope)
      farrowings = Enum.find(result.sections, &(&1.key == :farrowing))
      far_count = Enum.find(farrowings.rows, &(&1.key == :farrowings))
      assert Enum.at(far_count.values, 2) == 1   # March
      assert far_count.acum == 1

      weanings = Enum.find(result.sections, &(&1.key == :weaning))
      pigs = Enum.find(weanings.rows, &(&1.key == :pigs_weaned))
      assert Enum.at(pigs.values, 3) == 10       # April
    end
  end

  defp build_year(scope),
    do: Peggy.Reports.PerformanceAnalysis.build(scope, %{from: ~D[2025-01-01], to: ~D[2025-12-31]})

  describe "farrowing metrics (pure)" do
    alias Peggy.Reports.PerformanceAnalysis, as: PA

    test "litter composition" do
      fs = [
        %{born_alive: 12, stillborn: 1, mummified: 0, total_birth_weight_g: nil, parity: 3, gestation_days: 115, interval_days: 150},
        %{born_alive: 6, stillborn: 3, mummified: 1, total_birth_weight_g: nil, parity: 5, gestation_days: 114, interval_days: 160}
      ]
      assert PA.m_count(fs) == 2
      assert_in_delta PA.m_pct_small_litter(fs), 50.0, 0.1   # one < 7 born alive
      assert_in_delta PA.m_avg(fs, :parity), 4.0, 0.01
      assert_in_delta PA.m_avg_total_born(fs), 11.5, 0.01     # (13 + 10)/2
      assert_in_delta PA.m_avg(fs, :born_alive), 9.0, 0.01
      assert_in_delta PA.m_pct_of_total_born(fs, :stillborn), 17.39, 0.1  # 4/23
      assert_in_delta PA.m_avg(fs, :gestation_days), 114.5, 0.01
    end

    test "birthweight per liveborn only over recorded rows" do
      fs = [
        %{born_alive: 10, total_birth_weight_g: 14_000},
        %{born_alive: 10, total_birth_weight_g: nil}
      ]
      assert PA.m_birthweight_per_liveborn(fs) == 1400.0
      assert PA.m_birthweight_per_liveborn([%{born_alive: 10, total_birth_weight_g: nil}]) == nil
    end
  end

  describe "weaning metrics (pure)" do
    alias Peggy.Reports.PerformanceAnalysis, as: PA

    test "weaning aggregates" do
      ws = [
        %{weaned_count: 11, avg_wean_weight_g: 6500, born_alive: 12, lactation_days: 24, bred_within_7d?: true, sow_id: 1},
        %{weaned_count: 9, avg_wean_weight_g: nil, born_alive: 10, lactation_days: 26, bred_within_7d?: false, sow_id: 1}
      ]
      assert PA.m_count(ws) == 2
      assert PA.m_sum(ws, :weaned_count) == 20
      assert_in_delta PA.m_avg(ws, :weaned_count), 10.0, 0.01
      assert_in_delta PA.m_per_female(ws), 20.0, 0.01   # 20 / 1 distinct sow
      assert_in_delta PA.m_avg(ws, :lactation_days), 25.0, 0.01
      assert_in_delta PA.m_pct_bred_7d(ws), 50.0, 0.1
      assert PA.m_avg_wean_weight(ws) == 6500.0          # only recorded row
    end

    test "net fostered and recorded deaths from litter events" do
      events = [
        %{kind: "foster_in", quantity: 5}, %{kind: "foster_out", quantity: 8}, %{kind: "death", quantity: 3}
      ]
      assert PA.m_net_fostered(events) == -3
      assert PA.m_recorded_deaths(events) == 3
    end
  end

  describe "service metrics (pure)" do
    alias Peggy.Reports.PerformanceAnalysis, as: PA

    test "repeat % and matings" do
      svcs = [
        %{result: nil, classification: :first, mounting_count: 1, service_type: "ai"},
        %{result: nil, classification: :repeat, mounting_count: 2, service_type: "ai"},
        %{result: nil, classification: :first, mounting_count: 1, service_type: "natural"}
      ]
      assert PA.m_total(svcs) == 3
      assert PA.m_count_class(svcs, :repeat) == 1
      assert_in_delta PA.m_pct_repeat(svcs), 33.3, 0.1
      assert PA.m_multiple_matings(svcs) == 1
      assert_in_delta PA.m_matings_per_service(svcs), 1.33, 0.01
      assert PA.m_count_type(svcs, "ai") == 2
      assert_in_delta PA.m_pct_type(svcs, "ai"), 66.7, 0.1
    end

    test "conception + farrowing rate over closed services" do
      svcs = [
        %{result: "farrowing"}, %{result: "farrowing"},
        %{result: "re_service"}, %{result: "abortion"}, %{result: nil}
      ]
      # closed = 4 (nil excluded); not-returned = 3 → 75%
      assert_in_delta PA.m_conception_rate(svcs), 75.0, 0.1
      # farrowing = 2 / 4 closed → 50%
      assert_in_delta PA.m_farrowing_rate(svcs), 50.0, 0.1
    end
  end
end
