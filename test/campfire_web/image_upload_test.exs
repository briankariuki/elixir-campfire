defmodule CampfireWeb.ImageUploadTest do
  use ExUnit.Case, async: true

  alias CampfireWeb.{ImageUpload, Paths}

  test "image?/2 needs both an image extension and an image content type" do
    assert ImageUpload.image?("me.PNG", "image/png")
    assert ImageUpload.image?("me.jpg", "Image/JPEG")
    refute ImageUpload.image?("evil.html", "image/png")
    refute ImageUpload.image?("evil.svg", "image/svg+xml")
    refute ImageUpload.image?("me.png", "text/html")
    refute ImageUpload.image?("me.png", nil)
  end

  test "content_type/1 only knows allowlisted image keys" do
    assert ImageUpload.content_type("abc.png") == "image/png"
    assert ImageUpload.content_type("abc.jpeg") == "image/jpeg"
    assert ImageUpload.content_type("abc.webp") == "image/webp"
    assert ImageUpload.content_type("abc.html") == nil
    assert ImageUpload.content_type("abc.svg") == nil
    assert ImageUpload.content_type(nil) == nil
  end

  test "the avatar cache-buster ignores updated_at" do
    user = %{id: 1, avatar_key: "a.png", name: "Jo", updated_at: ~U[2020-01-01 00:00:00Z]}

    assert Paths.avatar_path(user) == Paths.avatar_path(%{user | updated_at: DateTime.utc_now()})
    refute Paths.avatar_path(user) == Paths.avatar_path(%{user | avatar_key: "b.png"})
    refute Paths.avatar_path(user) == Paths.avatar_path(%{user | name: "Jane"})
  end
end
