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
  end

  defp build_year(scope),
    do: Peggy.Reports.PerformanceAnalysis.build(scope, %{from: ~D[2025-01-01], to: ~D[2025-12-31]})

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
