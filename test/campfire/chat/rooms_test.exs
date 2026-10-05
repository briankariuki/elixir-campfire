defmodule Campfire.Chat.RoomsTest do
  use Campfire.DataCase, async: true

  import Campfire.Fixtures

  alias Campfire.{Accounts, Broadcast, Chat}
  alias Campfire.Chat.Room

  defp member_ids(room) do
    room.id |> Campfire.Chat.Membership.member_ids() |> Enum.sort()
  end

  defp involvement(room, user) do
    Chat.get_membership!(room.id, actor: user).involvement
  end

  describe "open rooms" do
    test "every active user (bots included) becomes a member" do
      admin = admin_fixture()
      user = user_fixture()
      bot = bot_fixture()
      deactivated = user_fixture()
      Accounts.deactivate_user!(deactivated, actor: admin)
      Broadcast.subscribe_user(user.id)

      assert {:ok, room} = Chat.create_open_room("Watercooler", actor: user)
      assert room.kind == :open
      assert room.creator_id == user.id
      assert member_ids(room) == Enum.sort([admin.id, user.id, bot.id])
      assert involvement(room, user) == :mentions
      assert_receive :sidebar_changed
    end

    test "bots and inactive users can't create rooms" do
      bot = bot_fixture()

      assert {:error, %Ash.Error.Forbidden{}} = Chat.create_open_room("Nope", actor: bot)
      assert {:error, _} = Chat.create_open_room("Nope")
    end

    test "creation can be restricted to administrators" do
      admin = admin_fixture()
      user = user_fixture()
      account_fixture(%{restrict_room_creation_to_administrators: true})

      refute Chat.can_create_open_room?(user, "Nope")
      assert Chat.can_create_open_room?(admin, "Yes")
      assert {:error, %Ash.Error.Forbidden{}} = Chat.create_open_room("Nope", actor: user)

      assert {:error, %Ash.Error.Forbidden{}} =
               Chat.create_closed_room("Nope", [user.id], actor: user)

      assert {:ok, _} = Chat.create_open_room("Yes", actor: admin)
      assert {:ok, _} = Chat.create_closed_room("Yes", [admin.id], actor: admin)
      # Direct rooms are always allowed.
      assert {:ok, _} = Chat.find_or_create_direct_room([admin.id], actor: user)
    end
  end

  describe "closed rooms" do
    test "only the given users become members (the creator isn't added automatically)" do
      creator = user_fixture()
      a = user_fixture()
      b = user_fixture()
      _outsider = user_fixture()

      assert {:ok, room} = Chat.create_closed_room("Secret", [a.id, b.id], actor: creator)
      assert room.kind == :closed
      assert member_ids(room) == Enum.sort([a.id, b.id])

      assert {:ok, room} = Chat.create_closed_room("Mine", [creator.id, a.id], actor: creator)
      assert member_ids(room) == Enum.sort([creator.id, a.id])
    end

    test "update_closed renames, grants and revokes" do
      creator = user_fixture()
      a = user_fixture()
      b = user_fixture()
      c = user_fixture()
      room = closed_room_fixture(creator, [creator, a, b])
      Broadcast.subscribe_user(b.id)

      assert {:ok, room} =
               Chat.update_closed_room(
                 room,
                 %{name: "Renamed", user_ids: [creator.id, a.id, c.id]},
                 actor: creator
               )

      assert room.name == "Renamed"
      assert member_ids(room) == Enum.sort([creator.id, a.id, c.id])
      assert_receive {:room_removed, room_id}
      assert room_id == room.id
    end

    test "a user revoked by update_closed is told once, and only after the commit" do
      creator = user_fixture()
      keep = user_fixture()
      gone = user_fixture()
      room = closed_room_fixture(creator, [creator, keep, gone])
      Broadcast.subscribe_user(gone.id)
      room_id = room.id

      {:ok, notifications} =
        Ash.DataLayer.transaction(Room, fn ->
          {:ok, _room, notifications} =
            Chat.update_closed_room(room, %{user_ids: [creator.id, keep.id]},
              actor: creator,
              return_notifications?: true
            )

          refute_received {:room_removed, _}
          refute_received :sidebar_changed
          notifications
        end)

      Ash.Notifier.notify(notifications)

      assert_received {:room_removed, ^room_id}
      assert_received :sidebar_changed
      refute_received {:room_removed, _}
      refute_received :sidebar_changed
    end
  end

  describe "conversion" do
    test "closed -> open grants every active user; open -> closed revokes" do
      admin = admin_fixture()
      creator = user_fixture()
      a = user_fixture()
      room = closed_room_fixture(creator, [creator])

      assert {:ok, room} = Chat.update_open_room(room, %{name: "Now open"}, actor: creator)
      assert room.kind == :open
      assert member_ids(room) == Enum.sort([admin.id, creator.id, a.id])

      assert {:ok, room} =
               Chat.update_closed_room(room, %{user_ids: [creator.id, a.id]}, actor: admin)

      assert room.kind == :closed
      assert room.name == "Now open"
      assert member_ids(room) == Enum.sort([creator.id, a.id])
    end

    test "only admins and the creator may update" do
      creator = user_fixture()
      other = user_fixture()
      room = open_room_fixture(creator)

      assert {:error, %Ash.Error.Forbidden{}} =
               Chat.update_open_room(room, %{name: "Mine now"}, actor: other)

      assert {:ok, _} = Chat.update_open_room(room, %{name: "Ok"}, actor: admin_fixture())
    end

    test "direct rooms can never change kind" do
      admin = admin_fixture()
      user = user_fixture()
      direct = direct_room_fixture(admin, [user])

      assert {:error, %Ash.Error.Invalid{}} =
               Chat.update_open_room(direct, %{name: "x"}, actor: admin)

      assert {:error, %Ash.Error.Invalid{}} =
               Chat.update_closed_room(direct, %{user_ids: [admin.id]}, actor: admin)
    end
  end

  describe "direct rooms" do
    test "find_or_create_direct always includes the actor and is idempotent" do
      me = user_fixture()
      you = user_fixture()
      them = user_fixture()

      assert {:ok, room} = Chat.find_or_create_direct_room([you.id], actor: me)
      assert room.kind == :direct
      assert room.name == nil
      assert room.direct_key == Room.direct_key([me.id, you.id])
      assert member_ids(room) == Enum.sort([me.id, you.id])
      assert involvement(room, me) == :everything
      assert involvement(room, you) == :everything

      assert {:ok, same} = Chat.find_or_create_direct_room([me.id, you.id], actor: you)
      assert same.id == room.id
      assert {:ok, same} = Chat.find_or_create_direct_room([you.id, me.id, you.id], actor: me)
      assert same.id == room.id

      assert {:ok, group} = Chat.find_or_create_direct_room([you.id, them.id], actor: me)
      assert group.id != room.id
      assert member_ids(group) == Enum.sort([me.id, you.id, them.id])
    end

    test "any member can delete a direct room; others can't" do
      me = user_fixture()
      you = user_fixture()
      outsider = user_fixture()
      room = direct_room_fixture(me, [you])

      assert {:error, _} = Chat.destroy_room(room, actor: outsider)
      assert :ok = Chat.destroy_room(room, actor: you)
    end
  end

  describe "reading" do
    test "users only see rooms they are members of" do
      creator = user_fixture()
      member = user_fixture()
      outsider = user_fixture()
      room = closed_room_fixture(creator, [creator, member])

      assert {:ok, _} = Chat.get_room(room.id, actor: member)
      assert {:error, _} = Chat.get_room(room.id, actor: outsider)
      assert room.id in Enum.map(Chat.list_rooms!(actor: member), & &1.id)
      refute room.id in Enum.map(Chat.list_rooms!(actor: outsider), & &1.id)
    end

    test "members can load the room's users" do
      creator = user_fixture()
      member = user_fixture()
      room = closed_room_fixture(creator, [creator, member])

      users = Ash.load!(room, :users, actor: member).users
      assert Enum.sort(Enum.map(users, & &1.id)) == Enum.sort([creator.id, member.id])
    end
  end

  describe "destroy" do
    test "admin or creator destroys a shared room with its messages; members are told" do
      creator = user_fixture()
      member = user_fixture()
      room = closed_room_fixture(creator, [creator, member])
      message = message_fixture(room, member)
      Broadcast.subscribe_user(member.id)

      assert {:error, %Ash.Error.Forbidden{}} = Chat.destroy_room(room, actor: member)
      assert :ok = Chat.destroy_room(room, actor: creator)

      assert_receive {:room_removed, room_id}
      assert room_id == room.id
      assert_receive :sidebar_changed
      assert {:error, _} = Chat.get_message(message.id, actor: member)
      assert member_ids(room) == []
    end
  end

  describe "memberships" do
    test "involvement and mark_read on own membership only" do
      creator = user_fixture()
      member = user_fixture()
      room = closed_room_fixture(creator, [creator, member])
      membership = Chat.get_membership!(room.id, actor: member)
      Broadcast.subscribe_user(member.id)

      assert {:error, %Ash.Error.Forbidden{}} =
               Chat.set_involvement(membership, :everything, actor: creator)

      assert {:ok, %{involvement: :invisible}} =
               Chat.set_involvement(membership, :invisible, actor: member)

      assert_receive :sidebar_changed

      message_fixture(room, creator)
      membership = Chat.get_membership!(room.id, actor: member)
      assert membership.unread_at == nil, "invisible members aren't marked unread"

      {:ok, _} = Chat.set_involvement(membership, :mentions, actor: member)
      message_fixture(room, creator)
      membership = Chat.get_membership!(room.id, actor: member)
      assert membership.unread_at

      assert {:error, %Ash.Error.Forbidden{}} = Chat.mark_read(membership, actor: creator)
      assert {:ok, %{unread_at: nil}} = Chat.mark_read(membership, actor: member)
      assert_receive {:room_read, room_id}
      assert room_id == room.id
    end

    test "list_memberships returns the actor's memberships with rooms loaded" do
      user = user_fixture()
      room = open_room_fixture(user)
      assert [%{room: %Room{id: id}}] = Chat.list_memberships!(actor: user)
      assert id == room.id
    end

    test "revoke (admin or room creator) tells the user" do
      creator = user_fixture()
      member = user_fixture()
      room = closed_room_fixture(creator, [creator, member])
      membership = Chat.get_membership!(room.id, actor: member)
      Broadcast.subscribe_user(member.id)

      assert {:error, %Ash.Error.Forbidden{}} = Chat.revoke_membership(membership, actor: member)
      assert :ok = Chat.revoke_membership(membership, actor: creator)
      assert_receive {:room_removed, _}
      assert member_ids(room) == [creator.id]
    end

    test "grants are idempotent" do
      user = user_fixture()
      room = open_room_fixture(user)
      assert Campfire.Chat.Membership.grant(room, [user.id, user.id]) == []
      assert member_ids(room) == [user.id]
    end

    test "grant returns only the newly granted users and keeps existing rows" do
      creator = user_fixture()
      other = user_fixture()
      room = closed_room_fixture(creator, [creator])

      Chat.set_involvement!(Chat.get_membership!(room.id, actor: creator), :everything,
        actor: creator
      )

      assert Campfire.Chat.Membership.grant(room, [creator.id, other.id]) == [other.id]
      assert involvement(room, creator) == :everything
      assert involvement(room, other) == :mentions
    end

    test "bulk revocation tells every revoked user" do
      creator = user_fixture()
      one = user_fixture()
      two = user_fixture()
      room = closed_room_fixture(creator, [creator, one, two])
      Broadcast.subscribe_user(one.id)
      Broadcast.subscribe_user(two.id)

      assert Enum.sort(Campfire.Chat.Membership.revoke(room.id, [one.id, two.id])) ==
               Enum.sort([one.id, two.id])

      room_id = room.id
      assert_receive {:room_removed, ^room_id}
      assert_receive {:room_removed, ^room_id}
      assert member_ids(room) == [creator.id]
    end

    test "revoke_all_except_direct keeps direct rooms and tells the user" do
      user = user_fixture()
      friend = user_fixture()
      open = open_room_fixture(user)
      closed = closed_room_fixture(friend, [friend, user])
      {:ok, direct} = Chat.find_or_create_direct_room([friend.id], actor: user)
      Broadcast.subscribe_user(user.id)

      assert :ok = Campfire.Chat.Membership.revoke_all_except_direct(user.id)

      open_id = open.id
      closed_id = closed.id
      assert_receive {:room_removed, ^open_id}
      assert_receive {:room_removed, ^closed_id}
      assert user.id in member_ids(direct)
      refute user.id in member_ids(open)
      refute user.id in member_ids(closed)
    end
  end
end
