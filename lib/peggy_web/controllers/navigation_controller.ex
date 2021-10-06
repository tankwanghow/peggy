defmodule PeggyWeb.NavigationController do
  use PeggyWeb, :controller

  def index(conn, _params) do
    conn
    |> assign(:page_title, gettext("Navigation Page"))
    |> assign(:current_farm, get_session(conn, :current_farm))
    |> render("index.html")
  end
end
