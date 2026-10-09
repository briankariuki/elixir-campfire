defmodule Campfire.UploadsImageTest do
  use ExUnit.Case, async: true

  alias Campfire.Uploads
  alias Campfire.Uploads.Image
  alias Vix.Vips.Image, as: VipsImage
  alias Vix.Vips.Operation

  @moduletag :tmp_dir
  @moduletag :capture_log

  # A solid-colour image encoded as `suffix` (".png", ".jpg", ".webp", ".gif", ".svg" ...)
  defp image_file(dir, name, width, height, suffix \\ nil) do
    {:ok, image} = Operation.black(width, height, bands: 3)
    path = Path.join(dir, name)
    {:ok, binary} = VipsImage.write_to_buffer(image, suffix || Path.extname(name))
    File.write!(path, binary)
    path
  end

  describe "attributes/2" do
    test "returns dimensions only for images within the thumbnail limits", %{tmp_dir: dir} do
      path = image_file(dir, "small.png", 640, 480)

      assert Image.attributes(path, "image/png") == %{
               attachment_width: 640,
               attachment_height: 480
             }
    end

    test "thumbnails images wider or taller than 1200x800 and keeps the format", %{tmp_dir: dir} do
      for {name, type, ext} <- [
            {"wide.png", "image/png", ".png"},
            {"wide.jpg", "image/jpeg", ".jpg"},
            {"wide.webp", "image/webp", ".webp"}
          ] do
        # Noise, so that the downscaled copy is smaller than the original
        {:ok, noise} = Operation.gaussnoise(3000, 2000, mean: 128, sigma: 40)
        {:ok, noise} = Operation.cast(noise, :VIPS_FORMAT_UCHAR)
        path = Path.join(dir, name)
        {:ok, binary} = VipsImage.write_to_buffer(noise, ext)
        File.write!(path, binary)

        attrs = Image.attributes(path, type)

        assert %{attachment_width: 3000, attachment_height: 2000, attachment_thumbnail_key: key} =
                 attrs

        assert String.ends_with?(key, ext)
        {:ok, thumbnail} = VipsImage.new_from_file(Uploads.path(key))
        assert {VipsImage.width(thumbnail), VipsImage.height(thumbnail)} == {1200, 800}
        assert File.stat!(Uploads.path(key)).size < File.stat!(path).size

        Uploads.delete(key)
      end
    end

    test "scales tall images to the height limit", %{tmp_dir: dir} do
      {:ok, noise} = Operation.gaussnoise(1000, 2000, mean: 128, sigma: 40)
      path = Path.join(dir, "tall.png")
      {:ok, binary} = VipsImage.write_to_buffer(noise, ".png")
      File.write!(path, binary)

      assert %{attachment_thumbnail_key: key} = Image.attributes(path, "image/png")
      {:ok, thumbnail} = VipsImage.new_from_file(Uploads.path(key))
      assert {VipsImage.width(thumbnail), VipsImage.height(thumbnail)} == {400, 800}
      Uploads.delete(key)
    end

    test "never thumbnails GIFs (they may be animated) but reads their size", %{tmp_dir: dir} do
      path = image_file(dir, "big.gif", 2000, 1000)

      assert Image.attributes(path, "image/gif") == %{
               attachment_width: 2000,
               attachment_height: 1000
             }
    end

    test "ignores SVG and other types, whatever the file contains", %{tmp_dir: dir} do
      svg = Path.join(dir, "logo.svg")
      File.write!(svg, ~s(<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"/>))

      assert Image.attributes(svg, "image/svg+xml") == %{}
      # An SVG claiming to be a PNG is refused by the loader check
      assert Image.attributes(svg, "image/png") == %{}
      assert Image.attributes(image_file(dir, "a.png", 10, 10), "application/pdf") == %{}
      assert Image.attributes(image_file(dir, "b.png", 10, 10), nil) == %{}
    end

    test "failures yield no attributes instead of raising", %{tmp_dir: dir} do
      broken = Path.join(dir, "broken.png")
      File.write!(broken, "not an image")

      assert Image.attributes(broken, "image/png") == %{}
      assert Image.attributes(Path.join(dir, "missing.png"), "image/png") == %{}
    end

    test "applies the EXIF orientation to the dimensions", %{tmp_dir: dir} do
      {:ok, image} = Operation.black(400, 200, bands: 3)

      {:ok, image} =
        VipsImage.mutate(image, &Vix.Vips.MutableImage.set(&1, "orientation", :gint, 6))

      path = Path.join(dir, "rotated.jpg")
      {:ok, binary} = VipsImage.write_to_buffer(image, ".jpg")
      File.write!(path, binary)

      assert %{attachment_width: 200, attachment_height: 400} =
               Image.attributes(path, "image/jpeg")
    end
  end

  describe "preview_dimensions/2" do
    test "keeps images within the limits and scales larger ones down to fit" do
      assert Image.preview_dimensions(640, 480) == {640, 480}
      assert Image.preview_dimensions(3000, 2000) == {1200, 800}
      assert Image.preview_dimensions(2400, 800) == {1200, 400}
      assert Image.preview_dimensions(1000, 2000) == {400, 800}
    end

    test "is nil without both dimensions" do
      assert Image.preview_dimensions(nil, 10) == nil
      assert Image.preview_dimensions(10, nil) == nil
      assert Image.preview_dimensions(0, 0) == nil
    end
  end
end
