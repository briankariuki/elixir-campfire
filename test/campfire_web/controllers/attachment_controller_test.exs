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
    assert get_resp_header(conn, "content-type") == ["application/pdf"]
    [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ ~s(filename="Q1 report.pdf")
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
