defmodule PeggyWeb.ActiveFarm do
  import Plug.Conn
  import Phoenix.Controller

  def require_active_farm(conn, _opts) do
    farm_id = String.to_integer(conn.params["farm_id"] || "-1")

    current_farm_id =
      if get_session(conn, "current_farm") do
        get_session(conn, "current_farm").id
      else
        -1
      end

    if farm_id != current_farm_id do
      set_current_farm(conn, farm_id)
    else
      conn
    end
  end

  defp set_current_farm(conn, farm_id) do
    require PeggyWeb.Gettext

    try do
      farm = Peggy.Company.get_farm!(farm_id, conn.assigns.current_user)

      conn
      |> assign(:current_farm, farm)
      |> put_session(:current_farm, farm)
      |> put_flash(:warning, "#{farm.name} " <> PeggyWeb.Gettext.gettext("is active now."))
    rescue
      Ecto.NoResultsError ->
        conn
        |> put_flash(:error, PeggyWeb.Gettext.gettext("Not authorise to access."))
    end
  end
end
