defmodule PeggyWeb.ActiveFarmController do
  use PeggyWeb, :controller

  def create(conn, %{"id" => id}) do
    c = Peggy.Sys.get_farm!(id)

    conn
    |> put_session(:current_farm, c)
    |> redirect(to: ~p"/farms")
  end

  def delete(conn, _) do
    conn
    |> put_session(:current_farm, nil)
    |> redirect(to: ~p"/farms")
  end
end
