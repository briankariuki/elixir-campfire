defmodule CampfireWeb.BotBoostController do
  @moduledoc "The bot API for boosts. The boost content is the raw request body."
  use CampfireWeb, :controller

  import CampfireWeb.BotAPI

  alias Campfire.Chat
  alias CampfireWeb.BotJSON

  plug :authenticate_bot
  plug :load_room
  plug :load_message, "message_id"

  def create(conn, _params) do
    {content, conn} = raw_body(conn)
    %{bot: bot, message: message} = conn.assigns

    if String.valid?(content) and not blank?(content) do
      case Chat.create_boost(message, String.trim(content), actor: bot) do
        {:ok, boost} ->
          conn
          |> put_status(:created)
          |> json(BotJSON.boost(boost, message))

        {:error, %Ash.Error.Forbidden{}} ->
          error(conn, :forbidden)

        {:error, error} ->
          error(conn, :unprocessable_entity, CampfireWeb.ErrorMessages.summary(error))
      end
    else
      error(conn, :unprocessable_entity, "The boost content is required")
    end
  end

  def delete(conn, %{"id" => id}) do
    %{bot: bot, message: message} = conn.assigns

    with {:ok, boost} <- Chat.get_boost(id, actor: bot),
         true <- boost.message_id == message.id and boost.booster_id == bot.id,
         :ok <- Chat.destroy_boost(boost, actor: bot) do
      send_resp(conn, :no_content, "")
    else
      _ -> error(conn, :not_found)
    end
  end
end
