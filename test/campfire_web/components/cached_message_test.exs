defmodule CampfireWeb.CachedMessageTest do
  use Campfire.DataCase, async: true

  import Phoenix.LiveViewTest
  import Campfire.Fixtures

  alias Campfire.{Accounts, Broadcast, Chat}
  alias Campfire.Chat.Message
  alias CampfireWeb.{MessageBody.Cache, MessageComponents}

  setup do
    author = user_fixture(name: "Author")
    member = user_fixture(name: "Member")
    admin = admin_fixture(name: "Admin")
    room = closed_room_fixture(author, [author, member, admin])
    Broadcast.subscribe_room(room.id)
    %{author: author, member: member, admin: admin, room: room}
  end

  # The message as the room LiveViews load it
  defp reload(message, actor),
    do: Chat.get_message!(message.id, actor: actor, load: Message.loads())

  defp assigns(message, viewer, extra) do
    Keyword.merge(
      [
        id: "messages-#{message.client_message_id}",
        message: message,
        current_user: viewer,
        users: %{}
      ],
      extra
    )
  end

  defp cached(message, viewer, extra \\ []),
    do: render_component(&MessageComponents.cached_message/1, assigns(message, viewer, extra))

  defp uncached(message, viewer, extra \\ []),
    do: render_component(&MessageComponents.message/1, assigns(message, viewer, extra))

  test "renders exactly what message/1 renders, for every kind of viewer", %{
    author: author,
    member: member,
    admin: admin,
    room: room
  } do
    message = message_fixture(room, author, %{body: "Hi @Member, **bold** https://example.com"})
    assert_receive {:message_created, _}
    {:ok, _boost} = Chat.create_boost(message, "👍", actor: member)
    {:ok, _boost} = Chat.create_boost(message, "🎉", actor: admin)
    assert_receive {:boost_created, _first}
    assert_receive {:boost_created, %{message: broadcast}}
    users = %{author.id => author, member.id => member, admin.id => admin}

    for viewer <- [author, member, admin, user_fixture()] do
      assert cached(broadcast, viewer, users: users) == uncached(broadcast, viewer, users: users)
      # and again, from the cache
      assert cached(broadcast, viewer, users: users) == uncached(broadcast, viewer, users: users)
    end
  end

  test "broadcast messages carry their digest, which follows every change", %{
    author: author,
    member: member,
    room: room
  } do
    message = message_fixture(room, author, %{body: "digest me"})
    assert_receive {:message_created, %{__metadata__: %{digest: created}} = broadcast}
    assert is_binary(created)
    assert Message.digest(broadcast) == created

    {:ok, _} = Chat.update_message(message, %{body: "digest me again"}, actor: author)
    assert_receive {:message_updated, %{__metadata__: %{digest: updated}}}

    {:ok, _boost} = Chat.create_boost(message, "🔥", actor: member)
    assert_receive {:boost_created, %{message: %{__metadata__: %{digest: boosted}}}}

    assert length(Enum.uniq([created, updated, boosted])) == 3

    # a message that did not come from a broadcast gets one computed, and it follows the content
    plain = Map.put(broadcast, :__metadata__, %{})
    assert is_binary(Message.digest(plain))
    refute Message.digest(plain) == Message.digest(%{plain | body: "other"})
  end

  test "viewers who differ get different markup, viewers who don't share one entry", %{
    author: author,
    member: member,
    room: room
  } do
    message = message_fixture(room, author, %{body: "Hi @Member"})
    assert_receive {:message_created, broadcast}
    users = %{author.id => author, member.id => member}
    other = user_fixture()

    own = cached(broadcast, author, users: users)
    mentioned = cached(broadcast, member, users: users)
    plain = cached(broadcast, other, users: users)

    assert own =~ "message--me"
    assert mentioned =~ "message--mentioned"
    refute plain =~ "message--me"
    refute plain =~ "message--mentioned"
    assert own =~ "message__edit-btn"
    refute plain =~ "message__edit-btn"

    size = Cache.size(CampfireWeb.MessageHtmlCache)
    assert cached(broadcast, user_fixture(), users: users) == plain
    assert Cache.size(CampfireWeb.MessageHtmlCache) == size
    assert message.id == broadcast.id
  end

  test "a changed message renders again: edit, boost, rename, highlight", %{
    author: author,
    member: member,
    room: room
  } do
    message = message_fixture(room, author, %{body: "before"})
    assert_receive {:message_created, created}
    assert cached(created, member) =~ "before"

    {:ok, _} = Chat.update_message(message, %{body: "after"}, actor: author)
    assert_receive {:message_updated, updated}
    assert cached(updated, member) == uncached(updated, member)
    assert cached(updated, member) =~ "after"

    {:ok, _boost} = Chat.create_boost(updated, "🔥", actor: member)
    assert_receive {:boost_created, %{message: boosted}}
    assert cached(boosted, member) == uncached(boosted, member)
    assert cached(boosted, member) =~ "boost__delete"
    refute cached(boosted, author) =~ "boost__delete"

    {:ok, _} = Accounts.update_profile(author, %{name: "Renamed Author"}, actor: author)
    renamed = reload(message, member)
    assert cached(renamed, member) == uncached(renamed, member)
    assert cached(renamed, member) =~ "Renamed Author"

    assert cached(renamed, member, highlighted: true) ==
             uncached(renamed, member, highlighted: true)

    assert cached(renamed, member, highlighted: true) =~ "search-highlight"
    refute cached(renamed, member) =~ "search-highlight"
  end

  test "a message being edited or boosted by this viewer is never shared", %{
    author: author,
    member: member,
    room: room
  } do
    message_fixture(room, author, %{body: "edit me"})
    assert_receive {:message_created, message}

    editing = Ash.Resource.put_metadata(message, :editing, true)
    boosting = Ash.Resource.put_metadata(message, :boosting, true)

    assert cached(editing, author) == uncached(editing, author)
    assert cached(editing, author) =~ "edit-form-"
    assert cached(boosting, member) == uncached(boosting, member)
    assert cached(boosting, member) =~ "boost-form-"
    refute cached(message, author) =~ "edit-form-"
    refute cached(message, member) =~ "boost-form-"
  end

  test "attachments and sounds render the same too", %{author: author, room: room} do
    message_fixture(room, author, %{body: "/play tada"})
    assert_receive {:message_created, sound}

    attachment =
      Chat.create_message!(
        room,
        %{
          attachment_key: "k/1",
          attachment_filename: "photo.png",
          attachment_content_type: "image/png",
          attachment_byte_size: 10,
          attachment_width: 800,
          attachment_height: 600
        },
        actor: author
      )

    assert_receive {:message_created, broadcast}
    assert broadcast.id == attachment.id

    for message <- [sound, broadcast] do
      assert cached(message, author) == uncached(message, author)
    end
  end
end
