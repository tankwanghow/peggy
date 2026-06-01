defmodule Peggy.Reports.PerformanceAnalysis do
  @moduledoc """
  Builds the Porcitec-style Performance Analysis matrix (Service /
  Farrowing / Weaning sections) for a date range, broken into calendar
  months plus an ACUM (whole-range) column. See
  `docs/superpowers/specs/2026-06-01-performance-analysis-report-design.md`.
  """

  @doc "Calendar-month buckets intersecting `[from, to]`, partial months clipped."
  def calendar_months(%Date{} = from, %Date{} = to) do
    from
    |> Date.beginning_of_month()
    |> Stream.iterate(fn d -> d |> Date.end_of_month() |> Date.add(1) end)
    |> Enum.take_while(fn d -> Date.compare(d, to) != :gt end)
    |> Enum.map(fn month_start ->
      p_from = later(month_start, from)
      p_to = earlier(Date.end_of_month(month_start), to)
      %{label: Calendar.strftime(p_from, "%d-%m-%y"), from: p_from, to: p_to}
    end)
  end

  defp later(a, b), do: if(Date.compare(a, b) == :lt, do: b, else: a)
  defp earlier(a, b), do: if(Date.compare(a, b) == :gt, do: b, else: a)
end
