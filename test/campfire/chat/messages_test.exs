defmodule Campfire.Chat.MessagesTest do
  use Campfire.DataCase, async: true

  import Campfire.Fixtures

  alias Campfire.{Broadcast, Chat, Presence}
  alias Campfire.Chat.{Mentions, Message}

  setup do
    author = user_fixture(name: "Author")
    member = user_fixture(name: "Member")
    room = closed_room_fixture(author, [author, member])
    %{author: author, member: member, room: room}
  end

  defp unread_at(room, user), do: Chat.get_membership!(room.id, actor: user).unread_at

  describe "create" do
    test "requires membership", %{room: room} do
      outsider = user_fixture()

      assert {:error, %Ash.Error.Forbidden{}} =
               Chat.create_message(room, %{body: "hi"}, actor: outsider)
    end

    test "rejects empty messages", %{room: room, author: author} do
      assert {:error, %Ash.Error.Invalid{}} =
               Chat.create_message(room, %{body: "  "}, actor: author)
    end

    test "fills client_message_id, loads creator and boosts, touches the room", %{
      room: room,
      author: author
    } do
      assert {:ok, message} = Chat.create_message(room, %{body: "Hello"}, actor: author)
      assert message.creator_id == author.id
      assert message.room_id == room.id
      assert {:ok, _} = Ecto.UUID.cast(message.client_message_id)
      assert message.creator.name == "Author"
      assert message.boosts == []

      assert {:ok, %{client_message_id: "abc"}} =
               Chat.create_message(room, %{body: "x", client_message_id: "abc"}, actor: author)

      assert DateTime.compare(reload(room).updated_at, room.updated_at) == :gt
    end

    test "marks unread for members who aren't the author, invisible or present", %{
      room: room,
      author: author,
      member: member
    } do
      present = user_fixture()
      invisible = user_fixture()

      Chat.update_closed_room!(
        room,
        %{user_ids: [author.id, member.id, present.id, invisible.id]},
        actor: author
      )

      Chat.set_involvement!(Chat.get_membership!(room.id, actor: invisible), :invisible,
        actor: invisible
      )

      {:ok, _} = Presence.track_user(self(), room.id, present.id)

      message = message_fixture(room, author)

      assert unread_at(room, member) == message.inserted_at
      assert unread_at(room, author) == nil
      assert unread_at(room, present) == nil
      assert unread_at(room, invisible) == nil
    end

    test "broadcasts the message to the room and room_unread to every member", %{
      room: room,
      author: author,
      member: member
    } do
      Broadcast.subscribe_room(room.id)
      Broadcast.subscribe_user(member.id)
      Broadcast.subscribe_user(author.id)

      message = message_fixture(room, author, body: "Broadcast me")

      assert_receive {:message_created, %Message{id: id, creator: %{name: "Author"}}}
      assert id == message.id
      room_id = room.id
      assert_receive {:room_unread, ^room_id}
      assert_receive {:room_unread, ^room_id}
    end

    test "notifications are held until the outermost transaction commits", %{
      room: room,
      author: author,
      member: member
    } do
      Broadcast.subscribe_room(room.id)
      Broadcast.subscribe_user(member.id)

      # Ash only knows about transactions it opened itself: inside one, `return_notifications?`
      # hands the notifications back for the caller to send once it has committed.
      {:ok, {message, notifications}} =
        Ash.DataLayer.transaction(Message, fn ->
          {:ok, message, notifications} =
            Chat.create_message(room, %{body: "In a transaction"},
              actor: author,
              return_notifications?: true
            )

          # Both the PubSub notifier (room topic) and the Fanout notifier (per-member) are held.
          refute_received {:message_created, _}
          refute_received {:room_unread, _}
          {message, notifications}
        end)

      refute_received {:message_created, _}
      Ash.Notifier.notify(notifications)

      assert_received {:message_created, %Message{id: id}}
      assert id == message.id
      assert_received {:room_unread, _}
    end
  end

  describe "mentions" do
    test "resolves @Full Name against room members, longest name first", %{
      room: room,
      author: author
    } do
      ann = user_fixture(name: "Ann")
      ann_smith = user_fixture(name: "Ann Smith")
      outsider = user_fixture(name: "Outsider")

      Chat.update_closed_room!(room, %{user_ids: [author.id, ann.id, ann_smith.id]},
        actor: author
      )

      message = message_fixture(room, author, body: "Hey @Ann Smith and @Outsider")
      assert message.mentioned_user_ids == [ann_smith.id]

      message = message_fixture(room, author, body: "@Ann, @Ann Smith!")
      assert Enum.sort(message.mentioned_user_ids) == Enum.sort([ann.id, ann_smith.id])

      message = message_fixture(room, author, body: "@Annie isn't Ann")
      assert message.mentioned_user_ids == []

      refute outsider.id in message.mentioned_user_ids

      {:ok, updated} = Chat.update_message(message, %{body: "now @Ann"}, actor: author)
      assert updated.mentioned_user_ids == [ann.id]
    end

    test "mentioned_ids/2" do
      assert Mentions.mentioned_ids("hi @Bob", [{1, "Bob"}, {2, "Bo"}]) == [1]
      assert Mentions.mentioned_ids("hi @Bo.", [{1, "Bob"}, {2, "Bo"}]) == [2]
      assert Mentions.mentioned_ids("hi Bob", [{1, "Bob"}]) == []
      assert Mentions.mentioned_ids(nil, [{1, "Bob"}]) == []
    end

    test "mentioned_ids/2 ignores @Name inside a word, like an email address" do
      members = [{1, "Ann"}, {2, "Deploy"}]

      assert Mentions.mentioned_ids("ping ops@Deploy.example", members) == []
      assert Mentions.mentioned_ids("mail bob@Ann.com", members) == []
      assert Mentions.mentioned_ids("x_@Ann 9@Ann", members) == []
      assert Mentions.mentioned_ids("ops@Deploy.example, cc @Ann", members) == [1]
    end

    test "mentioned_ids/2 matches at the start, after spaces, punctuation and newlines" do
      members = [{1, "Ann"}]

      for body <- ["@Ann", "hi @Ann", "(@Ann)", "hi,@Ann", "> @Ann", "first\n@Ann", "@@Ann"] do
        assert Mentions.mentioned_ids(body, members) == [1],
               "expected a mention in #{inspect(body)}"
      end

      assert Mentions.mentioned_ids("@Ann Smith@Ann", [{1, "Ann"}, {2, "Ann Smith"}]) == [2, 1]
    end

    test "mentioned_ids/2 mentions every member with the mentioned name" do
      members = [{1, "Ann"}, {2, "Bob"}, {3, "Ann"}, {4, "Ann Smith"}]

      assert Mentions.mentioned_ids("hi @Ann", members) == [1, 3]
      assert Mentions.mentioned_ids("@Ann Smith and @Ann", members) == [4, 1, 3]
      assert Mentions.mentioned_ids("@Ann Smith", members) == [4]
    end
  end

  describe "content type and plain text" do
    test "sound, text and attachment", %{room: room, author: author} do
      sound = message_fixture(room, author, body: "/play trombone")
      unknown = message_fixture(room, author, body: "/play nothing")
      text = message_fixture(room, author, body: "/play trombone please")

      attachment =
        message_fixture(room, author,
          body: "",
          attachment_key: "abc.png",
          attachment_filename: "cat.png",
          attachment_content_type: "image/png",
          attachment_byte_size: 10
        )

      assert Message.content_type(sound) == :sound
      assert Message.sound_name(sound) == "trombone"
      assert Message.content_type(unknown) == :text
      assert Message.content_type(text) == :text
      assert Message.content_type(attachment) == :attachment

      assert Message.plain_text(text) == "/play trombone please"
      assert Message.plain_text(attachment) == "cat.png"
      assert Message.plain_text(%Message{body: "", attachment_filename: nil}) == ""

      loaded = Ash.load!(sound, [:content_type, :plain_text], authorize?: false)
      assert loaded.content_type == :sound
      assert loaded.plain_text == "/play trombone"
    end
  end

  describe "update and destroy" do
    test "the creator or an admin may edit; others may not", %{
      room: room,
      author: author,
      member: member
    } do
      message = message_fixture(room, author)
      Broadcast.subscribe_room(room.id)

      assert {:error, %Ash.Error.Forbidden{}} =
               Chat.update_message(message, %{body: "hacked"}, actor: member)

      assert {:ok, %{body: "edited"}} =
               Chat.update_message(message, %{body: "edited"}, actor: author)

      assert_receive {:message_updated, %Message{body: "edited", creator: %{}}}

      admin = admin_fixture()
      assert Chat.can_update_message?(author, message)
      assert Chat.can_update_message?(admin, message)
      refute Chat.can_update_message?(member, message)

      assert {:ok, %{body: "by admin"}} =
               Chat.update_message(message, %{body: "by admin"}, actor: admin)
    end

    test "bots may only edit their own messages", %{room: room, author: author} do
      bot = bot_fixture()
      Chat.update_closed_room!(room, %{user_ids: [author.id, bot.id]}, actor: author)
      message = message_fixture(room, author)
      bot_message = message_fixture(room, bot)

      assert {:error, %Ash.Error.Forbidden{}} =
               Chat.update_message(message, %{body: "x"}, actor: bot)

      assert {:ok, _} = Chat.update_message(bot_message, %{body: "x"}, actor: bot)
    end

    test "destroy: creator or admin; deletes the file and broadcasts", %{
      room: room,
      author: author,
      member: member
    } do
      path = Path.join(System.tmp_dir!(), "upload-#{System.unique_integer([:positive])}.txt")
      File.write!(path, "data")
      {:ok, key} = Campfire.Uploads.store(path, "notes.txt")
      assert Campfire.Uploads.exists?(key)

      message =
        message_fixture(room, author,
          body: "",
          attachment_key: key,
          attachment_filename: "notes.txt"
        )

      Broadcast.subscribe_room(room.id)

      assert {:error, %Ash.Error.Forbidden{}} = Chat.destroy_message(message, actor: member)
      assert :ok = Chat.destroy_message(message, actor: author)
      assert_receive {:message_deleted, %Message{id: id}}
      assert id == message.id
      refute Campfire.Uploads.exists?(key)

      other = message_fixture(room, member)
      assert :ok = Chat.destroy_message(other, actor: admin_fixture())
    end
  end

  describe "remove_all_by_creator" do
    test "destroys each message through the action: broadcast and attachment cleanup", %{
      room: room,
      author: author,
      member: member
    } do
      path = Path.join(System.tmp_dir!(), "upload-#{System.unique_integer([:positive])}.txt")
      File.write!(path, "data")
      {:ok, key} = Campfire.Uploads.store(path, "notes.txt")

      one = message_fixture(room, author, body: "one")
      two = message_fixture(room, author, body: "", attachment_key: key, attachment_filename: "n")
      kept = message_fixture(room, member, body: "kept")
      Broadcast.subscribe_room(room.id)

      assert :ok = Message.remove_all_by_creator(author.id)

      assert_receive {:message_deleted, %Message{id: first}}
      assert_receive {:message_deleted, %Message{id: second}}
      assert Enum.sort([first, second]) == Enum.sort([one.id, two.id])
      refute_receive {:message_deleted, _}
      refute Campfire.Uploads.exists?(key)
      assert {:ok, _} = Chat.get_message(kept.id, actor: member)
    end
  end

  describe "reading" do
    test "only members can read messages", %{room: room, author: author} do
      message = message_fixture(room, author)
      assert {:ok, _} = Chat.get_message(message.id, actor: author)
      assert {:error, _} = Chat.get_message(message.id, actor: user_fixture())
      assert Chat.page_messages!(room.id, actor: user_fixture()) == []
    end

    test "count_messages", %{room: room, author: author} do
      for _ <- 1..3, do: message_fixture(room, author)
      assert Chat.count_messages(room.id, actor: author) == {:ok, 3}
    end
  end

  describe "pagination" do
    setup %{room: room, author: author} do
      messages = for i <- 1..100, do: message_fixture(room, author, body: "message #{i}")
      %{messages: messages}
    end

    defp ids(messages), do: Enum.map(messages, & &1.id)

    test "the default is the last 40, ascending", %{
      room: room,
      author: author,
      messages: messages
    } do
      page = Chat.page_messages!(room.id, actor: author)
      assert ids(page) == messages |> Enum.take(-40) |> ids()
      assert [%{creator: %{}, boosts: []} | _] = page
    end

    test "before, after and around", %{room: room, author: author, messages: messages} do
      cursor = Enum.at(messages, 50)

      assert ids(Chat.page_messages!(room.id, %{before: cursor.id}, actor: author)) ==
               messages |> Enum.slice(10, 40) |> ids()

      assert ids(Chat.page_messages!(room.id, %{after: cursor.id}, actor: author)) ==
               messages |> Enum.slice(51, 40) |> ids()

      assert ids(Chat.page_messages!(room.id, %{around: cursor.id}, actor: author)) ==
               messages |> Enum.slice(10, 81) |> ids()

      first = hd(messages)
      assert Chat.page_messages!(room.id, %{before: first.id}, actor: author) == []
    end

    test "ties on inserted_at are ordered by id", %{
      room: room,
      author: author,
      messages: messages
    } do
      at = ~N[2020-01-01 00:00:00.000000]
      Repo.update_all(from(m in "messages", where: m.room_id == ^room.id), set: [inserted_at: at])

      all_ids = ids(messages)
      cursor = Enum.at(messages, 50)

      assert ids(Chat.page_messages!(room.id, actor: author)) == Enum.take(all_ids, -40)

      assert ids(Chat.page_messages!(room.id, %{before: cursor.id}, actor: author)) ==
               Enum.slice(all_ids, 10, 40)

      assert ids(Chat.page_messages!(room.id, %{after: cursor.id}, actor: author)) ==
               Enum.slice(all_ids, 51, 40)
    end

    test "a deleted cursor pages by id", %{room: room, author: author, messages: messages} do
      cursor = Enum.at(messages, 50)
      Chat.destroy_message!(cursor, actor: author)

      assert ids(Chat.page_messages!(room.id, %{before: cursor.id}, actor: author)) ==
               messages |> Enum.slice(10, 40) |> ids()

      assert ids(Chat.page_messages!(room.id, %{after: cursor.id}, actor: author)) ==
               messages |> Enum.slice(51, 40) |> ids()

      assert ids(Chat.page_messages!(room.id, %{around: cursor.id}, actor: author)) ==
               messages |> Enum.take(-40) |> ids()
    end

    # inserted_at is shuffled so it disagrees with id order, in groups of 7 sharing one value
    # (so page boundaries fall inside tie groups); the id breaks the ties.
    defp scramble_inserted_at(messages) do
      base = ~N[2020-01-01 00:00:00.000000]

      messages
      |> Enum.with_index()
      |> Enum.map(fn {message, index} ->
        offset = rem(div(index, 7) * 5, 11)
        at = NaiveDateTime.add(base, offset, :second)
        Repo.update_all(from(m in "messages", where: m.id == ^message.id), set: [inserted_at: at])
        {offset, message.id}
      end)
      |> Enum.sort()
      |> Enum.map(&elem(&1, 1))
    end

    test "walks the whole room in both directions with ties across page boundaries", %{
      room: room,
      author: author,
      messages: messages
    } do
      ordered = scramble_inserted_at(messages)

      last = ids(Chat.page_messages!(room.id, actor: author))
      assert last == Enum.take(ordered, -40)

      # backwards from the last page, 40 at a time
      back =
        Enum.reduce_while(1..5, {last, []}, fn _, {page, acc} ->
          case Chat.page_messages!(room.id, %{before: hd(page)}, actor: author) do
            [] -> {:halt, {page, acc}}
            earlier -> {:cont, {ids(earlier), [ids(earlier) | acc]}}
          end
        end)
        |> elem(1)

      assert List.flatten(back) ++ last == ordered

      # forwards from the first message
      first_page = Enum.take(ordered, 40)

      forward =
        Enum.reduce_while(1..5, {List.last(first_page), []}, fn _, {cursor, acc} ->
          case Chat.page_messages!(room.id, %{after: cursor}, actor: author) do
            [] -> {:halt, {cursor, acc}}
            later -> {:cont, {ids(later) |> List.last(), acc ++ ids(later)}}
          end
        end)
        |> elem(1)

      assert first_page ++ forward == ordered
    end

    test "edges: before the first, after the last, around either end", %{
      room: room,
      author: author,
      messages: messages
    } do
      all_ids = ids(messages)
      first = hd(messages)
      last = List.last(messages)

      assert Chat.page_messages!(room.id, %{before: first.id}, actor: author) == []
      assert Chat.page_messages!(room.id, %{after: last.id}, actor: author) == []

      assert ids(Chat.page_messages!(room.id, %{around: first.id}, actor: author)) ==
               Enum.take(all_ids, 41)

      assert ids(Chat.page_messages!(room.id, %{around: last.id}, actor: author)) ==
               Enum.take(all_ids, -41)

      # a short page next to the edge is still ascending
      assert ids(Chat.page_messages!(room.id, %{before: Enum.at(messages, 2).id}, actor: author)) ==
               Enum.take(all_ids, 2)

      assert ids(Chat.page_messages!(room.id, %{after: Enum.at(messages, 97).id}, actor: author)) ==
               Enum.take(all_ids, -2)
    end

    test "a deleted cursor at the edges pages by id", %{
      room: room,
      author: author,
      messages: messages
    } do
      first = hd(messages)
      last = List.last(messages)
      Chat.destroy_message!(first, actor: author)
      Chat.destroy_message!(last, actor: author)

      assert Chat.page_messages!(room.id, %{before: first.id}, actor: author) == []
      assert Chat.page_messages!(room.id, %{after: last.id}, actor: author) == []

      assert ids(Chat.page_messages!(room.id, %{after: first.id}, actor: author)) ==
               messages |> Enum.slice(1, 40) |> ids()

      assert ids(Chat.page_messages!(room.id, %{before: last.id}, actor: author)) ==
               messages |> Enum.slice(59, 40) |> ids()
    end

    test "a non-member gets nothing for any cursor", %{room: room, messages: messages} do
      outsider = user_fixture()
      cursor = Enum.at(messages, 50)

      for params <- [%{}, %{before: cursor.id}, %{after: cursor.id}, %{around: cursor.id}] do
        assert Chat.page_messages!(room.id, params, actor: outsider) == []
      end
    end

    test "a cursor from another room only pages this room", %{room: room, author: author} do
      other_room = open_room_fixture(author)
      other = message_fixture(other_room, author)
      page = Chat.page_messages!(room.id, %{before: other.id}, actor: author)
      assert length(page) == 40
      assert Enum.all?(page, &(&1.room_id == room.id))
    end
  end

  describe "search" do
    test "matches messages in the actor's rooms, with stemming", %{
      room: room,
      author: author,
      member: member
    } do
      other_room = closed_room_fixture(author, [author])
      m1 = message_fixture(room, author, body: "I like eels")
      _m2 = message_fixture(room, author, body: "Nothing to see")
      m3 = message_fixture(other_room, author, body: "More eel talk")

      attachment =
        message_fixture(room, author,
          body: "",
          attachment_key: "k.pdf",
          attachment_filename: "eel-report.pdf"
        )

      assert Chat.search_messages!("eel", actor: author) |> ids() == [m1.id, m3.id, attachment.id]
      assert Chat.search_messages!("eels", actor: member) |> ids() == [m1.id, attachment.id]
      assert [%{room: %{}, creator: %{}} | _] = Chat.search_messages!("eel", actor: member)
      assert Chat.search_messages!("!!!", actor: author) == []
      assert Chat.search_messages!("eel & | !", actor: author) |> length() == 3
    end

    test "returns the last 100, ascending", %{room: room, author: author} do
      messages = for i <- 1..105, do: message_fixture(room, author, body: "needle #{i}")

      assert Chat.search_messages!("needle", actor: author) |> ids() ==
               messages |> Enum.take(-100) |> ids()
    end
  end

  describe "boosts" do
    test "members boost; only the booster deletes", %{room: room, author: author, member: member} do
      message = message_fixture(room, author)
      outsider = user_fixture()
      Broadcast.subscribe_room(room.id)

      assert {:error, %Ash.Error.Forbidden{}} = Chat.create_boost(message, "👍", actor: outsider)
      assert {:error, %Ash.Error.Invalid{}} = Chat.create_boost(message, "", actor: member)

      assert {:error, %Ash.Error.Invalid{}} =
               Chat.create_boost(message, String.duplicate("x", 17), actor: member)

      assert {:ok, boost} = Chat.create_boost(message, "🎉", actor: member)
      assert boost.booster.id == member.id
      assert_receive {:boost_created, %{id: id, content: "🎉", booster: %{}, message: broadcast}}
      assert id == boost.id
      assert broadcast.id == message.id
      assert [%{id: ^id, booster: %{id: booster_id}}] = broadcast.boosts
      assert booster_id == member.id
      assert boost.room_id == room.id

      assert [%{content: "🎉"}] =
               Chat.page_messages!(room.id, actor: author) |> List.last() |> Map.get(:boosts)

      assert {:error, %Ash.Error.Forbidden{}} = Chat.destroy_boost(boost, actor: author)
      assert {:error, %Ash.Error.Forbidden{}} = Chat.destroy_boost(boost, actor: admin_fixture())
      assert :ok = Chat.destroy_boost(boost, actor: member)
      assert_receive {:boost_deleted, %{id: ^id, message: %{boosts: []}}}
    end
  end

  describe "recent searches" do
    test "record upserts, keeps the 10 newest, and clears", %{author: author, member: member} do
      for i <- 1..12, do: Chat.record_search!("query #{i}", actor: author)
      Chat.record_search!("query 5", actor: author)
      Chat.record_search!("other", actor: member)

      queries = Chat.recent_searches!(actor: author) |> Enum.map(& &1.query)
      assert length(queries) == 10
      assert hd(queries) == "query 5"
      refute "query 1" in queries
      refute "query 2" in queries
      assert Enum.count(queries, &(&1 == "query 5")) == 1

      assert :ok = Chat.clear_searches(actor: author)
      assert Chat.recent_searches!(actor: author) == []
      assert [%{query: "other"}] = Chat.recent_searches!(actor: member)
    end
  end
end
