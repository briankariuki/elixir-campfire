defmodule CampfireWeb.BotAPITest do
  use CampfireWeb.ConnCase, async: true

  import Campfire.Fixtures

  alias Campfire.Accounts.User
  alias Campfire.Chat

  setup do
    account_fixture()
    admin = admin_fixture()
    bot = bot_fixture(name: "Deploy Bot")
    room = open_room_fixture(admin, "Watercooler")
    %{admin: admin, bot: bot, room: room, key: User.bot_key(bot)}
  end

  defp raw_post(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> post(path, body)
  end

  defp raw_put(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put(path, body)
  end

  describe "authentication and access" do
    test "401 for a bad key", %{conn: conn, room: room, bot: bot} do
      assert conn |> get("/rooms/#{room.id}/#{bot.id}-wrong/messages") |> json_response(401)
      assert build_conn() |> get("/rooms/#{room.id}/#{bot.id}-/messages") |> json_response(401)

      assert build_conn()
             |> raw_post("/rooms/#{room.id}/nope/messages", "Hi")
             |> json_response(401)
    end

    test "401 for a deactivated bot", %{conn: conn, room: room, bot: bot, admin: admin, key: key} do
      {:ok, _} = Campfire.Accounts.deactivate_user(bot, actor: admin)
      assert conn |> get("/rooms/#{room.id}/#{key}/messages") |> json_response(401)
    end

    test "404 for a room the bot isn't in", %{conn: conn, admin: admin, key: key} do
      closed = closed_room_fixture(admin, [admin])
      assert conn |> get("/rooms/#{closed.id}/#{key}/messages") |> json_response(404)

      assert build_conn()
             |> raw_post("/rooms/#{closed.id}/#{key}/messages", "Hi")
             |> json_response(404)
    end

    test "429 for POSTs from a banned IP", %{conn: conn, room: room, admin: admin, key: key} do
      banned = user_fixture()
      session_fixture(banned, ip_address: "9.9.9.9")
      {:ok, _} = Campfire.Accounts.ban_user(banned, actor: admin)

      conn = %{conn | remote_ip: {9, 9, 9, 9}}
      assert conn |> raw_post("/rooms/#{room.id}/#{key}/messages", "Hi") |> response(429)
    end
  end

  describe "POST messages" do
    test "posts the raw body", %{conn: conn, room: room, bot: bot, key: key} do
      Campfire.Broadcast.subscribe_room(room.id)

      conn = raw_post(conn, "/rooms/#{room.id}/#{key}/messages", "Hello! 100% done & dusted")
      json = json_response(conn, 201)

      assert json["body"]["plain_text"] == "Hello! 100% done & dusted"

      assert json["body"]["html"] ==
               ~s(<div class="lexxy-content">Hello! 100% done &amp; dusted</div>)

      assert json["creator"]["id"] == bot.id
      assert json["creator"]["role"] == "bot"
      assert json["creator"]["avatar_url"] =~ "/users/#{bot.id}/avatar"
      assert json["room"] == %{"id" => room.id}
      assert json["url"] =~ "/rooms/#{room.id}/@#{json["id"]}"
      assert json["created_at"] =~ ~r/\A\d{4}-\d\d-\d\dT.*Z\z/

      assert_receive {:message_created, %{body: "Hello! 100% done & dusted"}}
    end

    test "posts a text/plain body", %{conn: conn, room: room, key: key} do
      conn =
        conn
        |> put_req_header("content-type", "text/plain")
        |> post("/rooms/#{room.id}/#{key}/messages", "Plain text")

      assert json_response(conn, 201)["body"]["plain_text"] == "Plain text"
    end

    test "422 for a blank body", %{conn: conn, room: room, key: key} do
      assert conn |> raw_post("/rooms/#{room.id}/#{key}/messages", "  ") |> json_response(422)

      assert build_conn()
             |> raw_post("/rooms/#{room.id}/#{key}/messages", "")
             |> json_response(422)
    end

    test "posts a multipart attachment", %{conn: conn, room: room, key: key, admin: admin} do
      path = Path.join(System.tmp_dir!(), "bot-upload-#{System.unique_integer([:positive])}.txt")
      File.write!(path, "report contents")

      upload = %Plug.Upload{path: path, filename: "report.txt", content_type: "text/plain"}
      conn = post(conn, "/rooms/#{room.id}/#{key}/messages", %{"attachment" => upload})
      json = json_response(conn, 201)

      assert json["body"]["plain_text"] == "report.txt"
      {:ok, message} = Chat.get_message(json["id"], actor: admin)
      assert message.attachment_filename == "report.txt"
      assert message.attachment_byte_size == byte_size("report contents")
      assert File.read!(Campfire.Uploads.path(message.attachment_key)) == "report contents"
    end
  end

  describe "GET messages" do
    test "pages with X-Total-Count and Link", %{conn: conn, room: room, admin: admin, key: key} do
      messages = for i <- 1..45, do: message_fixture(room, admin, %{body: "Message #{i}"})

      conn = get(conn, "/rooms/#{room.id}/#{key}/messages")
      json = json_response(conn, 200)

      assert length(json) == 40
      assert List.last(json)["body"]["plain_text"] == "Message 45"
      assert get_resp_header(conn, "x-total-count") == ["45"]
      first_id = hd(json)["id"]
      assert [link] = get_resp_header(conn, "link")
      assert link =~ ~s(/rooms/#{room.id}/#{key}/messages?before=#{first_id}>; rel="next")

      older = build_conn() |> get("/rooms/#{room.id}/#{key}/messages?before=#{first_id}")
      assert length(json_response(older, 200)) == 5
      assert get_resp_header(older, "link") == []

      first = hd(messages)
      newer = build_conn() |> get("/rooms/#{room.id}/#{key}/messages?after=#{first.id}")
      newer_json = json_response(newer, 200)
      assert length(newer_json) == 40
      assert [after_link] = get_resp_header(newer, "link")
      assert after_link =~ "after=#{List.last(newer_json)["id"]}"
    end

    test "an empty room gives []", %{conn: conn, room: room, key: key} do
      conn = get(conn, "/rooms/#{room.id}/#{key}/messages")
      assert json_response(conn, 200) == []
      assert get_resp_header(conn, "x-total-count") == ["0"]
    end
  end

  describe "PUT/DELETE messages" do
    setup %{room: room, bot: bot, admin: admin} do
      %{own: message_fixture(room, bot, %{body: "Mine"}), other: message_fixture(room, admin)}
    end

    test "updates its own message", %{conn: conn, room: room, key: key, own: own} do
      conn = raw_put(conn, "/rooms/#{room.id}/#{key}/messages/#{own.id}", "Edited")
      assert json_response(conn, 200)["body"]["plain_text"] == "Edited"
    end

    test "403 for someone else's message", %{conn: conn, room: room, key: key, other: other} do
      assert conn
             |> raw_put("/rooms/#{room.id}/#{key}/messages/#{other.id}", "X")
             |> json_response(403)

      assert build_conn()
             |> delete("/rooms/#{room.id}/#{key}/messages/#{other.id}")
             |> json_response(403)
    end

    test "404 for a message in another room", %{
      conn: conn,
      room: room,
      key: key,
      admin: admin,
      bot: bot
    } do
      elsewhere = open_room_fixture(admin)
      foreign = message_fixture(elsewhere, bot)

      assert conn
             |> raw_put("/rooms/#{room.id}/#{key}/messages/#{foreign.id}", "X")
             |> json_response(404)

      assert build_conn()
             |> delete("/rooms/#{room.id}/#{key}/messages/#{foreign.id}")
             |> json_response(404)

      assert build_conn() |> delete("/rooms/#{room.id}/#{key}/messages/0") |> json_response(404)
    end

    test "deletes its own message", %{conn: conn, room: room, key: key, own: own, admin: admin} do
      assert conn |> delete("/rooms/#{room.id}/#{key}/messages/#{own.id}") |> response(204)
      assert {:error, _} = Chat.get_message(own.id, actor: admin)
    end
  end

  describe "boosts" do
    setup %{room: room, admin: admin} do
      %{message: message_fixture(room, admin)}
    end

    test "creates a boost from the raw body", %{
      conn: conn,
      room: room,
      key: key,
      message: message,
      bot: bot
    } do
      conn = raw_post(conn, "/rooms/#{room.id}/#{key}/messages/#{message.id}/boosts", "👀")
      json = json_response(conn, 201)

      assert json["content"] == "👀"
      assert json["booster"]["id"] == bot.id
      assert json["message"]["id"] == message.id
      assert json["message"]["url"] =~ "/rooms/#{room.id}/@#{message.id}"
    end

    test "422 for a blank boost", %{conn: conn, room: room, key: key, message: message} do
      assert conn
             |> raw_post("/rooms/#{room.id}/#{key}/messages/#{message.id}/boosts", " ")
             |> json_response(422)
    end

    test "deletes its own boost, 404 for others", %{
      conn: conn,
      room: room,
      key: key,
      message: message,
      admin: admin,
      bot: bot
    } do
      {:ok, own} = Chat.create_boost(message, "🎉", actor: bot)
      {:ok, theirs} = Chat.create_boost(message, "🔥", actor: admin)

      path = "/rooms/#{room.id}/#{key}/messages/#{message.id}/boosts"
      assert conn |> delete("#{path}/#{theirs.id}") |> json_response(404)
      assert build_conn() |> delete("#{path}/#{own.id}") |> response(204)
      assert build_conn() |> delete("#{path}/#{own.id}") |> json_response(404)
    end
  end
end
