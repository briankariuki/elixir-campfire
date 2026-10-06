defmodule Campfire.Webhooks do
  @moduledoc """
  Delivers new messages to bot webhooks and posts the responses as the bot's replies
  (docs/PORTING.md §5).

  Eligible bots for a message: in a direct room, every active bot member; otherwise the active
  bots mentioned in the message. The message's creator is always excluded.

  Delivery runs as Oban jobs (AshOban trigger `:deliver_webhooks` on `Campfire.Chat.Message`).
  `enqueue_for_message/2` inserts one job per eligible bot, so a slow bot doesn't delay the
  others and each can be retried on its own; the job calls `deliver_to_bot/2`. Retries
  (3 attempts) only happen for connection-level failures. A timeout is answered with the
  "Failed to respond within 7 seconds" reply and completes the job, so it is posted once; other
  failed responses are logged and not retried.

  Replies are created with `deliver_webhooks?: false`, so bots can't loop.

  The payload's `message.body.html` is rendered by the function configured as
  `config :campfire, :message_html, {module, function}` (`CampfireWeb.MessageBody.to_html_string/1`),
  so it matches the bot API's html without this module depending on the web layer.
  """

  require Ash.Query
  require Logger

  alias Campfire.Accounts.User
  alias Campfire.Chat.Mentions
  alias Campfire.Chat.Message
  alias Campfire.Uploads

  @timeout 7_000
  @timeout_reply "Failed to respond within 7 seconds"

  @doc """
  Enqueues a delivery job for every eligible bot's webhook. Call after the message committed.
  """
  def enqueue_for_message(%Message{} = message, room) do
    for bot <- eligible_bots(message, room), bot.webhook do
      AshOban.run_trigger(message, :deliver_webhooks, action_arguments: %{bot_id: bot.id})
    end

    :ok
  end

  @doc """
  The body of a delivery job: delivers `message` to the webhook of the bot with `bot_id`.

  Returns `:ok`, or `{:error, exception}` for a failure worth retrying. A bot that was
  deactivated or lost its webhook since the job was enqueued is skipped.
  """
  def deliver_to_bot(%Message{} = message, bot_id) do
    # System work after a message was created by someone else: load what the payload needs.
    message = Ash.load!(message, [:creator, :room], authorize?: false)

    case Ash.get(User, bot_id, load: :webhook, authorize?: false, not_found_error?: false) do
      {:ok, %User{role: :bot, status: :active, webhook: %{url: url}} = bot} ->
        deliver(bot, url, message, message.room)

      _ ->
        :ok
    end
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

  @doc false
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

      # The request probably never reached the bot (refused, DNS, closed): let Oban retry.
      {:error, %Req.TransportError{} = error} ->
        Logger.warning("Webhook for bot #{bot.id} failed: #{Exception.message(error)}")
        {:error, error}

      {:error, error} ->
        Logger.warning("Webhook for bot #{bot.id} failed: #{Exception.message(error)}")
        :ok
    end
  end

  @doc "The JSON payload sent to a bot's webhook."
  def payload(bot, message, room) do
    plain =
      message
      |> Message.plain_text()
      |> then(&Regex.replace(Mentions.mention_regex(bot.name), &1, ""))
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
        body: %{html: body_html(message), plain: plain},
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

        # Dimensions and a thumbnail for raster images (best effort)
        image = Uploads.Image.attributes(Uploads.path(key), mime)

        reply(
          bot,
          room,
          Map.merge(image, %{
            attachment_key: key,
            attachment_filename: filename,
            attachment_content_type: if(mime == "", do: "application/octet-stream", else: mime),
            attachment_byte_size: byte_size(body)
          })
        )

      true ->
        :ok
    end
  end

  # A failed reply is logged, not retried: retrying would deliver to the bot again.
  defp reply(bot, room, attrs) do
    Message
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(attrs, %{room: room, deliver_webhooks?: false}),
      actor: bot,
      authorize?: false
    )
    |> Ash.create(authorize?: false)
    |> case do
      {:ok, _message} ->
        :ok

      {:error, error} ->
        Logger.error("Reply for bot #{bot.id} failed: #{Exception.message(error)}")
        :ok
    end
  end

  # The same HTML as the bot API's `body.html`. Rendering lives in the web layer
  # (`CampfireWeb.MessageBody`, it knows the avatar and profile routes); the domain doesn't depend on
  # it, so the renderer is wired in config as `{module, function}` and called with the message.
  defp body_html(message) do
    {module, function} = Application.fetch_env!(:campfire, :message_html)
    apply(module, function, [message])
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
