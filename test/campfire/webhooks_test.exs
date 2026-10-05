defmodule Campfire.WebhooksTest do
  use Campfire.DataCase, async: true

  import Campfire.Fixtures

  alias Campfire.Accounts.User
  alias Campfire.Chat

  setup do
    user = user_fixture(name: "David")
    bot = bot_fixture(name: "Helper", webhook_url: "https://bots.example.com/helper")
    room = open_room_fixture(user, "Watercooler")
    %{user: user, bot: bot, room: room}
  end

  # Stubs the webhook endpoint: reports each request to the test process and responds with
  # `respond.(conn)`.
  defp stub_webhook(respond) do
    test_pid = self()

    Req.Test.stub(Campfire.Webhooks, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:webhook, conn.request_path, Jason.decode!(body)})
      respond.(conn)
    end)
  end

  defp bot_messages(room, bot) do
    room.id
    |> Chat.page_messages!(actor: bot)
    |> Enum.filter(&(&1.creator_id == bot.id))
  end

  test "posts the payload when a bot is mentioned and replies with text", %{
    user: user,
    bot: bot,
    room: room
  } do
    stub_webhook(&Req.Test.text(&1, "Hi David!"))

    message = message_fixture(room, user, body: "@Helper  what's up?")

    assert_received {:webhook, "/helper", payload}

    assert payload == %{
             "user" => %{"id" => user.id, "name" => "David"},
             "room" => %{
               "id" => room.id,
               "name" => "Watercooler",
               "path" => "/rooms/#{room.id}/#{User.bot_key(bot)}/messages"
             },
             "message" => %{
               "id" => message.id,
               "body" => %{"html" => "<p>@Helper  what&#39;s up?</p>", "plain" => "what's up?"},
               "path" => "/rooms/#{room.id}/@#{message.id}"
             }
           }

    assert [%{body: "Hi David!"}] = bot_messages(room, bot)
  end

  test "no webhook without a mention in shared rooms", %{user: user, room: room} do
    stub_webhook(&Req.Test.text(&1, "nope"))
    message_fixture(room, user, body: "Helper is not mentioned")
    refute_received {:webhook, _, _}
  end

  test "every message in a direct room with the bot is delivered", %{user: user, bot: bot} do
    stub_webhook(&Req.Test.text(&1, "pong"))
    direct = direct_room_fixture(user, [bot])

    message_fixture(direct, user, body: "ping")

    assert_received {:webhook, _, %{"message" => %{"body" => %{"plain" => "ping"}}}}
    assert [%{body: "pong"}] = bot_messages(direct, bot)
  end

  test "replies don't trigger webhooks (no loops)", %{user: user, bot: bot, room: room} do
    _other = bot_fixture(name: "Other", webhook_url: "https://bots.example.com/other")
    stub_webhook(&Req.Test.text(&1, "@Other hello"))

    message_fixture(room, user, body: "@Helper go")

    assert_received {:webhook, "/helper", _}
    refute_received {:webhook, "/other", _}
    assert [%{body: "@Other hello"}] = bot_messages(room, bot)
  end

  test "bots can trigger other bots, but never themselves", %{bot: bot, room: room} do
    _other = bot_fixture(name: "Other", webhook_url: "https://bots.example.com/other")
    stub_webhook(fn conn -> Plug.Conn.send_resp(conn, 204, "") end)

    message_fixture(room, bot, body: "@Helper @Other hi")

    assert_received {:webhook, "/other", _}
    refute_received {:webhook, "/helper", _}
  end

  test "inactive bots and bots without webhooks get nothing", %{user: user, bot: bot, room: room} do
    _plain_bot = bot_fixture(name: "Plain")
    Campfire.Accounts.deactivate_user!(bot, actor: admin_fixture())
    stub_webhook(&Req.Test.text(&1, "nope"))

    message_fixture(room, user, body: "@Helper @Plain hi")
    refute_received {:webhook, _, _}
  end

  test "binary responses become attachment replies", %{user: user, bot: bot, room: room} do
    stub_webhook(fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("image/png", nil)
      |> Plug.Conn.send_resp(200, <<137, 80, 78, 71>>)
    end)

    message_fixture(room, user, body: "@Helper draw")

    assert [reply] = bot_messages(room, bot)
    assert reply.attachment_filename == "attachment.png"
    assert reply.attachment_content_type == "image/png"
    assert reply.attachment_byte_size == 4
    assert File.read!(Campfire.Uploads.path(reply.attachment_key)) == <<137, 80, 78, 71>>
  end

  @tag :capture_log
  test "blank text and error responses post nothing", %{user: user, bot: bot, room: room} do
    stub_webhook(&Req.Test.text(&1, "   "))
    message_fixture(room, user, body: "@Helper one")

    stub_webhook(fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)
    message_fixture(room, user, body: "@Helper two")

    assert bot_messages(room, bot) == []
  end

  test "html replies become text", %{user: user, bot: bot, room: room} do
    stub_webhook(&Req.Test.html(&1, "<p>Hello &amp; welcome</p>"))
    message_fixture(room, user, body: "@Helper hi")
    assert [%{body: "Hello & welcome"}] = bot_messages(room, bot)
  end

  test "a timeout posts the failure text", %{user: user, bot: bot, room: room} do
    stub_webhook(&Req.Test.transport_error(&1, :timeout))
    message_fixture(room, user, body: "@Helper slow")
    assert [%{body: "Failed to respond within 7 seconds"}] = bot_messages(room, bot)
  end
end
