defmodule PeggyWeb.PageController do
  use PeggyWeb, :controller

  def home(conn, _params) do
    case conn.assigns[:current_scope] do
      %Peggy.Accounts.Scope{user: %Peggy.Accounts.User{} = user} ->
        Phoenix.Controller.redirect(conn, to: PeggyWeb.UserAuth.default_farm_path(user))

      _ ->
        if PeggyWeb.Device.mobile?(conn) do
          render(conn, :home_mobile)
        else
          render(conn, :home)
        end
    end
  end
end
