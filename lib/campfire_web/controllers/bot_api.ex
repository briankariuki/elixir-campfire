defmodule CampfireWeb.BotAPI do
  @moduledoc """
  Plugs and helpers shared by the bot API controllers (`/rooms/:room_id/:bot_key/...`).

    * `authenticate_bot` assigns `:bot` (401 for a bad key)
    * `load_room` assigns `:room` (404 unless the bot is a member)
    * `load_message` assigns `:message` from `param` (404 unless it's in that room)
  """
  import Plug.Conn
  import Phoenix.Controller

  alias Campfire.{Accounts, Chat}
  alias Campfire.Accounts.User

  def authenticate_bot(conn, _opts) do
    case Accounts.authenticate_bot(to_string(conn.params["bot_key"])) do
      {:ok, %User{} = bot} -> assign(conn, :bot, bot)
      _ -> conn |> error(:unauthorized) |> halt()
    end
  end

  def load_room(conn, _opts) do
    case Chat.get_room(conn.params["room_id"], actor: conn.assigns.bot) do
      {:ok, room} -> assign(conn, :room, room)
      _ -> conn |> error(:not_found) |> halt()
    end
  end

  def load_message(conn, param) do
    with id when is_binary(id) <- conn.params[param],
         {:ok, message} <- Chat.get_message(id, actor: conn.assigns.bot, load: [:creator]),
         true <- message.room_id == conn.assigns.room.id do
      assign(conn, :message, message)
    else
      _ -> conn |> error(:not_found) |> halt()
    end
  end

  @doc "Sends `{\"error\": message}` with `status`."
  def error(conn, status, message \\ nil) do
    conn
    |> put_status(status)
    |> json(%{error: message || Plug.Conn.Status.reason_phrase(Plug.Conn.Status.code(status))})
  end

  @doc """
  The raw request body: cached by `CampfireWeb.CacheBodyReader` for form posts, read here for
  other content types (e.g. `text/plain`). Multipart bodies have no raw text.
  """
  def raw_body(conn) do
    case conn.assigns[:raw_body] do
      nil ->
        case read_body(conn) do
          {:ok, body, conn} -> {body, conn}
          _ -> {"", conn}
        end

      body ->
        {body, conn}
    end
  end

  @doc "Whether a raw body is blank (whitespace only)."
  def blank?(body), do: String.trim(body) == ""
end
