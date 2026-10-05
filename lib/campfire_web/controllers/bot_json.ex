defmodule CampfireWeb.BotJSON do
  @moduledoc "JSON shapes of the bot API (docs/PORTING.md §5)."

  alias Campfire.Chat.Message
  alias CampfireWeb.{Endpoint, Paths}

  @doc "A message (with `:creator` loaded)."
  def message(message) do
    %{
      id: message.id,
      created_at: timestamp(message.inserted_at),
      body: %{plain_text: Message.plain_text(message), html: body_html(message)},
      creator: user(message.creator),
      room: %{id: message.room_id},
      url: Endpoint.url() <> Paths.message_path(message)
    }
  end

  @doc "A boost (with `:booster` loaded)."
  def boost(boost, message) do
    %{
      id: boost.id,
      content: boost.content,
      created_at: timestamp(boost.inserted_at),
      booster: user(boost.booster),
      message: %{id: message.id, url: Endpoint.url() <> Paths.message_path(message)}
    }
  end

  defp user(user) do
    %{
      id: user.id,
      name: user.name,
      role: to_string(user.role),
      avatar_url: Endpoint.url() <> Paths.avatar_path(user)
    }
  end

  defp timestamp(datetime) do
    datetime |> DateTime.truncate(:millisecond) |> DateTime.to_iso8601()
  end

  # The message body as HTML. Swap for `CampfireWeb.MessageBody.to_html/1` once it exists.
  defp body_html(%{body: body}) when is_binary(body) and body != "" do
    escaped = body |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
    "<p>" <> String.replace(escaped, "\n", "<br>") <> "</p>"
  end

  defp body_html(_message), do: ""
end
