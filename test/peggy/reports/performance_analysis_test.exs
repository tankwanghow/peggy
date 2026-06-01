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
end
