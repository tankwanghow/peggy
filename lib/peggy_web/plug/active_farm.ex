defmodule PeggyWeb.ActiveFarm do
  import Plug.Conn, only: [put_session: 3, get_session: 2, assign: 3]
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{params: %{"current_farm" => farm}} = conn, _opts) do
    set_current_farm(conn, farm)
  end

  def call(conn, _opts) do
    case get_session(conn, "current_farm") do
      nil ->
        set_current_farm(conn, nil)
      farm ->
        set_current_farm(conn, farm)
    end
  end

  defp set_current_farm(conn, farm) do
    conn
    |> put_session(:current_farm, farm)
    |> assign(:current_farm, farm)
  end
end
