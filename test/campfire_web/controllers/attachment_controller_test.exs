defmodule CampfireWeb.AttachmentControllerTest do
  use CampfireWeb.ConnCase, async: true

  import Campfire.Fixtures

  alias Campfire.Uploads

  setup :register_and_log_in_user

  setup %{user: user} do
    room = closed_room_fixture(user, [user])
    {:ok, key} = Uploads.store_binary("file contents", "report.pdf")

    message =
      message_fixture(room, user, %{
        body: "",
        attachment_key: key,
        attachment_filename: "Q1 report.pdf",
        attachment_content_type: "application/pdf",
        attachment_byte_size: 13
      })

    %{room: room, message: message}
  end

  test "serves the file to members", %{conn: conn, message: message} do
    conn = get(conn, ~p"/attachments/#{message.id}")

    assert conn.status == 200
    assert conn.resp_body == "file contents"
    # Not an inline media type: a download of opaque bytes
    assert get_resp_header(conn, "content-type") == ["application/octet-stream"]
    [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ ~s(attachment; filename="Q1 report.pdf")
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "content-security-policy") == ["sandbox"]
  end

  test "only allowlisted media types are inline, whatever their case", %{
    user: user,
    room: room
  } do
    for {type, served, disposition} <- [
          {"image/SVG+xml", "application/octet-stream", "attachment"},
          {"text/HTML", "application/octet-stream", "attachment"},
          {"image/x-icon", "application/octet-stream", "attachment"},
          {" IMAGE/PNG; foo=bar", "image/png", "inline"},
          {"video/mp4", "video/mp4", "inline"}
        ] do
      {:ok, key} = Uploads.store_binary("data", "file.bin")

      message =
        message_fixture(room, user, %{
          body: "",
          attachment_key: key,
          attachment_filename: "file.bin",
          attachment_content_type: type
        })

      conn = build_conn() |> log_in_user(user) |> get(~p"/attachments/#{message.id}")

      assert get_resp_header(conn, "content-type") == [served], type
      assert [header] = get_resp_header(conn, "content-disposition")
      assert String.starts_with?(header, disposition), type
      assert get_resp_header(conn, "content-security-policy") == ["sandbox"]
    end
  end

  test "serves images inline and downloads on request", %{conn: conn, user: user, room: room} do
    {:ok, key} = Uploads.store_binary("png", "a.png")

    message =
      message_fixture(room, user, %{
        body: "",
        attachment_key: key,
        attachment_filename: "a.png",
        attachment_content_type: "image/png"
      })

    [disposition] =
      conn |> get(~p"/attachments/#{message.id}") |> get_resp_header("content-disposition")

    assert disposition =~ "inline"

    [disposition] =
      build_conn()
      |> log_in_user(user)
      |> get(~p"/attachments/#{message.id}?download=1")
      |> get_resp_header("content-disposition")

    assert disposition =~ "attachment"
  end

  test "404s for non-members, messages without files and unknown ids", %{
    message: message,
    room: room,
    user: user
  } do
    outsider = user_fixture()
    conn = build_conn() |> log_in_user(outsider) |> get(~p"/attachments/#{message.id}")
    assert conn.status == 404

    text = message_fixture(room, user, %{body: "no file"})
    conn = build_conn() |> log_in_user(user) |> get(~p"/attachments/#{text.id}")
    assert conn.status == 404

    conn = build_conn() |> log_in_user(user) |> get(~p"/attachments/0")
    assert conn.status == 404
  end

  test "redirects guests to the login page", %{message: message} do
    conn = get(build_conn(), ~p"/attachments/#{message.id}")
    assert redirected_to(conn) == ~p"/session/new"
  end
end
