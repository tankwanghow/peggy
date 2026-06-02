defmodule PeggyWeb.Device do
  @moduledoc """
  Device detection (mobile vs desktop) for routing and template choice.
  The explicit `peggy_view` cookie wins; otherwise we sniff the user-agent.
  """
  import Plug.Conn

  @mobile_ua ~r/Mobile|Android|iPhone|iPod|Opera Mini|IEMobile/i

  @doc "True when the request should render the mobile UI."
  def mobile?(conn) do
    conn = fetch_cookies(conn)

    case conn.cookies["peggy_view"] do
      "mobile" -> true
      "desktop" -> false
      _ -> mobile_ua?(conn)
    end
  end

  @doc "True when the user-agent header looks like a mobile device."
  def mobile_ua?(conn) do
    ua = conn |> get_req_header("user-agent") |> List.first() |> Kernel.||("")
    String.match?(ua, @mobile_ua)
  end
end
