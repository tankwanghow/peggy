defmodule PeggyWeb.ActiveFarm do
  import Plug.Conn
  import Phoenix.Controller
  require PeggyWeb.Gettext

  def require_active_farm(conn, _opts) do
    url_farm_id = String.to_integer(conn.params["farm_id"] || "-1")

    session_farm_id =
      if(get_session(conn, "current_farm"), do: get_session(conn, "current_farm").id, else: -1)

    if session_farm_id != url_farm_id do
      farm = Peggy.Company.get_farm(url_farm_id, conn.assigns.current_user)

      if farm == nil do
        conn
        |> put_flash(:error, PeggyWeb.Gettext.gettext("Not authorise to access farm in the URL."))
        |> redirect(to: "/")
      else
        conn
        |> assign(:current_farm, farm)
        |> put_session(:current_farm, farm)
        |> put_flash(:warning, "#{farm.name} " <> PeggyWeb.Gettext.gettext("is active now."))
      end
    else
      conn
    end
  end
end
