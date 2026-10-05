defmodule CampfireWeb.CacheBodyReader do
  @moduledoc """
  A `Plug.Parsers` body reader that keeps the raw request body in `conn.assigns[:raw_body]`.

  The bot API takes the message text as the raw body (`curl -d 'Hello!' …`, sent as
  `application/x-www-form-urlencoded`). For bot API requests the parser is handed an empty body,
  so text such as `"100% done"` isn't decoded as (invalid) form params.
  """

  def read_body(conn, opts) do
    if bot_api?(conn), do: read_and_cache(conn, opts), else: Plug.Conn.read_body(conn, opts)
  end

  defp read_and_cache(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} -> {:ok, "", cache(conn, body)}
      {:more, body, conn} -> {:more, "", cache(conn, body)}
      error -> error
    end
  end

  @doc "Whether the request goes to the bot API (`/rooms/:room_id/:bot_key/messages…`)."
  def bot_api?(%Plug.Conn{path_info: ["rooms", _room_id, _bot_key, "messages" | _]}), do: true
  def bot_api?(_conn), do: false

  defp cache(conn, body) do
    Plug.Conn.assign(conn, :raw_body, (conn.assigns[:raw_body] || "") <> body)
  end
end
