defmodule CampfireWeb.SettingsLiveTest do
  use CampfireWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Campfire.Fixtures

  alias Campfire.{Accounts, Chat}

  setup do
    account_fixture()
    :ok
  end

  describe "UserLive" do
    test "members see the profile and can ping, but get no admin tools", %{conn: conn} do
      me = user_fixture()
      other = user_fixture(name: "Jason Fried", bio: "Co-founder")

      {:ok, view, html} = conn |> log_in_user(me) |> live(~p"/users/#{other.id}")
      assert html =~ "Jason Fried"
      assert html =~ "Co-founder"
      refute html =~ other.email_address
      refute has_element?(view, "#ban-user")
      refute has_element?(view, "#session_transfer_url")

      {:error, {:live_redirect, %{to: to}}} = view |> element("#ping-user") |> render_click()
      {:ok, room} = Chat.find_or_create_direct_room([other.id], actor: me)
      assert to == ~p"/rooms/#{room.id}"
    end

    test "admins see the email and transfer link, and can ban and unban", %{conn: conn} do
      admin = admin_fixture()
      other = user_fixture()

      {:ok, view, html} = conn |> log_in_user(admin) |> live(~p"/users/#{other.id}")
      assert html =~ other.email_address
      assert has_element?(view, "#session_transfer_url")

      view |> element("#ban-user") |> render_click()
      assert reload(other).status == :banned
      assert has_element?(view, ".banned")
      assert has_element?(view, "#unban-user")

      view |> element("#unban-user") |> render_click()
      assert reload(other).status == :active
      assert has_element?(view, "#ban-user")
    end

    test "a member can't ban through a crafted event", %{conn: conn} do
      me = user_fixture()
      other = user_fixture()

      {:ok, view, _html} = conn |> log_in_user(me) |> live(~p"/users/#{other.id}")
      assert render_click(view, "ban", %{}) =~ "allowed"
      assert reload(other).status == :active
    end

    test "deactivated users", %{conn: conn} do
      admin = admin_fixture()
      other = user_fixture(name: "Gone Person")
      {:ok, _} = Accounts.deactivate_user(other, actor: admin)

      {:ok, _view, html} = conn |> log_in_user(admin) |> live(~p"/users/#{other.id}")
      assert html =~ "is no longer on this account"
    end
  end

  describe "ProfileLive" do
    setup :register_and_log_in_user

    test "updates the profile", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/profile")

      view
      |> form("#profile-form", user: %{name: "New Name", bio: "Hi there", password: ""})
      |> render_submit()

      user = reload(user)
      assert user.name == "New Name"
      assert user.bio == "Hi there"
      assert {:ok, %{}} = Accounts.sign_in(user.email_address, "secret123")
    end

    test "shows validation errors", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/profile")

      html =
        view
        |> form("#profile-form", user: %{name: ""})
        |> render_submit()

      assert html =~ "input-error"
    end

    test "uploads and deletes the avatar", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/profile")

      avatar =
        file_input(view, "#avatar-form", :avatar, [
          %{name: "me.png", content: "PNGDATA", type: "image/png"}
        ])

      render_upload(avatar, "me.png")
      key = reload(user).avatar_key
      assert key && Campfire.Uploads.exists?(key)

      view |> element("#delete-avatar") |> render_click()
      assert reload(user).avatar_key == nil
      refute Campfire.Uploads.exists?(key)
    end

    test "rejects uploads that aren't both an image name and an image type", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/profile")

      for {name, type} <- [{"evil.html", "image/png"}, {"me.png", "text/html"}] do
        avatar =
          file_input(view, "#avatar-form", :avatar, [
            %{name: name, content: "<script>alert(1)</script>", type: type}
          ])

        assert render_upload(avatar, name) =~ "Please choose an image"
        assert reload(user).avatar_key == nil
      end
    end

    test "save ignores avatar_key", %{conn: conn, user: user} do
      {:ok, key} = Campfire.Uploads.store_binary("<script>", "evil.html")
      {:ok, view, _html} = live(conn, ~p"/profile")

      render_submit(view, "save", %{"user" => %{"name" => "Renamed", "avatar_key" => key}})

      user = reload(user)
      assert user.name == "Renamed"
      assert user.avatar_key == nil
    end

    test "cycles the involvement bell", %{conn: conn, user: user} do
      room = open_room_fixture(admin_fixture(), "Watercooler")
      {:ok, membership} = Chat.get_membership(room.id, actor: user)
      assert membership.involvement == :mentions

      {:ok, view, html} = live(conn, ~p"/profile")
      assert html =~ "Watercooler"

      for expected <- [:everything, :nothing, :invisible, :mentions] do
        view |> element("#involvement-#{membership.id}") |> render_click()
        assert {:ok, %{involvement: ^expected}} = Chat.get_membership(room.id, actor: user)
      end
    end

    test "direct rooms toggle between everything and nothing", %{conn: conn, user: user} do
      other = user_fixture(name: "Pinged Person")
      room = direct_room_fixture(user, [other])
      {:ok, membership} = Chat.get_membership(room.id, actor: user)

      {:ok, view, html} = live(conn, ~p"/profile")
      assert html =~ "Pinged Person"

      view |> element("#involvement-#{membership.id}") |> render_click()
      assert {:ok, %{involvement: :nothing}} = Chat.get_membership(room.id, actor: user)
      view |> element("#involvement-#{membership.id}") |> render_click()
      assert {:ok, %{involvement: :everything}} = Chat.get_membership(room.id, actor: user)
    end

    test "shows the transfer link and logout", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/profile")
      assert has_element?(view, "#session_transfer_url")
      assert has_element?(view, ~s(a[href="/session"][data-method="delete"]))
    end
  end

  describe "AccountLive" do
    test "members see the invite link and people, but no admin tools", %{conn: conn} do
      me = user_fixture()
      admin = admin_fixture(name: "Admin Person")
      account = account_fixture()

      {:ok, view, html} = conn |> log_in_user(me) |> live(~p"/account")
      assert html =~ "/join/#{account.join_code}"
      assert html =~ "Admin Person"
      refute has_element?(view, "#regenerate-join-code")
      refute has_element?(view, "#role-#{admin.id}")
      refute has_element?(view, "#restrict-room-creation")
    end

    test "members can't trigger admin events", %{conn: conn} do
      me = user_fixture()
      other = user_fixture()
      account = account_fixture()

      {:ok, view, _html} = conn |> log_in_user(me) |> live(~p"/account")

      assert render_click(view, "toggle_restrict", %{}) =~ "allowed"
      assert render_click(view, "regenerate_join_code", %{}) =~ "allowed"
      render_click(view, "toggle_role", %{"id" => to_string(other.id)})
      render_click(view, "remove_user", %{"id" => to_string(other.id)})

      assert account_fixture() == account
      assert reload(other).role == :member
      assert reload(other).status == :active
    end

    test "admins toggle roles, remove people, regenerate the code and restrict rooms", %{
      conn: conn
    } do
      admin = admin_fixture()
      other = user_fixture()
      account = account_fixture()

      {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/account")

      assert has_element?(view, "#role-#{admin.id}[disabled]")

      view |> element("#role-#{other.id}") |> render_click()
      assert reload(other).role == :administrator
      view |> element("#role-#{other.id}") |> render_click()
      assert reload(other).role == :member

      view |> element("#regenerate-join-code") |> render_click()
      new_code = account_fixture().join_code
      assert new_code != account.join_code
      assert render(view) =~ "/join/#{new_code}"

      view |> element("#restrict-room-creation") |> render_click()
      assert account_fixture().restrict_room_creation_to_administrators

      view |> form("#account-name-form", account: %{name: "Basecamp"}) |> render_submit()
      assert account_fixture().name == "Basecamp"

      view |> element("#remove-user-#{other.id}") |> render_click()
      assert reload(other).status == :deactivated
      refute has_element?(view, "#account-user-#{other.id}")
    end

    test "admins see banned users", %{conn: conn} do
      admin = admin_fixture()
      banned = user_fixture()
      {:ok, _} = Accounts.ban_user(banned, actor: admin)

      {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/account")
      assert has_element?(view, "#account-user-#{banned.id}.banned")

      {:ok, view, _html} = build_conn() |> log_in_user(user_fixture()) |> live(~p"/account")
      refute has_element?(view, "#account-user-#{banned.id}")
    end
  end

  describe "BotsLive" do
    test "non-admins are redirected", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/account/bots")
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/account/bots/new")
    end

    test "lists bots with curl snippets per room", %{conn: conn} do
      admin = admin_fixture()
      room = open_room_fixture(admin, "Deploys")
      bot = bot_fixture(name: "Deploy Bot")
      key = Campfire.Accounts.User.bot_key(bot)

      {:ok, _view, html} = conn |> log_in_user(admin) |> live(~p"/account/bots")
      assert html =~ "Deploy Bot"
      url = CampfireWeb.Endpoint.url() <> "/rooms/#{room.id}/#{key}/messages"
      assert html =~ "curl -d &#39;Hello!&#39; #{url}"
      assert html =~ "attachment=@/path/to/file"
    end

    test "creates a bot", %{conn: conn} do
      admin = admin_fixture()
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/account/bots/new")

      {:ok, _view, html} =
        view
        |> form("#bot-form", bot: %{name: "Helper", webhook_url: "https://example.com/hook"})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "Helper"
      assert [bot] = Accounts.list_bots!(actor: admin)
      assert bot.webhook.url == "https://example.com/hook"
    end

    test "edits the webhook, resets the key and deletes", %{conn: conn} do
      admin = admin_fixture()
      bot = bot_fixture(name: "Helper", webhook_url: "https://example.com/old")
      conn = log_in_user(conn, admin)

      {:ok, view, html} = live(conn, ~p"/account/bots/#{bot.id}/edit")
      assert html =~ "https://example.com/old"

      view
      |> form("#bot-form", bot: %{webhook_url: "https://example.com/new"})
      |> render_submit()

      assert [%{webhook: %{url: "https://example.com/new"}}] = Accounts.list_bots!(actor: admin)

      {:ok, view, _html} = live(conn, ~p"/account/bots/#{bot.id}/edit")
      view |> element("#reset-bot-key") |> render_click()
      assert reload(bot).bot_token != bot.bot_token

      view |> element("#delete-bot") |> render_click()
      assert reload(bot).status == :deactivated
      assert Accounts.list_bots!(actor: admin) == []
    end
  end
end
