defmodule CampfireWeb.BotMessageController do
  @moduledoc """
  The bot API for messages (docs/PORTING.md §5). The message text is the raw request body; a
  multipart `attachment` file posts an attachment instead.
  """
  use CampfireWeb, :controller

  import CampfireWeb.BotAPI

  alias Campfire.Chat
  alias CampfireWeb.BotJSON

  plug :authenticate_bot
  plug :load_room
  plug :load_message, "id" when action in [:update, :delete]

  def index(conn, params) do
    %{bot: bot, room: room} = conn.assigns
    {mode, cursor} = cursor(params)

    {:ok, messages} =
      Chat.page_messages(room.id, if(cursor, do: %{mode => cursor}, else: %{}), actor: bot)

    {:ok, count} = Chat.count_messages(room.id, actor: bot)

    conn
    |> put_resp_header("x-total-count", to_string(count))
    |> put_link_header(mode, messages)
    |> json(Enum.map(messages, &BotJSON.message/1))
  end

  def create(conn, %{"attachment" => %Plug.Upload{} = upload}) do
    with {:ok, key} <- Campfire.Uploads.store(upload.path, upload.filename) do
      %{size: size} = File.stat!(upload.path)

      attrs = %{
        attachment_key: key,
        attachment_filename: upload.filename,
        attachment_content_type:
          Campfire.Uploads.normalize_content_type(upload.content_type) ||
            MIME.from_path(upload.filename),
        attachment_byte_size: size
      }

      case Chat.create_message(conn.assigns.room, attrs, actor: conn.assigns.bot) do
        {:ok, message} ->
          created(conn, message)

        {:error, error} ->
          Campfire.Uploads.delete(key)
          failed(conn, error)
      end
    end
  end

  def create(conn, _params) do
    {body, conn} = raw_body(conn)

    if text?(body) do
      case Chat.create_message(conn.assigns.room, %{body: body}, actor: conn.assigns.bot) do
        {:ok, message} -> created(conn, message)
        {:error, error} -> failed(conn, error)
      end
    else
      error(conn, :unprocessable_entity, "The message body or an attachment is required")
    end
  end

  def update(conn, _params) do
    {body, conn} = raw_body(conn)

    case Chat.update_message(conn.assigns.message, %{body: body}, actor: conn.assigns.bot) do
      {:ok, message} -> json(conn, BotJSON.message(message))
      {:error, error} -> failed(conn, error)
    end
  end

  def delete(conn, _params) do
    case Chat.destroy_message(conn.assigns.message, actor: conn.assigns.bot) do
      :ok -> send_resp(conn, :no_content, "")
      {:error, error} -> failed(conn, error)
    end
  end

  defp created(conn, message) do
    conn
    |> put_status(:created)
    |> json(BotJSON.message(message))
  end

  defp failed(conn, %Ash.Error.Forbidden{}), do: error(conn, :forbidden)

  defp failed(conn, error),
    do: error(conn, :unprocessable_entity, CampfireWeb.ErrorMessages.summary(error))

  defp text?(body), do: String.valid?(body) and not blank?(body)

  defp cursor(%{"after" => id}), do: {:after, parse_id(id)}
  defp cursor(%{"before" => id}), do: {:before, parse_id(id)}
  defp cursor(_params), do: {:before, nil}

  defp parse_id(id) do
    case Integer.parse(to_string(id)) do
      {id, ""} -> id
      _ -> nil
    end
  end

  # `Link: <…?before=first_id>; rel="next"` while older messages exist (`after=last_id` while
  # newer ones exist when paging forward).
  defp put_link_header(conn, _mode, []), do: conn

  defp put_link_header(conn, mode, messages) do
    %{bot: bot, room: room} = conn.assigns
    edge = if mode == :after, do: List.last(messages), else: hd(messages)

    case Chat.page_messages(room.id, %{mode => edge.id}, actor: bot) do
      {:ok, [_ | _]} ->
        url =
          url(~p"/rooms/#{room.id}/#{conn.params["bot_key"]}/messages?#{[{mode, edge.id}]}")

        put_resp_header(conn, "link", ~s(<#{url}>; rel="next"))

      _ ->
        conn
    end
  end
end
