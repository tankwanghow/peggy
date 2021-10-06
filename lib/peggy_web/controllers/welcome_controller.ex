defmodule PeggyWeb.WelcomeController do
  use PeggyWeb, :controller
  
  def index(conn, _params) do
    conn
    |> assign(:page_title, gettext("Peggy Welcome Page"))
    |> render("index.html")
  end

end
