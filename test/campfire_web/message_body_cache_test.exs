defmodule CampfireWeb.MessageBodyCacheTest do
  use Campfire.DataCase, async: true

  import Campfire.Fixtures

  alias Campfire.{Accounts, Chat}
  alias CampfireWeb.MessageBody
  alias CampfireWeb.MessageBody.Cache

  # The cache table is shared by the async tests, but its keys start with the message id (unique per
  # test), so each test only looks at the events of its own message.
  defp watch(message_id) do
    test = self()
    handler = "cache-test-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler,
      [[:campfire, :message_body_cache, :hit], [:campfire, :message_body_cache, :miss]],
      fn event, _measurements, %{key: key}, _config ->
        if elem(key, 0) == message_id, do: send(test, {:cache, List.last(event)})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  defp render(message, users \\ %{}, opts \\ []) do
    message |> MessageBody.cached_html(users, opts) |> Phoenix.HTML.safe_to_string()
  end

  setup do
    author = user_fixture(name: "Author")
    room = open_room_fixture(author)
    %{author: author, room: room}
  end

  test "renders once per message version, and matches the uncached render", %{
    author: author,
    room: room
  } do
    message = message_fixture(room, author, %{body: "Hello **world** https://example.com"})
    watch(message.id)

    first = MessageBody.cached_html(message, %{}, live: true)
    second = MessageBody.cached_html(message, %{}, live: true)

    assert {:safe, html} = first
    assert is_binary(html)
    assert second == first
    assert first == MessageBody.to_html(message, %{}, live: true) |> to_binary_safe()

    assert_received {:cache, :miss}
    assert_received {:cache, :hit}
    refute_received {:cache, :miss}
  end

  test "an edit renders again", %{author: author, room: room} do
    message = message_fixture(room, author, %{body: "before"})
    watch(message.id)

    assert render(message) =~ "before"
    assert_received {:cache, :miss}

    edited = Chat.update_message!(message, %{body: "after"}, actor: author)
    assert edited.id == message.id
    assert DateTime.compare(edited.updated_at, message.updated_at) == :gt

    assert render(edited) =~ "after"
    assert_received {:cache, :miss}
    refute render(edited) =~ "before"
    assert_received {:cache, :hit}
  end

  test "the body is part of the key, even with the same updated_at", %{author: author, room: room} do
    message = message_fixture(room, author, %{body: "one"})

    assert render(message) =~ "one"
    assert render(%{message | body: "two"}) =~ "two"
  end

  test "renaming a mentioned user renders again", %{author: author, room: room} do
    ann = user_fixture(name: "Ann")
    message = message_fixture(room, author, %{body: "Hi @Ann Lee"})
    assert message.mentioned_user_ids == [ann.id]
    watch(message.id)

    before = render(message, %{ann.id => ann})
    assert before =~ ~s(title="Ann")
    assert_received {:cache, :miss}

    assert render(message, %{ann.id => ann}) == before
    assert_received {:cache, :hit}

    renamed = Accounts.update_profile!(ann, %{name: "Ann Lee"}, actor: ann)
    after_rename = render(message, %{ann.id => renamed})

    assert_received {:cache, :miss}
    assert after_rename =~ ~s(title="Ann Lee")
    assert after_rename =~ "Ann Lee</span>"
    refute after_rename == before
  end

  test "an avatar change renders again", %{author: author, room: room} do
    ann = user_fixture(name: "Ann")
    message = message_fixture(room, author, %{body: "Hi @Ann"})
    watch(message.id)

    before = render(message, %{ann.id => ann})
    after_avatar = render(message, %{ann.id => %{ann | avatar_key: "new-avatar"}})

    assert_received {:cache, :miss}
    assert_received {:cache, :miss}
    refute after_avatar == before
  end

  test "live and plain renders are keyed separately", %{author: author, room: room} do
    message = message_fixture(room, author, %{body: "Hi\n> quoted\n— Author /rooms/1/@2\n\n"})
    watch(message.id)

    live = render(message, %{}, live: true)
    plain = render(message)

    assert live =~ ~s(data-phx-link="redirect")
    refute plain =~ "data-phx-link"
    assert_received {:cache, :miss}
    assert_received {:cache, :miss}

    assert render(message, %{}, live: true) == live
    assert render(message) == plain
    assert_received {:cache, :hit}
    assert_received {:cache, :hit}
  end

  test "messages without a text body are rendered uncached", %{author: author, room: room} do
    message = message_fixture(room, author, %{body: "text"})
    watch(message.id)

    assert render(%{message | body: ""}) =~ "lexxy-content"
    assert render(%{message | body: nil}) =~ "lexxy-content"
    assert render(%{id: nil, body: "no id", mentioned_user_ids: []}) =~ "no id"
    refute_received {:cache, _}
  end

  describe "Cache" do
    test "fetch/3 computes once per key" do
      cache = start_cache(:counting_test_cache, 100)
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      render = fn ->
        Agent.update(counter, &(&1 + 1))
        "html"
      end

      assert Cache.fetch(:a, render, cache) == "html"
      assert Cache.fetch(:a, render, cache) == "html"
      assert Cache.fetch(:b, render, cache) == "html"
      assert Agent.get(counter, & &1) == 2
      assert Cache.size(cache) == 2
    end

    test "stays bounded, dropping the oldest entries first" do
      cache = start_cache(:eviction_test_cache, 20)

      for i <- 1..100 do
        Cache.fetch({:key, i}, fn -> "html #{i}" end, cache)
        # The owner handles the notification before the next insert
        _ = :sys.get_state(cache)
        assert Cache.size(cache) <= 20
      end

      # The newest are kept, the oldest are gone
      assert :ets.member(cache, {:key, 100})
      assert :ets.member(cache, {:key, 90})
      refute :ets.member(cache, {:key, 1})
      assert Cache.size(cache) > 10
    end

    test "renders uncached when the table doesn't exist" do
      assert Cache.fetch(:a, fn -> "html" end, :no_such_cache) == "html"
    end
  end

  describe "concurrent fetches of one missing key" do
    test "render once, everybody gets the result" do
      cache = start_cache(:single_flight_cache, 20)
      renders = :counters.new(1, [])

      render = fn ->
        :counters.add(renders, 1, 1)
        Process.sleep(20)
        "html"
      end

      results =
        1..50
        |> Task.async_stream(fn _ -> Cache.fetch(:key, render, cache) end, max_concurrency: 50)
        |> Enum.map(fn {:ok, html} -> html end)

      assert results == List.duplicate("html", 50)
      assert :counters.get(renders, 1) == 1
    end

    test "a leader that raises leaves nothing behind, the next fetch renders" do
      cache = start_cache(:single_flight_raise_cache, 20)

      assert_raise RuntimeError, "boom", fn ->
        Cache.fetch(:key, fn -> raise "boom" end, cache)
      end

      refute :ets.member(cache, :key)
      assert Cache.fetch(:key, fn -> "html" end, cache) == "html"
    end

    test "a leader that died without cleaning up is not waited for forever" do
      cache = start_cache(:single_flight_stale_cache, 20)
      :ets.insert(cache, {:key, {:"$cache_pending", self()}, 0})

      assert Cache.fetch(:key, fn -> "html" end, cache) == "html"
      assert Cache.fetch(:key, fn -> "other" end, cache) == "html"
    end
  end

  defp start_cache(name, max) do
    start_supervised!({Cache, name: name, max_entries: max})
    name
  end

  defp to_binary_safe({:safe, iodata}), do: {:safe, IO.iodata_to_binary(iodata)}
end
