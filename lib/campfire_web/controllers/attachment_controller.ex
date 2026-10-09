defmodule CampfireWeb.AttachmentController do
  @moduledoc """
  `GET /attachments/:message_id`: serves a message's attachment to members of its room.
  `?download=1` sends it as a download; only allowlisted images, video and audio are shown inline.
  `?thumb=1` serves the image's downscaled thumbnail instead, when it has one (else the original);
  a download is always the original.
  """
  use CampfireWeb, :controller

  alias Campfire.{Chat, Uploads}

  # Only these media types are shown inline (and served with their own content type). Anything
  # else (HTML, SVG, ...) could run scripts on our origin, so it is a download of
  # application/octet-stream.
  @inline_types ~w(image/png image/jpeg image/gif image/webp video/mp4 video/webm video/quicktime
                   audio/mpeg audio/mp4 audio/ogg audio/wav audio/webm)

  def show(conn, %{"message_id" => id} = params) do
    with {id, ""} <- Integer.parse(id),
         {:ok, %{attachment_key: key} = message} when is_binary(key) <-
           Chat.get_message(id, actor: conn.assigns.current_user),
         true <- Uploads.exists?(key) do
      content_type = Uploads.normalize_content_type(message.attachment_content_type)
      inline? = inline_type?(content_type)
      download? = params["download"] in ["1", "true"]
      disposition = if download? or not inline?, do: "attachment", else: "inline"

      file_key =
        if params["thumb"] in ["1", "true"] and inline? and not download?,
          do: thumbnail_key(message, content_type) || key,
          else: key

      conn
      |> put_resp_content_type(
        if(inline?, do: content_type, else: "application/octet-stream"),
        nil
      )
      |> put_resp_header("content-disposition", content_disposition(disposition, message))
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("content-security-policy", "sandbox")
      |> put_resp_header("cache-control", "private, max-age=31536000")
      |> send_file(200, Uploads.path(file_key))
    else
      _ -> conn |> put_status(:not_found) |> text("Not found")
    end
  end

  # The thumbnail has the original's format; only raster images ever get one.
  defp thumbnail_key(%{attachment_thumbnail_key: key}, content_type) when is_binary(key) do
    if content_type in ~w(image/png image/jpeg image/webp) and Uploads.exists?(key), do: key
  end

  defp thumbnail_key(_message, _content_type), do: nil

  @doc "Whether a (normalized) content type is shown inline rather than downloaded."
  def inline_type?(content_type), do: content_type in @inline_types

  defp content_disposition(disposition, message) do
    filename = message.attachment_filename || "attachment"
    ascii = String.replace(filename, ~r/[^A-Za-z0-9.\- _]/, "_")

    ~s(#{disposition}; filename="#{ascii}"; filename*=UTF-8''#{URI.encode(filename, &URI.char_unreserved?/1)})
  end
end
