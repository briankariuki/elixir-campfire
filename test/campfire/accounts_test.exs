defmodule Campfire.AccountsTest do
  use Campfire.DataCase, async: true

  import Campfire.Fixtures

  alias Campfire.{Accounts, Broadcast, Chat}
  alias Campfire.Accounts.{Session, User}

  describe "first run" do
    test "creates the account, an administrator and the open room All Talk" do
      assert {:ok, %{account: account, user: user, room: room}} =
               Accounts.first_run(%{
                 name: "Jason",
                 email_address: "Jason@Example.com",
                 password: "pw"
               })

      assert account.name == "Campfire"
      assert account.join_code =~ ~r/\A[A-Za-z0-9]{4}-[A-Za-z0-9]{4}-[A-Za-z0-9]{4}\z/
      assert user.role == :administrator
      assert user.email_address == "jason@example.com"
      assert room.name == "All Talk"
      assert room.kind == :open
      assert [%{room_id: room_id}] = Chat.list_memberships!(actor: user)
      assert room_id == room.id
      assert Accounts.set_up?()
    end

    test "only runs once" do
      Accounts.first_run!(%{name: "A", email_address: "a@example.com", password: "pw"})

      assert {:error, :already_set_up} =
               Accounts.first_run(%{name: "B", email_address: "b@example.com", password: "pw"})
    end
  end

  describe "account" do
    test "join code checks and reset (admin only)" do
      admin = admin_fixture()
      member = user_fixture()
      account = account_fixture()

      assert Accounts.valid_join_code?(account.join_code)
      refute Accounts.valid_join_code?("nope")

      assert {:error, %Ash.Error.Forbidden{}} = Accounts.reset_join_code(account, actor: member)
      assert {:ok, reset} = Accounts.reset_join_code(account, actor: admin)
      assert reset.join_code != account.join_code
    end

    test "update is admin only" do
      admin = admin_fixture()
      member = user_fixture()
      account = account_fixture()

      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.update_account(account, %{name: "X"}, actor: member)

      assert {:ok, %{name: "Basecamp", restrict_room_creation_to_administrators: true}} =
               Accounts.update_account(
                 account,
                 %{name: "Basecamp", restrict_room_creation_to_administrators: true},
                 actor: admin
               )
    end

    test "anyone can read the account" do
      account = account_fixture()
      assert Accounts.get_account!().id == account.id
    end
  end

  describe "registration and sign in" do
    test "registering joins every open room, but not closed ones" do
      admin = admin_fixture()
      open1 = open_room_fixture(admin)
      open2 = open_room_fixture(admin)
      closed = closed_room_fixture(admin, [admin])

      {:ok, user} =
        Accounts.register_user(%{
          name: "David",
          email_address: "david@example.com",
          password: "pw"
        })

      assert user.role == :member

      room_ids = Chat.list_memberships!(actor: user) |> Enum.map(& &1.room_id) |> Enum.sort()
      assert room_ids == Enum.sort([open1.id, open2.id])
      refute closed.id in room_ids
    end

    test "duplicate emails are rejected" do
      user_fixture(email_address: "dup@example.com")

      assert {:error, _} =
               Accounts.register_user(%{
                 name: "X",
                 email_address: "DUP@example.com",
                 password: "pw"
               })
    end

    test "sign in with email and password, active users only" do
      user = user_fixture(email_address: "me@example.com", password: "right")

      assert {:ok, %User{id: id}} = Accounts.sign_in("Me@example.com", "right")
      assert id == user.id
      assert {:ok, nil} = Accounts.sign_in("me@example.com", "wrong")
      assert {:ok, nil} = Accounts.sign_in("nobody@example.com", "right")

      Accounts.deactivate_user!(user, actor: admin_fixture())
      assert {:ok, nil} = Accounts.sign_in("me@example.com", "right")
    end

    test "helpers" do
      user = user_fixture(name: "Jason Fried")
      assert User.initials(user) == "JF"
      assert Ash.load!(user, :initials, authorize?: false).initials == "JF"
      refute User.bot_key(user)
    end
  end

  describe "profile" do
    test "users update their own profile and password" do
      user = user_fixture(password: "old")
      other = user_fixture()

      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.update_profile(other, %{name: "Hacked"}, actor: user)

      assert {:ok, updated} =
               Accounts.update_profile(user, %{name: "New Name", bio: "Hi", password: "new"},
                 actor: user
               )

      assert updated.name == "New Name"
      assert {:ok, %User{}} = Accounts.sign_in(user.email_address, "new")
      assert {:ok, nil} = Accounts.sign_in(user.email_address, "old")
    end

    test "set_last_room" do
      user = user_fixture()
      assert {:ok, %{last_room_id: 42}} = Accounts.set_last_room(user, 42, actor: user)
    end
  end

  describe "listing users" do
    test "people excludes bots, deactivated and (by default) banned users" do
      admin = admin_fixture(name: "Admin")
      active = user_fixture(name: "active")
      banned = user_fixture()
      deactivated = user_fixture()
      bot = bot_fixture()
      Accounts.ban_user!(banned, actor: admin)
      Accounts.deactivate_user!(deactivated, actor: admin)

      ids = Accounts.list_users!(actor: active) |> Enum.map(& &1.id)
      assert active.id in ids
      assert admin.id in ids
      refute banned.id in ids
      refute deactivated.id in ids
      refute bot.id in ids

      ids =
        Accounts.list_users!(%{include_banned: true, include_bots: true}, actor: admin)
        |> Enum.map(& &1.id)

      assert banned.id in ids
      assert bot.id in ids
    end

    test "reading users requires an actor" do
      user = user_fixture()
      # Read policies filter, so unauthorized reads look like "not found".
      assert {:error, %Ash.Error.Invalid{}} = Accounts.get_user(user.id)
      assert {:ok, %User{}} = Accounts.get_user(user.id, actor: user)
    end
  end

  describe "roles" do
    test "admins change roles; only member/administrator are possible" do
      admin = admin_fixture()
      user = user_fixture()

      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.change_role(user, :administrator, actor: user)

      assert {:ok, %{role: :administrator}} =
               Accounts.change_role(user, :administrator, actor: admin)

      assert {:ok, %{role: :member}} = Accounts.change_role(user, "member", actor: admin)
      # Anything else becomes a member.
      {:ok, admin_user} = Accounts.change_role(user, :administrator, actor: admin)
      assert {:ok, %{role: :member}} = Accounts.change_role(admin_user, :bot, actor: admin)
      assert {:error, _} = Accounts.change_role(bot_fixture(), :administrator, actor: admin)
    end
  end

  describe "sessions" do
    test "create, look up by token, touch and destroy" do
      user = user_fixture()
      session = session_fixture(user, ip_address: "1.2.3.4")
      assert session.user_id == user.id
      assert byte_size(session.token) >= 32

      assert %Session{id: id, user: %User{}} = Accounts.get_session_by_token(session.token)
      assert id == session.id
      refute Accounts.get_session_by_token("nope")

      # Fresh sessions aren't written to.
      assert {:ok, ^session} = Accounts.touch_session(session, %{ip_address: "5.6.7.8"})

      stale = %{session | last_active_at: DateTime.add(DateTime.utc_now(), -2, :hour)}
      assert {:ok, touched} = Accounts.touch_session(stale, %{ip_address: "5.6.7.8"})
      assert touched.ip_address == "5.6.7.8"

      Phoenix.PubSub.subscribe(Campfire.PubSub, Broadcast.socket_id(user.id))

      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.destroy_session(session, actor: user_fixture())

      assert :ok = Accounts.destroy_session(session, actor: user)
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
      refute Accounts.get_session_by_token(session.token)
    end

    test "sessions of inactive users are not found" do
      user = user_fixture()
      session = session_fixture(user)
      Accounts.deactivate_user!(user, actor: admin_fixture())
      refute Accounts.get_session_by_token(session.token)
    end
  end

  describe "deactivate" do
    test "removes non-direct memberships, sessions and searches, mangles the email, disconnects" do
      admin = admin_fixture()
      user = user_fixture(email_address: "gone@example.com")
      open = open_room_fixture(admin)
      direct = direct_room_fixture(admin, [user])
      session_fixture(user)
      Chat.record_search!("hello", actor: user)
      Phoenix.PubSub.subscribe(Campfire.PubSub, Broadcast.socket_id(user.id))

      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.deactivate_user(user, actor: user_fixture())

      assert {:error, %Ash.Error.Forbidden{}} = Accounts.deactivate_user(admin, actor: admin)
      assert {:ok, user} = Accounts.deactivate_user(user, actor: admin)

      assert user.status == :deactivated
      assert user.email_address =~ ~r/\Agone-deactivated-[0-9a-f-]{36}@example\.com\z/
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}

      room_ids = Chat.list_memberships!(actor: user) |> Enum.map(& &1.room_id)
      assert room_ids == [direct.id]
      refute open.id in room_ids
      assert Chat.recent_searches!(actor: user) == []
      assert Ash.read!(Session, authorize?: false) |> Enum.filter(&(&1.user_id == user.id)) == []

      # The email can be used again.
      assert {:ok, _} =
               Accounts.register_user(%{
                 name: "New",
                 email_address: "gone@example.com",
                 password: "pw"
               })
    end
  end

  describe "ban" do
    test "bans public session IPs, deletes sessions and messages, disconnects; unban restores" do
      admin = admin_fixture()
      user = user_fixture()
      room = open_room_fixture(admin)
      session_fixture(user, ip_address: "8.8.4.4")
      session_fixture(user, ip_address: "8.8.4.4")
      session_fixture(user, ip_address: "192.168.1.2")
      session_fixture(user, ip_address: "127.0.0.1")
      message = message_fixture(room, user)
      other_message = message_fixture(room, admin)

      Broadcast.subscribe_room(room.id)
      Phoenix.PubSub.subscribe(Campfire.PubSub, Broadcast.socket_id(user.id))

      assert {:error, %Ash.Error.Forbidden{}} = Accounts.ban_user(user, actor: user_fixture())
      assert {:error, %Ash.Error.Forbidden{}} = Accounts.ban_user(admin, actor: admin)
      assert {:ok, banned} = Accounts.ban_user(user, actor: admin)

      assert banned.status == :banned
      assert Accounts.banned_ip?("8.8.4.4")
      refute Accounts.banned_ip?("192.168.1.2")
      refute Accounts.banned_ip?("127.0.0.1")
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
      assert_receive {:message_deleted, %{id: deleted_id}}
      assert deleted_id == message.id

      assert {:error, _} = Chat.get_message(message.id, actor: admin)
      assert {:ok, _} = Chat.get_message(other_message.id, actor: admin)
      assert Ash.read!(Session, authorize?: false) |> Enum.filter(&(&1.user_id == user.id)) == []

      assert {:ok, %{status: :active}} = Accounts.unban_user(banned, actor: admin)
      refute Accounts.banned_ip?("8.8.4.4")
    end

    test "public_ip?" do
      alias Campfire.Accounts.Ban
      assert Ban.public_ip?("8.8.8.8")
      assert Ban.public_ip?("2001:4860:4860::8888")
      refute Ban.public_ip?("10.0.0.1")
      refute Ban.public_ip?("172.16.5.4")
      refute Ban.public_ip?("169.254.1.1")
      refute Ban.public_ip?("::1")
      refute Ban.public_ip?("fe80::1")
      refute Ban.public_ip?("::ffff:192.168.0.1")
      refute Ban.public_ip?("not an ip")
    end
  end

  describe "bots" do
    test "admins create bots that join open rooms; webhook optional" do
      admin = admin_fixture()
      member = user_fixture()
      room = open_room_fixture(admin)

      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.create_bot(%{name: "Nope"}, actor: member)

      assert {:ok, bot} =
               Accounts.create_bot(%{name: "Helper", webhook_url: "https://example.com/hook"},
                 actor: admin
               )

      assert bot.role == :bot
      assert String.length(bot.bot_token) == 12
      assert Campfire.Accounts.User.bot_key(bot) == "#{bot.id}-#{bot.bot_token}"
      assert {:ok, %{room_id: room_id}} = Chat.get_membership(room.id, actor: bot)
      assert room_id == room.id

      [listed] = Accounts.list_bots!(actor: admin)
      assert listed.webhook.url == "https://example.com/hook"
    end

    test "update_bot with a blank webhook_url deletes the webhook" do
      admin = admin_fixture()
      bot = bot_fixture(webhook_url: "https://example.com/hook")

      assert {:ok, bot} =
               Accounts.update_bot(bot, %{name: "Renamed", webhook_url: "https://example.com/2"},
                 actor: admin
               )

      assert Ash.load!(bot, :webhook, authorize?: false).webhook.url == "https://example.com/2"

      # Omitting webhook_url leaves the webhook alone.
      assert {:ok, bot} = Accounts.update_bot(bot, %{name: "Renamed"}, actor: admin)
      assert Ash.load!(bot, :webhook, authorize?: false).webhook.url == "https://example.com/2"

      assert {:ok, %{name: "Renamed"}} =
               Accounts.update_bot(bot, %{webhook_url: ""}, actor: admin)

      assert Ash.load!(bot, :webhook, authorize?: false).webhook == nil

      assert {:error, _} = Accounts.update_bot(bot, %{webhook_url: "not a url"}, actor: admin)
    end

    test "authenticate_bot checks id, token, role and status" do
      admin = admin_fixture()
      bot = bot_fixture()
      key = User.bot_key(bot)

      assert {:ok, %User{id: id}} = Accounts.authenticate_bot(key)
      assert id == bot.id
      assert {:ok, nil} = Accounts.authenticate_bot("#{bot.id}-wrong")
      assert {:ok, nil} = Accounts.authenticate_bot("#{bot.id}-")
      assert {:ok, nil} = Accounts.authenticate_bot("garbage")
      assert {:ok, nil} = Accounts.authenticate_bot("#{admin.id}-#{bot.bot_token}")

      {:ok, reset} = Accounts.reset_bot_key(bot, actor: admin)
      assert reset.bot_token != bot.bot_token
      assert {:ok, nil} = Accounts.authenticate_bot(key)
      assert {:ok, %User{}} = Accounts.authenticate_bot(User.bot_key(reset))

      Accounts.deactivate_user!(reset, actor: admin)
      assert {:ok, nil} = Accounts.authenticate_bot(User.bot_key(reset))
    end
  end
end
