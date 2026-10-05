defmodule CampfireWeb.AttachmentController do
  @moduledoc """
  `GET /attachments/:message_id`: serves a message's attachment to members of its room.
  `?download=1` sends it as a download; only images, video and audio are ever shown inline.
  """
  use CampfireWeb, :controller

  alias Campfire.{Chat, Uploads}

  def show(conn, %{"message_id" => id} = params) do
    with {id, ""} <- Integer.parse(id),
         {:ok, %{attachment_key: key} = message} when is_binary(key) <-
           Chat.get_message(id, actor: conn.assigns.current_user),
         true <- Uploads.exists?(key) do
      disposition =
        if params["download"] in ["1", "true"] or not inline?(message.attachment_content_type),
          do: "attachment",
          else: "inline"

      conn
      |> put_resp_content_type(message.attachment_content_type || "application/octet-stream", nil)
      |> put_resp_header("content-disposition", content_disposition(disposition, message))
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("cache-control", "private, max-age=31536000")
      |> send_file(200, Uploads.path(key))
    else
      _ -> conn |> put_status(:not_found) |> text("Not found")
    end
  end

  # Only media is shown inline; anything else (HTML, SVG, ...) could run scripts on our origin
  defp inline?("image/svg" <> _), do: false
  defp inline?("image/" <> _), do: true
  defp inline?("video/" <> _), do: true
  defp inline?("audio/" <> _), do: true
  defp inline?(_), do: false

  defp content_disposition(disposition, message) do
    filename = message.attachment_filename || "attachment"
    ascii = String.replace(filename, ~r/[^A-Za-z0-9.\- _]/, "_")

    ~s(#{disposition}; filename="#{ascii}"; filename*=UTF-8''#{URI.encode(filename, &URI.char_unreserved?/1)})
  end
end
