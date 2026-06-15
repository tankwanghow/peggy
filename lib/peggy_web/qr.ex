defmodule PeggyWeb.QR do
  @moduledoc "Renders a URL as an inline SVG QR code."

  @doc "Returns an SVG string (no XML declaration) for embedding with `raw/1`."
  def svg(url, opts \\ []) when is_binary(url) do
    width = Keyword.get(opts, :width, 240)

    url
    |> EQRCode.encode()
    |> EQRCode.svg(width: width, viewbox: true)
  end
end
