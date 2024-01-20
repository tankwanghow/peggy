defmodule PeggyWeb.ActiveFarm do
  use PeggyWeb, :verified_routes
  import Plug.Conn
  import Phoenix.Controller
  require PeggyWeb.Gettext

  def on_mount(:assign_active_farm, _params, session, socket) do
    {:cont,
     socket
     |> Phoenix.Component.assign(:current_farm, session["current_farm"])
     |> Phoenix.Component.assign(:current_role, session["current_role"])}
  end

  def set_active_farm(%{params: %{"farm_id" => url_farm_id}} = conn, _opts) do
    session_farm_id = Util.attempt(get_session(conn, "current_farm"), :id) || -1

    if session_farm_id != url_farm_id do
      if conn.assigns.current_user do
        cu = Peggy.Sys.get_farm_user(url_farm_id, conn.assigns.current_user.id)

        if cu != nil do
          c = Peggy.Sys.get_farm!(cu.farm_id)

          conn
          |> put_session(:current_role, cu.role)
          |> put_session(:current_farm, c)
          |> assign(:current_role, cu.role)
          |> assign(:current_farm, c)
        else
          conn
          |> put_flash(:error, PeggyWeb.Gettext.gettext("Not Authorise."))
          |> redirect(to: "/")
          |> halt()
        end
      else
        conn
      end
    else
      conn
    end
  end

  def set_active_farm(conn, _opts) do
    conn
    |> assign(:current_role, get_session(conn, "current_role"))
    |> assign(:current_farm, get_session(conn, "current_farm"))
  end
end
