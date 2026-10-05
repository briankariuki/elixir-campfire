defmodule Campfire.Webhooks do
  @moduledoc """
  Delivers new messages to bot webhooks and posts the responses as the bot's replies
  (docs/PORTING.md §5).

  Eligible bots for a message: in a direct room, every active bot member; otherwise the active
  bots mentioned in the message. The message's creator is always excluded. Each delivery runs
  through `Campfire.Async` (a `Campfire.TaskSupervisor` child, or inline in tests).

  Replies are created with `deliver_webhooks?: false`, so bots can't loop.
  """

  require Ash.Query
  require Logger

  alias Campfire.Accounts.User
  alias Campfire.Chat.{Message, Room}
  alias Campfire.{Async, Uploads}

  @timeout 7_000
  @timeout_reply "Failed to respond within 7 seconds"

  @doc "Delivers the message to every eligible bot's webhook."
  def deliver_for_message(%Message{} = message, room \\ nil) do
    room = room || Ash.get!(Room, message.room_id, authorize?: false)
    message = Ash.load!(message, [:creator], authorize?: false)

    for bot <- eligible_bots(message, room), bot.webhook do
      Async.run(fn -> deliver(bot, bot.webhook.url, message, room) end)
    end

    :ok
  end

  @doc false
  def eligible_bots(message, room) do
    query =
      if room.kind == :direct do
        room_id = room.id
        Ash.Query.filter(User, exists(memberships, room_id == ^room_id))
      else
        ids = message.mentioned_user_ids
        Ash.Query.filter(User, id in ^ids)
      end

    creator_id = message.creator_id

    query
    |> Ash.Query.filter(role == :bot and status == :active and id != ^creator_id)
    |> Ash.Query.load(:webhook)
    |> Ash.read!(authorize?: false)
  end

  @doc "POSTs the payload to `url` and handles the response. Runs synchronously."
  def deliver(bot, url, message, room) do
    options =
      [
        json: payload(bot, message, room),
        receive_timeout: @timeout,
        connect_options: [timeout: @timeout],
        retry: false,
        decode_body: false
      ] ++ Application.get_env(:campfire, :webhook_req_options, [])

    case Req.post(url, options) do
      {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
        handle_response(bot, room, response)

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("Webhook for bot #{bot.id} responded with #{status}")
        :ok

      {:error, %Req.TransportError{reason: :timeout}} ->
        reply(bot, room, %{body: @timeout_reply})

      {:error, error} ->
        Logger.warning("Webhook for bot #{bot.id} failed: #{Exception.message(error)}")
        :ok
    end
  rescue
    error ->
      Logger.error(
        "Webhook for bot #{bot.id} crashed: " <> Exception.format(:error, error, __STACKTRACE__)
      )

      :error
  end

  @doc "The JSON payload sent to a bot's webhook."
  def payload(bot, message, room) do
    plain =
      message
      |> Message.plain_text()
      |> String.replace("@#{bot.name}", "")
      |> String.trim()

    %{
      user: %{id: message.creator.id, name: message.creator.name},
      room: %{
        id: room.id,
        name: room.name,
        path: "/rooms/#{room.id}/#{User.bot_key(bot)}/messages"
      },
      message: %{
        id: message.id,
        body: %{html: simple_html(Message.plain_text(message)), plain: plain},
        path: "/rooms/#{room.id}/@#{message.id}"
      }
    }
  end

  defp handle_response(bot, room, response) do
    mime =
      response
      |> Req.Response.get_header("content-type")
      |> List.first("")
      |> String.split(";")
      |> hd()
      |> String.trim()
      |> String.downcase()

    body = IO.iodata_to_binary(response.body || "")

    cond do
      mime in ["text/plain", "text/html"] ->
        text = if mime == "text/html", do: html_to_text(body), else: body

        if String.trim(text) != "", do: reply(bot, room, %{body: text}), else: :ok

      body != "" ->
        ext = if mime == "", do: "bin", else: mime |> MIME.extensions() |> List.first("bin")
        filename = "attachment.#{ext}"
        {:ok, key} = Uploads.store_binary(body, filename)

        reply(bot, room, %{
          attachment_key: key,
          attachment_filename: filename,
          attachment_content_type: if(mime == "", do: "application/octet-stream", else: mime),
          attachment_byte_size: byte_size(body)
        })

      true ->
        :ok
    end
  end

  defp reply(bot, room, attrs) do
    Message
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(attrs, %{room: room, deliver_webhooks?: false}),
      actor: bot,
      authorize?: false
    )
    |> Ash.create(authorize?: false)
  end

  defp simple_html(text) do
    html =
      text
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()
      |> String.replace("\n", "<br>")

    "<p>#{html}</p>"
  end

  defp html_to_text(html) do
    html
    |> String.replace(~r/<br\s*\/?>|<\/p>|<\/div>/i, "\n")
    |> String.replace(~r/<[^>]*>/, "")
    |> String.replace("&nbsp;", " ")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&amp;", "&")
    |> String.trim()
  end
end
