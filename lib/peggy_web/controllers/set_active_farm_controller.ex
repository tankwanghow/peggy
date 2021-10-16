defmodule PeggyWeb.SetActiveFarmController do
  use PeggyWeb, :controller
  import Phoenix.LiveView.Controller

  alias Peggy.Company

  def new(conn, _params) do
    conn
    |> assign(:current_farm_user, nil)
    |> put_session(:current_farm_user, nil)
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
    |> put_flash(:warning, "#{conn.assigns.current_farm_user.farm.name} " <> gettext("is active now."))
    |> redirect(to: "/farms/#{id}/navigation")
  end

  defp set_active_farm(conn, farm_id) do
    farm_user = Company.get_farm_user(farm_id, conn.assigns.current_user.id)

    conn
    |> assign(:current_farm_user, farm_user)
    |> put_session(:current_farm_user, farm_user)
  end
end
