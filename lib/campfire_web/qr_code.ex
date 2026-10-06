defmodule CampfireWeb.QRCode do
  @moduledoc """
  QR codes for the join link and the session transfer link (the original's `QrCodeController`).

  `EQRCode` encodes the text into a module matrix; the SVG is serialised here as one `<path>` of
  horizontal runs (EQRCode's own `svg/2` emits one `<rect>` per module, ~80 KB for a join URL).
  `data_uri/1` wraps it as a base64 `data:` URI, which is what the lightbox shows: the markup is
  safe to put in an attribute and needs no `raw/1`.
  """

  @extra_quiet_zone 2

  @doc "A black-on-white SVG of `text` (with a 4-module quiet zone), as a string."
  @spec svg(String.t()) :: String.t()
  def svg(text) when is_binary(text) do
    %EQRCode.Matrix{matrix: rows} = matrix = EQRCode.encode(text)
    size = EQRCode.Matrix.size(matrix)

    path =
      rows
      |> Tuple.to_list()
      |> Enum.with_index()
      |> Enum.map_join(fn {row, y} -> row_path(Tuple.to_list(row), y) end)

    # EQRCode adds a 2-module quiet zone; the spec asks for 4, so pad by 2 more on every side.
    full = size + 2 * @extra_quiet_zone
    origin = -@extra_quiet_zone

    ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="#{origin} #{origin} #{full} #{full}" ) <>
      ~s(width="600" height="600" shape-rendering="crispEdges">) <>
      ~s(<rect x="#{origin}" y="#{origin}" width="#{full}" height="#{full}" fill="#fff"/>) <>
      ~s(<path d="#{path}" fill="#000"/></svg>)
  end

  @doc "The QR code of `text` as a `data:image/svg+xml;base64,…` URI."
  @spec data_uri(String.t()) :: String.t()
  def data_uri(text), do: "data:image/svg+xml;base64," <> Base.encode64(svg(text))

  # `M x y h<run> v1 h-<run> z` for every run of dark modules in the row.
  defp row_path(modules, y) do
    modules
    |> Enum.with_index()
    |> Enum.chunk_by(fn {module, _x} -> module == 1 end)
    |> Enum.filter(fn [{module, _x} | _] -> module == 1 end)
    |> Enum.map_join(fn [{_, x} | _] = run ->
      len = length(run)
      "M#{x} #{y}h#{len}v1h-#{len}z"
    end)
  end
end
