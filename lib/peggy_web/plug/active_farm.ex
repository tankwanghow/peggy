defmodule PeggyWeb.ActiveFarm do
  import Plug.Conn
  import Phoenix.Controller
  require PeggyWeb.Gettext

  def require_active_farm(conn, _opts) do
    url_farm_id = String.to_integer(conn.params["farm_id"] || "-1")

    session_farm_id = Util.attempt(get_session(conn, "current_farm_user"), :farm_id) || -1

    if session_farm_id != url_farm_id do
      farm_user = Peggy.Company.get_farm_user(url_farm_id, conn.assigns.current_user.id)

      if farm_user == nil do
        conn
        |> put_flash(:error, PeggyWeb.Gettext.gettext("Not authorise to access farm in the URL."))
        |> redirect(to: "/")
        |> halt()
      else
        conn
        |> assign(:current_farm_user, farm_user)
        |> put_session(:current_farm_user, farm_user)
        |> put_flash(
          :warning,
          "#{farm_user.farm.name} " <> PeggyWeb.Gettext.gettext("is active now.")
        )
      end
    else
      conn
    end
  end
end
