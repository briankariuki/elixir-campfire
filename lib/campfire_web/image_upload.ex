defmodule CampfireWeb.ImageUpload do
  @moduledoc """
  Stores uploaded images (avatars, logo) with `Campfire.Uploads`, and decides which stored
  images may be served.

  Only raster images are allowed: uploaded files are served from our origin, and SVG or HTML
  can carry scripts. A file is accepted only when **both** its extension and its client content
  type are allowed (LiveView's `accept:` passes when either matches), so the stored key always
  ends in an allowlisted image extension.
  """

  @types %{
    ".png" => "image/png",
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".gif" => "image/gif",
    ".webp" => "image/webp"
  }

  @accept Map.keys(@types)
  @client_types ["image/jpg" | Map.values(@types)]

  @doc "The file extensions accepted for avatars and logos (for `allow_upload/3`)."
  def accept, do: @accept

  @doc """
  Stores a `Plug.Upload` image and returns its key, or nil when there is no (valid) image.
  """
  def store(%Plug.Upload{path: path, filename: filename, content_type: content_type}),
    do: store(path, filename, content_type)

  def store(_upload), do: nil

  @doc """
  Stores the image at `path` and returns its key, or nil unless `filename` and `content_type`
  are both an allowed image. For LiveView entries pass `entry.client_name, entry.client_type`.
  """
  def store(path, filename, content_type) when is_binary(filename) and filename != "" do
    if image?(filename, content_type) do
      case Campfire.Uploads.store(path, filename) do
        {:ok, key} -> key
        _ -> nil
      end
    end
  end

  def store(_path, _filename, _content_type), do: nil

  @doc "Whether both the file extension and the content type are allowed images."
  def image?(filename, content_type) do
    Map.has_key?(@types, extension(filename)) and
      Campfire.Uploads.normalize_content_type(content_type) in @client_types
  end

  @doc "The content type to serve a stored image key with, or nil if it isn't an allowed image."
  def content_type(key) when is_binary(key), do: Map.get(@types, extension(key))
  def content_type(_key), do: nil

  @doc """
  Headers for serving uploaded images: no sniffing, and no scripts even if the file is opened
  directly.
  """
  def put_security_headers(conn) do
    conn
    |> Plug.Conn.put_resp_header("x-content-type-options", "nosniff")
    |> Plug.Conn.put_resp_header(
      "content-security-policy",
      "default-src 'none'; style-src 'unsafe-inline'; sandbox"
    )
  end

  defp extension(filename), do: filename |> to_string() |> Path.extname() |> String.downcase()
end
