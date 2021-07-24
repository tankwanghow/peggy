defmodule PeggyWeb.SetActiveFarmController do
  use PeggyWeb, :controller

  alias Peggy.Company

  def new(conn, _params) do
    conn =
      conn
      |> assign(:current_farm, nil)
      |> put_session(:current_farm, nil)

    render(conn, "index.html",
      farms: Company.list_farms(conn.assigns.current_user),
      page_title: gettext("Please select an active farm.")
    )
  end

  def index(conn, _params) do
    render(conn, "index.html",
      page_title: gettext("Please select an active farm."),
      farms: Company.list_farms(conn.assigns.current_user)
    )
  end

  def create(conn, %{"id" => id}) do
    conn =
      conn
      |> assign(:current_farm, Company.get_farm!(id, conn.assigns.current_user))

    conn
    |> put_session(:current_farm, conn.assigns.current_farm)
    |> put_flash(:warning, "#{conn.assigns.current_farm.name} " <> gettext("is active now."))
    |> redirect(to: "/navigation")
  end
end
