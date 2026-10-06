defmodule Campfire.Uploads.Image do
  @moduledoc """
  Image metadata and thumbnails for message attachments (libvips, through Vix).

  For the raster types the attachment controller serves inline (PNG, JPEG, GIF, WebP; never SVG)
  `attributes/2` reads the pixel dimensions and, when the image is larger than
  1200x800 (the original Campfire's `THUMBNAIL_MAX_WIDTH`/`THUMBNAIL_MAX_HEIGHT`), stores a
  downscaled copy with its own upload key, in the same format and without metadata. The result is a
  map of `Message` attributes to merge into the create params.

  Processing is best effort: anything that goes wrong is logged and yields no (or fewer)
  attributes, so an upload never fails because of it.
  """

  alias Campfire.Uploads
  alias Vix.Vips.Operation
  alias Vix.Vips.Image, as: VipsImage

  require Logger

  @max_width 1200
  @max_height 800
  # Larger images are not decoded for a thumbnail (decompression bombs).
  @max_pixels 100_000_000
  @quality 82

  # content type => {extension, libvips save suffix}; nil: dimensions only (GIFs may be animated)
  @formats %{
    "image/png" => {".png", ".png[strip]"},
    "image/jpeg" => {".jpg", ".jpg[Q=#{@quality},strip]"},
    "image/webp" => {".webp", ".webp[Q=#{@quality},strip]"},
    "image/gif" => nil
  }
  # Only these libvips loaders may touch an upload, whatever its claimed type (no SVG, PDF, ...)
  @loaders ~w(pngload jpegload webpload gifload)

  @doc "The thumbnail size limit as `{max_width, max_height}`."
  def thumbnail_limits, do: {@max_width, @max_height}

  @doc """
  The dimensions an image is displayed at: the image itself, scaled down to fit the thumbnail
  limits (`Messages::AttachmentPresentation#preview_dimensions`). `nil` without both dimensions.
  """
  @spec preview_dimensions(integer() | nil, integer() | nil) ::
          {pos_integer(), pos_integer()} | nil
  def preview_dimensions(width, height)
      when is_integer(width) and is_integer(height) and width > 0 and height > 0 do
    scale = Enum.min([@max_width / width, @max_height / height, 1.0])
    {max(round(width * scale), 1), max(round(height * scale), 1)}
  end

  def preview_dimensions(_width, _height), do: nil

  @doc """
  `Message` attributes (`:attachment_width`, `:attachment_height`, `:attachment_thumbnail_key`)
  for the image at `path`, or `%{}` when it is not a supported raster image or can't be processed.
  """
  @spec attributes(Path.t(), String.t() | nil) :: map()
  def attributes(path, content_type) do
    case Map.fetch(@formats, Uploads.normalize_content_type(content_type)) do
      {:ok, format} -> process(path, format)
      :error -> %{}
    end
  rescue
    error ->
      Logger.warning("Attachment image processing failed: #{Exception.message(error)}")
      %{}
  end

  defp process(path, format) do
    with {:ok, image} <- VipsImage.new_from_file(path),
         :ok <- check_loader(image) do
      {width, height} = display_dimensions(image)

      %{attachment_width: width, attachment_height: height}
      |> Map.merge(thumbnail_attributes(path, image, format, width, height))
    else
      error ->
        Logger.warning("Attachment image could not be read: #{inspect(error)}")
        %{}
    end
  end

  defp check_loader(image) do
    case VipsImage.header_value(image, "vips-loader") do
      {:ok, loader} when is_binary(loader) ->
        if Enum.any?(@loaders, &String.starts_with?(loader, &1)), do: :ok, else: {:error, loader}

      other ->
        {:error, other}
    end
  end

  # Headers don't include the EXIF orientation: 5 to 8 are the transposed/rotated-by-90 cases,
  # which browsers (and `thumbnail`) display with width and height swapped.
  defp display_dimensions(image) do
    width = VipsImage.width(image)
    height = VipsImage.height(image)

    case VipsImage.header_value(image, "orientation") do
      {:ok, orientation} when orientation in 5..8 -> {height, width}
      _ -> {width, height}
    end
  end

  defp thumbnail_attributes(_path, _image, nil, _width, _height), do: %{}

  defp thumbnail_attributes(path, image, {ext, suffix}, width, height) do
    if (width > @max_width or height > @max_height) and width * height <= @max_pixels and
         not multi_page?(image) do
      case store_thumbnail(path, ext, suffix) do
        {:ok, key} -> %{attachment_thumbnail_key: key}
        _ -> %{}
      end
    else
      %{}
    end
  end

  defp multi_page?(image) do
    match?(
      {:ok, pages} when is_integer(pages) and pages > 1,
      VipsImage.header_value(image, "n-pages")
    )
  end

  defp store_thumbnail(path, ext, suffix) do
    with {:ok, thumbnail} <-
           Operation.thumbnail(path, @max_width, height: @max_height, size: :VIPS_SIZE_DOWN),
         {:ok, binary} <- VipsImage.write_to_buffer(thumbnail, suffix),
         # A thumbnail that isn't smaller than an already optimised original is no use
         true <- byte_size(binary) < File.stat!(path).size do
      Uploads.store_binary(binary, "thumbnail" <> ext)
    else
      error ->
        Logger.warning("Attachment thumbnail failed: #{inspect(error)}")
        :error
    end
  end
end
