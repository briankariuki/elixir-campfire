defmodule Campfire.SupportModulesTest do
  use ExUnit.Case, async: true

  alias Campfire.{Presence, Sound, Uploads}

  describe "Sound" do
    test "has the 56 built-in sounds" do
      assert length(Sound.names()) == 56
      assert Sound.find("trombone") == {:text, "plays a sad trombone"}
      assert Sound.find("deeper") == {:image, "top.webp", 188, 80}
      assert Sound.find("nope") == nil
      assert Sound.audio_path("bell") == "/sounds/bell.mp3"
      assert Sound.image_path("top.webp") == "/images/sounds/top.webp"
    end

    test "sound_name/1 matches exactly `/play <known name>`" do
      assert Sound.sound_name("/play 56k") == "56k"
      assert Sound.sound_name("/play nope") == nil
      assert Sound.sound_name(" /play bell") == nil
      assert Sound.sound_name("/play bell now") == nil
      assert Sound.sound_name(nil) == nil
    end
  end

  describe "Uploads" do
    test "store, store_binary, path and delete" do
      source = Path.join(System.tmp_dir!(), "src-#{System.unique_integer([:positive])}.JPG")
      File.write!(source, "jpeg")

      assert {:ok, key} = Uploads.store(source, "Photo.JPG")
      assert String.ends_with?(key, ".jpg")
      assert File.read!(Uploads.path(key)) == "jpeg"
      assert Uploads.exists?(key)

      assert {:ok, key2} = Uploads.store_binary("bin", "weird name")
      refute String.contains?(key2, ".")
      assert File.read!(Uploads.path(key2)) == "bin"

      assert Uploads.path("../../etc/passwd") == Path.join(Uploads.dir(), "passwd")

      assert :ok = Uploads.delete(key)
      refute Uploads.exists?(key)
      assert :ok = Uploads.delete(key)
      assert :ok = Uploads.delete(nil)
    end
  end

  describe "Presence" do
    test "tracks users per room" do
      room_id = System.unique_integer([:positive])
      {:ok, _} = Presence.track_user(self(), room_id, 7)
      assert Presence.present_user_ids(room_id) == [7]
      :ok = Presence.untrack_user(self(), room_id, 7)
      assert Presence.present_user_ids(room_id) == []
    end
  end
end
