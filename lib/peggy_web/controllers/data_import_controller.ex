defmodule PeggyWeb.DataImportController do
  @moduledoc """
  Serves header-only CSV templates for the legacy data importer.
  Hit from "Download template" links on the upload step.
  """
  use PeggyWeb, :controller

  @templates %{
    "locations" => "house_code,house_purpose,pen_code,capacity,status,notes\n",
    "sows" => "ear_tag,breed,dob,status,sire_tag,dam_tag,legacy_parity,rfid,notes\n",
    "services" => "sow_ear_tag,served_at,service_type,boar_ear_tag,result,result_at,notes\n",
    "farrowings" =>
      "sow_ear_tag,farrowed_at,born_alive,stillborn,mummified,total_birth_weight_g,pen,notes\n",
    "weanings" => "sow_ear_tag,weaned_at,weaned_count,avg_wean_weight_g,batch_tag,notes\n",
    "culls" => "ear_tag,culled_at,reason,notes\n",
    "movements" => "ear_tag,moved_at,house_code,pen_code,notes\n"
  }

  def template(conn, %{"type" => type}) when is_map_key(@templates, type) do
    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{type}.csv"))
    |> send_resp(200, Map.fetch!(@templates, type))
  end

  def template(conn, _), do: conn |> put_status(:not_found) |> text("Unknown template")
end
