defmodule CampfireWeb.AuthControllersTest do
  use CampfireWeb.ConnCase, async: true

  import Campfire.Fixtures

  alias Campfire.{Accounts, Chat}

  defp image_upload do
    %Plug.Upload{
      path: Application.app_dir(:campfire, "priv/static/images/campfire-icon.png"),
      filename: "me.png",
      content_type: "image/png"
    }
  end

  describe "first run" do
    test "shows the setup form until the account exists", %{conn: conn} do
      html = conn |> get(~p"/first_run") |> html_response(200)
      assert html =~ "Set up Campfire"
      assert html =~ ~s(class="signup")
      assert html =~ "nametag"

      account_fixture()
      assert build_conn() |> get(~p"/first_run") |> redirected_to() == ~p"/"
    end

    test "sign in redirects to first run when not set up", %{conn: conn} do
      assert conn |> get(~p"/session/new") |> redirected_to() == ~p"/first_run"
    end

    test "creates the account and admin, and signs in", %{conn: conn} do
      conn =
        post(conn, ~p"/first_run", %{
          "user" => %{
            "name" => "Jason Fried",
            "email_address" => "jason@example.com",
            "password" => "secret123",
            "avatar" => image_upload()
          }
        })

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :session_token)
      assert Accounts.set_up?()

      {:ok, user} = Accounts.sign_in("jason@example.com", "secret123")
      assert user.role == :administrator
      assert user.avatar_key && Campfire.Uploads.exists?(user.avatar_key)
      assert [%{room: %{name: "All Talk"}}] = Chat.list_memberships!(actor: user)
    end

    test "re-renders with an error for invalid input", %{conn: conn} do
      conn =
        post(conn, ~p"/first_run", %{
          "user" => %{"name" => "", "email_address" => "x@example.com", "password" => "pw"}
        })

      assert html_response(conn, 422) =~ "Set up Campfire"
      refute Accounts.set_up?()
    end
  end

  describe "sign in" do
    setup do
      account_fixture()
      %{user: user_fixture(email_address: "david@example.com", password: "secret123")}
    end

    test "renders the login form, prefilled", %{conn: conn} do
      html = conn |> get(~p"/session/new?email_address=david@example.com") |> html_response(200)
      assert html =~ ~s(value="david@example.com")
      assert html =~ "Campfire"
      refute html =~ "shake"
    end

    test "logs in and redirects to /", %{conn: conn} do
      conn =
        post(conn, ~p"/session", %{
          "email_address" => "david@example.com",
          "password" => "secret123"
        })

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :session_token)
      assert get_session(conn, :live_socket_id) =~ "users_socket:"
    end

    test "redirects to the stored return_to", %{conn: conn} do
      conn = get(conn, ~p"/profile")
      assert redirected_to(conn) == ~p"/session/new"

      conn =
        conn
        |> recycle()
        |> post(~p"/session", %{"email_address" => "david@example.com", "password" => "secret123"})

      assert redirected_to(conn) == ~p"/profile"
    end

    test "a wrong password gives 401 and shakes", %{conn: conn} do
      conn =
        post(conn, ~p"/session", %{"email_address" => "david@example.com", "password" => "x"})

      html = html_response(conn, 401)
      assert html =~ "shake"
      assert html =~ "Too many requests or unauthorized."
      refute get_session(conn, :session_token)
    end

    test "signed-in users are sent away from the login page", %{conn: conn, user: user} do
      assert conn |> log_in_user(user) |> get(~p"/session/new") |> redirected_to() == ~p"/"
    end

    test "logout destroys the session", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user)
      token = get_session(conn, :session_token)

      conn = delete(conn, ~p"/session")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :session_token)
      assert Accounts.get_session_by_token(token) == nil
    end

    test "POSTs from a banned IP get 429", %{conn: conn} do
      admin = admin_fixture()
      banned = user_fixture()
      session_fixture(banned, ip_address: "8.8.8.8")
      {:ok, _} = Accounts.ban_user(banned, actor: admin)

      conn = %{conn | remote_ip: {8, 8, 8, 8}}

      assert conn
             |> post(~p"/session", %{"email_address" => "david@example.com", "password" => "x"})
             |> response(429)

      # GETs still work
      assert build_conn()
             |> Map.put(:remote_ip, {8, 8, 8, 8})
             |> get(~p"/session/new")
             |> html_response(200)
    end
  end

  describe "join" do
    setup do
      %{account: account_fixture()}
    end

    test "404 for a bad code", %{conn: conn} do
      assert conn |> get(~p"/join/nope") |> response(404)
      assert build_conn() |> post(~p"/join/nope", %{"user" => %{}}) |> response(404)
    end

    test "shows the sign up form", %{conn: conn, account: account} do
      html = conn |> get(~p"/join/#{account.join_code}") |> html_response(200)
      assert html =~ "nametag"
      assert html =~ account.name
    end

    test "registers a member, joins open rooms and signs in", %{conn: conn, account: account} do
      room = open_room_fixture(admin_fixture())

      conn =
        post(conn, ~p"/join/#{account.join_code}", %{
          "user" => %{
            "name" => "New Person",
            "email_address" => "new@example.com",
            "password" => "secret123"
          }
        })

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :session_token)

      {:ok, user} = Accounts.sign_in("new@example.com", "secret123")
      assert user.role == :member
      assert Enum.any?(Chat.list_memberships!(actor: user), &(&1.room_id == room.id))
    end

    test "a taken email redirects to sign in", %{conn: conn, account: account} do
      user_fixture(email_address: "taken@example.com")

      conn =
        post(conn, ~p"/join/#{account.join_code}", %{
          "user" => %{
            "name" => "Dup",
            "email_address" => "taken@example.com",
            "password" => "secret123"
          }
        })

      assert redirected_to(conn) == ~p"/session/new?email_address=taken%40example.com"
    end
  end

  describe "session transfer" do
    setup do
      account_fixture()
      %{user: user_fixture()}
    end

    test "GET shows a confirm form", %{conn: conn, user: user} do
      token = CampfireWeb.Transfer.token(user)
      html = conn |> get(~p"/session/transfers/#{token}") |> html_response(200)
      assert html =~ ~r/name="_method"[^>]*value="put"/
    end

    test "PUT with a valid token logs in", %{conn: conn, user: user} do
      conn = put(conn, ~p"/session/transfers/#{CampfireWeb.Transfer.token(user)}")
      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :session_token)
    end

    test "PUT with a bad or expired token is a 400", %{conn: conn, user: user} do
      assert conn |> put(~p"/session/transfers/garbage") |> response(400)

      expired =
        Phoenix.Token.sign(CampfireWeb.Endpoint, "transfer", user.id,
          signed_at: System.system_time(:second) - 5 * 60 * 60
        )

      assert build_conn() |> put(~p"/session/transfers/#{expired}") |> response(400)
    end

    test "PUT for a deactivated user is a 400", %{conn: conn, user: user} do
      {:ok, _} = Accounts.deactivate_user(user, actor: admin_fixture())

      assert conn
             |> put(~p"/session/transfers/#{CampfireWeb.Transfer.token(user)}")
             |> response(400)
    end
  end

  describe "avatars and logo" do
    setup :register_and_log_in_user

    test "requires sign in" do
      assert build_conn() |> get(~p"/users/1/avatar") |> redirected_to() == ~p"/session/new"
    end

    test "generates an initials SVG", %{conn: conn} do
      other = user_fixture(name: "Jason Fried")
      conn = get(conn, ~p"/users/#{other.id}/avatar")

      assert response(conn, 200) =~ "JF"
      assert response_content_type(conn, :svg) =~ "image/svg+xml"
      assert get_resp_header(conn, "cache-control") |> hd() =~ "max-age"
      assert response(conn, 200) =~ CampfireWeb.AvatarController.color(other)
    end

    test "serves an uploaded avatar", %{conn: conn} do
      {:ok, key} = Campfire.Uploads.store_binary("PNGDATA", "a.png")
      other = user_fixture(avatar_key: key)
      conn = get(conn, ~p"/users/#{other.id}/avatar")

      assert response(conn, 200) == "PNGDATA"
      assert response_content_type(conn, :png) =~ "image/png"
    end

    test "bots without an avatar get the default bot image", %{conn: conn} do
      bot = bot_fixture()

      assert conn |> get(~p"/users/#{bot.id}/avatar") |> redirected_to() ==
               "/images/default-bot-avatar.svg"
    end

    test "404 for unknown users", %{conn: conn} do
      assert conn |> get(~p"/users/0/avatar") |> response(404)
    end

    test "the logo is public, with a default" do
      conn = get(build_conn(), ~p"/account/logo")
      assert response_content_type(conn, :png) =~ "image/png"
      assert conn.status == 200

      {:ok, key} = Campfire.Uploads.store_binary("LOGO", "logo.png")
      account_fixture(%{logo_key: key})
      assert build_conn() |> get(~p"/account/logo") |> response(200) == "LOGO"
    end
  end
end
