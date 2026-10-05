defmodule CampfireWeb.ImageUpload do
  @moduledoc "Stores uploaded images (avatars, logo) with `Campfire.Uploads`."

  # No SVG: uploaded files are served from our origin, and SVGs can carry scripts.
  @accept ~w(.jpg .jpeg .png .gif .webp)

  @doc "The file extensions accepted for avatars and logos (for `allow_upload/3`)."
  def accept, do: @accept

  @doc """
  Stores a `Plug.Upload` image and returns its key, or nil when there is no (valid) image.
  """
  def store(%Plug.Upload{path: path, filename: filename, content_type: content_type})
      when is_binary(filename) and filename != "" do
    if image?(filename, content_type) do
      case Campfire.Uploads.store(path, filename) do
        {:ok, key} -> key
        _ -> nil
      end
    end
  end

  def store(_upload), do: nil

  defp image?(filename, content_type) do
    String.downcase(Path.extname(filename)) in @accept and
      String.starts_with?(content_type || "", "image/")
  end
end
