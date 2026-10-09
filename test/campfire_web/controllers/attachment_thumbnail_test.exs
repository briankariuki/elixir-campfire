defmodule CampfireWeb.AttachmentThumbnailTest do
  use CampfireWeb.ConnCase, async: true

  import Campfire.Fixtures
  import Phoenix.LiveViewTest

  alias Campfire.{Chat, Uploads}
  alias Campfire.Accounts.User
  alias Vix.Vips.Image, as: VipsImage
  alias Vix.Vips.Operation

  @moduletag :capture_log

  setup :register_and_log_in_user

  # A noisy PNG (so the downscaled copy is smaller), as a path and its bytes
  defp big_png(width \\ 2400, height \\ 1600) do
    {:ok, noise} = Operation.gaussnoise(width, height, mean: 128, sigma: 40)
    {:ok, binary} = VipsImage.write_to_buffer(noise, ".png")
    path = Path.join(System.tmp_dir!(), "thumb-test-#{System.unique_integer([:positive])}.png")
    File.write!(path, binary)
    {path, binary}
  end

  defp image_message(room, user) do
    {path, binary} = big_png()
    {:ok, key} = Uploads.store(path, "photo.png")
    {:ok, thumbnail_key} = Uploads.store_binary("thumbnail bytes", "thumbnail.png")

    message =
      message_fixture(room, user, %{
        body: "",
        attachment_key: key,
        attachment_filename: "photo.png",
        attachment_content_type: "image/png",
        attachment_byte_size: byte_size(binary),
        attachment_width: 2400,
        attachment_height: 1600,
        attachment_thumbnail_key: thumbnail_key
      })

    {message, binary}
  end

  describe "GET /attachments/:id?thumb=1" do
    setup %{user: user} do
      room = closed_room_fixture(user, [user])
      {message, binary} = image_message(room, user)
      %{room: room, message: message, original: binary}
    end

    test "serves the thumbnail inline with the same safe headers", %{conn: conn, message: message} do
      conn = get(conn, ~p"/attachments/#{message.id}?thumb=1")

      assert conn.status == 200
      assert conn.resp_body == "thumbnail bytes"
      assert get_resp_header(conn, "content-type") == ["image/png"]

      assert [~s(inline; filename="photo.png"; ) <> _] =
               get_resp_header(conn, "content-disposition")

      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
      assert get_resp_header(conn, "content-security-policy") == ["sandbox"]
    end

    test "the original and downloads are never the thumbnail", %{
      conn: conn,
      message: message,
      original: original
    } do
      assert get(conn, ~p"/attachments/#{message.id}").resp_body == original

      download = get(conn, ~p"/attachments/#{message.id}?thumb=1&download=1")
      assert download.resp_body == original
      assert [~s(attachment; ) <> _] = get_resp_header(download, "content-disposition")
    end

    test "falls back to the original without a (readable) thumbnail", %{
      conn: conn,
      room: room,
      user: user,
      message: message,
      original: original
    } do
      Uploads.delete(message.attachment_thumbnail_key)
      assert get(conn, ~p"/attachments/#{message.id}?thumb=1").resp_body == original

      {path, binary} = big_png(10, 10)
      {:ok, key} = Uploads.store(path, "tiny.png")

      tiny =
        message_fixture(room, user, %{
          body: "",
          attachment_key: key,
          attachment_filename: "tiny.png",
          attachment_content_type: "image/png"
        })

      assert get(conn, ~p"/attachments/#{tiny.id}?thumb=1").resp_body == binary
    end

    test "is not served to non-members or anonymous visitors", %{message: message} do
      assert build_conn() |> get(~p"/attachments/#{message.id}?thumb=1") |> response(302)

      outsider = user_fixture()

      assert build_conn()
             |> log_in_user(outsider)
             |> get(~p"/attachments/#{message.id}?thumb=1")
             |> response(404)
    end

    test "never serves a thumbnail for types that aren't allowlisted rasters", %{
      conn: conn,
      room: room,
      user: user
    } do
      {:ok, key} = Uploads.store_binary("<svg/>", "x.svg")
      {:ok, thumbnail_key} = Uploads.store_binary("<script/>", "t.svg")

      message =
        message_fixture(room, user, %{
          body: "",
          attachment_key: key,
          attachment_filename: "x.svg",
          attachment_content_type: "image/svg+xml",
          attachment_thumbnail_key: thumbnail_key
        })

      conn = get(conn, ~p"/attachments/#{message.id}?thumb=1")
      assert conn.resp_body == "<svg/>"
      assert get_resp_header(conn, "content-type") == ["application/octet-stream"]
    end
  end

  describe "deleting" do
    setup %{user: user} do
      room = closed_room_fixture(user, [user])
      {message, _binary} = image_message(room, user)
      %{room: room, message: message}
    end

    test "a message removes its thumbnail file", %{user: user, message: message} do
      assert Uploads.exists?(message.attachment_thumbnail_key)

      assert :ok = Chat.destroy_message(message, actor: user)

      refute Uploads.exists?(message.attachment_key)
      refute Uploads.exists?(message.attachment_thumbnail_key)
    end

    test "a room removes its thumbnail files", %{user: user, room: room, message: message} do
      assert :ok = Chat.destroy_room(room, actor: user)

      refute Uploads.exists?(message.attachment_key)
      refute Uploads.exists?(message.attachment_thumbnail_key)
    end
  end

  describe "uploading" do
    test "the room composer stores dimensions and a thumbnail", %{conn: conn, user: user} do
      room = open_room_fixture(user, "Pictures")
      {_path, binary} = big_png()
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      input =
        file_input(view, "#composer", :attachments, [
          %{name: "photo.png", content: binary, type: "image/png"}
        ])

      render_upload(input, "photo.png")
      view |> form("#composer", %{body: ""}) |> render_submit()

      assert [photo] = Chat.page_messages!(room.id, %{}, actor: user)
      assert photo.attachment_width == 2400
      assert photo.attachment_height == 1600
      assert Uploads.exists?(photo.attachment_thumbnail_key)

      # Rendered from the thumbnail in a box of the original's proportions; the lightbox opens the original
      assert has_element?(
               view,
               ~s(div.max-inline-size[style*="width: 600px; aspect-ratio: 1200 / 800"])
             )

      assert has_element?(
               view,
               ~s(a[data-lightbox][href="/attachments/#{photo.id}"] img.message__attachment[src="/attachments/#{photo.id}?thumb=1"][width="1200"][height="800"])
             )

      assert has_element?(
               view,
               ~s(a[data-lightbox-download="/attachments/#{photo.id}?download=1"])
             )
    end

    test "the bot API stores dimensions and a thumbnail", %{user: user} do
      bot = bot_fixture(name: "Camera")
      room = open_room_fixture(user, "Bot pics")
      {path, _binary} = big_png()

      upload = %Plug.Upload{path: path, filename: "shot.png", content_type: "image/png"}

      json =
        build_conn()
        |> post("/rooms/#{room.id}/#{User.bot_key(bot)}/messages", %{"attachment" => upload})
        |> json_response(201)

      {:ok, message} = Chat.get_message(json["id"], actor: user)
      assert {message.attachment_width, message.attachment_height} == {2400, 1600}
      assert Uploads.exists?(message.attachment_thumbnail_key)
    end

    test "a file that is not really an image is still accepted, without dimensions", %{
      conn: conn,
      user: user
    } do
      room = open_room_fixture(user, "Fake")
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      input =
        file_input(view, "#composer", :attachments, [
          %{name: "fake.png", content: "not a png", type: "image/png"}
        ])

      render_upload(input, "fake.png")
      view |> form("#composer", %{body: ""}) |> render_submit()

      assert [message] = Chat.page_messages!(room.id, %{}, actor: user)
      assert message.attachment_filename == "fake.png"
      assert is_nil(message.attachment_width)
      assert is_nil(message.attachment_thumbnail_key)
      assert has_element?(view, ~s(img.message__attachment[src="/attachments/#{message.id}"]))
    end
  end

  describe "share button" do
    test "file attachments and the message menu get a Share button", %{conn: conn, user: user} do
      room = open_room_fixture(user, "Files")

      message =
        message_fixture(room, user, %{
          body: "",
          attachment_key: "x.pdf",
          attachment_filename: "report.pdf",
          attachment_content_type: "application/pdf"
        })

      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      assert has_element?(
               view,
               ~s(button[phx-hook="Share"][hidden][data-share-url="/attachments/#{message.id}?download=1"])
             )

      assert has_element?(view, ~s(button[id^="share-file-"].message__action-btn))
      assert has_element?(view, ~s(button[id^="share-"][title="Share"]))
    end
  end
end
