defmodule PeggyWeb.SetActiveFarmController do
  use PeggyWeb, :controller
  import Phoenix.LiveView.Controller

  alias Peggy.Company

  def new(conn, _params) do
    conn
    |> assign(:current_farm, nil)
    |> put_session(:current_farm, nil)
    |> put_session(:page_title, gettext("Please select an active farm."))
    |> live_render(PeggyWeb.FarmLive.Index)
  end

  def update(conn, %{"id" => id}) do
    conn
    |> set_active_farm(id)
    |> put_flash(:success, gettext("Farm updated successfully"))
    |> live_render(PeggyWeb.FarmLive.Index)
  end

  def create(conn, %{"id" => id}) do
    conn = set_active_farm(conn, id)
    conn
    |> put_flash(:warning, "#{conn.assigns.current_farm.name} " <> gettext("is active now."))
    |> live_render(PeggyWeb.FarmLive.Index)
  end

  defp set_active_farm(conn, id) do
    farm = Company.get_farm(id, conn.assigns.current_user)

    conn
    |> assign(:current_farm, farm)
    |> put_session(:current_farm, farm)
  end
end
