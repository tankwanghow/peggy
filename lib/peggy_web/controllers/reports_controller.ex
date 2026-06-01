defmodule PeggyWeb.ReportsController do
  @moduledoc """
  Streams CSV exports of breeding data within a date range. Used as
  the "download" affordance from the Reports LiveView.
  """
  use PeggyWeb, :controller

  alias Peggy.{Farms, Reports}
  alias Peggy.Accounts.Scope

  @types ~w(services farrowings weanings performance)

  def export(conn, %{"farm_slug" => slug, "type" => type} = params) when type in @types do
    base_scope = conn.assigns.current_scope

    case load_farm_scope(base_scope, slug) do
      {:ok, scope} ->
        if Peggy.Policy.can?(scope, :view_reports) do
          range = parse_range(params, scope)
          csv = build_csv(scope, type, range)
          filename = "#{slug}-#{type}-#{range.from}-to-#{range.to}.csv"

          conn
          |> put_resp_content_type("text/csv")
          |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
          |> send_resp(200, IO.iodata_to_binary(csv))
        else
          conn |> put_status(:forbidden) |> text("Forbidden")
        end

      :error ->
        conn |> put_status(:not_found) |> text("Farm not found")
    end
  end

  def export(conn, _), do: conn |> put_status(:bad_request) |> text("Bad request")

  defp load_farm_scope(%Scope{user: nil}, _slug), do: :error

  defp load_farm_scope(%Scope{user: user} = scope, slug) do
    case Farms.get_farm_by_slug(slug) do
      nil ->
        :error

      farm ->
        case Farms.get_membership(user, farm) do
          nil -> :error
          membership -> {:ok, Scope.put_farm(scope, farm, membership)}
        end
    end
  end

  defp build_csv(scope, "services", range), do: Reports.services_csv(scope, range)
  defp build_csv(scope, "farrowings", range), do: Reports.farrowings_csv(scope, range)
  defp build_csv(scope, "weanings", range), do: Reports.weanings_csv(scope, range)
  defp build_csv(scope, "performance", range), do: Reports.performance_analysis_csv(scope, range)

  defp parse_range(params, scope) do
    %{from: Reports.default_range(scope).from, to: Reports.default_range(scope).to}
    |> Map.put(:from, parse_date(params["from"]) || Reports.default_range(scope).from)
    |> Map.put(:to, parse_date(params["to"]) || Reports.default_range(scope).to)
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(s) when is_binary(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> d
      _ -> nil
    end
  end
end
