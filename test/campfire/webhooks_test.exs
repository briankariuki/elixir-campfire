defmodule Campfire.WebhooksTest do
  use Campfire.DataCase, async: true
  use AshOban.Test, repo: Campfire.Repo

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

  test "an email-like @Name isn't a mention", %{user: user, room: room} do
    stub_webhook(&Req.Test.text(&1, "nope"))
    message = message_fixture(room, user, body: "write to ops@Helper.example")
    assert message.mentioned_user_ids == []
    refute_received {:webhook, _, _}
  end

  test "the plain body only drops real mentions of the bot", %{user: user, room: room} do
    stub_webhook(&Req.Test.text(&1, ""))
    message_fixture(room, user, body: "@Helper mail ops@Helper.example")
    assert_received {:webhook, "/helper", payload}
    assert payload["message"]["body"]["plain"] == "mail ops@Helper.example"
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

  describe "as Oban jobs" do
    # Jobs run inline by default (see config/test.exs); these tests hold them back to look at
    # the queue and to run retries.
    defp manual(fun), do: Oban.Testing.with_testing_mode(:manual, fun)

    defp drain_webhooks, do: Oban.drain_queue(queue: :webhooks, with_scheduled: true)

    defp bot_args(bot), do: [args: %{action_arguments: %{bot_id: bot.id}}]

    test "mentions enqueue one job per bot and the jobs post the replies", %{
      user: user,
      bot: bot,
      room: room
    } do
      other = bot_fixture(name: "Other", webhook_url: "https://bots.example.com/other")
      stub_webhook(&Req.Test.text(&1, "On it"))

      manual(fn ->
        message = message_fixture(room, user, body: "@Helper @Other go")

        assert [_] = assert_triggered(message, :deliver_webhooks, bot_args(bot))
        assert [_] = assert_triggered(message, :deliver_webhooks, bot_args(other))
        refute_received {:webhook, _, _}

        assert %{success: 2, failure: 0} = drain_webhooks()
      end)

      assert_received {:webhook, "/helper", _}
      assert_received {:webhook, "/other", _}
      assert [%{body: "On it"}] = bot_messages(room, bot)
      assert [%{body: "On it"}] = bot_messages(room, other)
    end

    test "no job without an eligible bot", %{user: user, room: room} do
      manual(fn ->
        message = message_fixture(room, user, body: "just talking")
        refute_triggered(message, :deliver_webhooks)
      end)
    end

    test "a bot's reply enqueues nothing", %{user: user, bot: bot, room: room} do
      _other = bot_fixture(name: "Other", webhook_url: "https://bots.example.com/other")
      stub_webhook(&Req.Test.text(&1, "@Other hello"))

      manual(fn ->
        message_fixture(room, user, body: "@Helper go")
        assert %{success: 1} = drain_webhooks()
        assert %{success: 0, failure: 0} = drain_webhooks()
      end)

      assert [%{body: "@Other hello"}] = bot_messages(room, bot)
    end

    test "delivering doesn't touch the message", %{user: user, room: room} do
      stub_webhook(&Req.Test.text(&1, "hi"))

      manual(fn ->
        message = message_fixture(room, user, body: "@Helper hello")
        drain_webhooks()

        reloaded = Chat.get_message!(message.id, actor: user)
        assert reloaded.body == message.body
        assert reloaded.updated_at == message.updated_at
      end)
    end

    test "a bot deactivated after enqueueing is skipped", %{user: user, bot: bot, room: room} do
      stub_webhook(&Req.Test.text(&1, "late"))

      manual(fn ->
        message_fixture(room, user, body: "@Helper hello")
        Campfire.Accounts.deactivate_user!(bot, actor: admin_fixture())
        assert %{success: 1} = drain_webhooks()
      end)

      refute_received {:webhook, _, _}
      assert bot_messages(room, bot) == []
    end

    @tag :capture_log
    test "a timeout posts the failure text once, also when an earlier attempt was retried", %{
      user: user,
      bot: bot,
      room: room
    } do
      test_pid = self()

      Req.Test.expect(Campfire.Webhooks, fn conn ->
        send(test_pid, :refused)
        Req.Test.transport_error(conn, :econnrefused)
      end)

      Req.Test.expect(Campfire.Webhooks, fn conn ->
        send(test_pid, :timed_out)
        Req.Test.transport_error(conn, :timeout)
      end)

      manual(fn ->
        message_fixture(room, user, body: "@Helper slow")

        # Attempt 1: connection refused, the job fails and is retried.
        assert %{failure: 1, success: 0} = drain_webhooks()
        assert_received :refused
        assert bot_messages(room, bot) == []

        # Attempt 2: the timeout is answered and completes the job.
        assert %{success: 1, failure: 0} = drain_webhooks()
        assert_received :timed_out
        assert [%{body: "Failed to respond within 7 seconds"}] = bot_messages(room, bot)

        # Nothing is left to retry, so the failure text isn't posted again.
        assert %{success: 0, failure: 0} = drain_webhooks()
      end)

      assert [%{body: "Failed to respond within 7 seconds"}] = bot_messages(room, bot)
    end

    @tag :capture_log
    test "a timeout completes the job instead of failing it", %{user: user, bot: bot, room: room} do
      stub_webhook(&Req.Test.transport_error(&1, :timeout))

      manual(fn ->
        message_fixture(room, user, body: "@Helper slow")
        assert %{success: 1, failure: 0} = drain_webhooks()
        assert %{success: 0, failure: 0} = drain_webhooks()
      end)

      assert [%{body: "Failed to respond within 7 seconds"}] = bot_messages(room, bot)
    end

    @tag :capture_log
    test "connection errors are retried up to three attempts", %{user: user, room: room} do
      stub_webhook(&Req.Test.transport_error(&1, :econnrefused))

      manual(fn ->
        message_fixture(room, user, body: "@Helper hello")

        assert %{failure: 1} = drain_webhooks()
        assert %{failure: 1} = drain_webhooks()
        assert %{discard: 1} = drain_webhooks()
        assert %{success: 0, failure: 0, discard: 0} = drain_webhooks()
      end)
    end
  end
end
