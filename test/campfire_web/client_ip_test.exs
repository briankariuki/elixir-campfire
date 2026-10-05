defmodule CampfireWeb.ClientIPTest do
  # Not async: toggles the global :trust_proxy_headers setting.
  use CampfireWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Campfire.Fixtures

  alias Campfire.Accounts

  @proxy_ip {172, 18, 0, 3}

  setup do
    on_exit(fn -> Application.delete_env(:campfire, :trust_proxy_headers) end)
  end

  defp trust_proxy_headers(trust?),
    do: Application.put_env(:campfire, :trust_proxy_headers, trust?)

  # A request arriving from the proxy, forwarded for `client`
  defp via_proxy(conn, client) do
    %{conn | remote_ip: @proxy_ip}
    |> Plug.Test.put_peer_data(%{address: @proxy_ip, port: 1234, ssl_cert: nil})
    |> put_req_header("x-forwarded-for", client)
  end

  describe "the plug" do
    test "uses the first X-Forwarded-For entry when proxy headers are trusted", %{conn: conn} do
      trust_proxy_headers(true)
      conn = conn |> via_proxy("9.9.9.9, 10.0.0.1") |> CampfireWeb.ClientIP.call([])
      assert conn.remote_ip == {9, 9, 9, 9}
    end

    test "ignores X-Forwarded-For by default", %{conn: conn} do
      conn = conn |> via_proxy("9.9.9.9") |> CampfireWeb.ClientIP.call([])
      assert conn.remote_ip == @proxy_ip
    end

    test "keeps the peer address when the header isn't an IP", %{conn: conn} do
      trust_proxy_headers(true)
      conn = conn |> via_proxy("unknown") |> CampfireWeb.ClientIP.call([])
      assert conn.remote_ip == @proxy_ip
    end
  end

  test "sessions record the forwarded client IP", %{conn: conn} do
    trust_proxy_headers(true)
    user = user_fixture(password: "secret123")

    conn
    |> via_proxy("9.9.9.9")
    |> post(~p"/session", %{"email_address" => user.email_address, "password" => "secret123"})

    assert [%{ip_address: "9.9.9.9"}] =
             Accounts.Session
             |> Ash.read!(authorize?: false)
             |> Enum.filter(&(&1.user_id == user.id))
  end

  describe "LiveView sockets" do
    setup :register_and_log_in_user

    setup %{user: user} do
      Accounts.Ban
      |> Ash.Changeset.for_create(:create, %{user_id: user_fixture().id, ip_address: "9.9.9.9"})
      |> Ash.create!(authorize?: false)

      %{room: open_room_fixture(user, "Watercooler")}
    end

    test "a banned forwarded IP is refused when proxy headers are trusted",
         %{conn: conn, room: room} do
      trust_proxy_headers(true)

      assert {:error, {:redirect, %{to: "/blocked"}}} =
               conn |> via_proxy("9.9.9.9") |> live(~p"/rooms/#{room.id}")
    end

    test "X-Forwarded-For is ignored by default", %{conn: conn, room: room} do
      assert {:ok, _view, _html} = conn |> via_proxy("9.9.9.9") |> live(~p"/rooms/#{room.id}")
    end
  end
end
