defmodule CampfireWeb.HomeLiveTest do
  use CampfireWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Campfire.Fixtures

  alias Campfire.Accounts
  alias Campfire.Chat

  setup :register_and_log_in_user

  test "shows an empty state without rooms", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "messages-empty.svg"
  end

  test "goes to the oldest room, not the first by name", %{conn: conn, user: user} do
    oldest = open_room_fixture(user, "Zulu")
    _newer = open_room_fixture(user, "alpha")

    assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/")
    assert to == ~p"/rooms/#{oldest.id}"
  end

  test "falls back to the oldest room when the last room is no longer accessible",
       %{conn: conn, user: user} do
    other = user_fixture()
    gone = closed_room_fixture(other, [other, user], "Gone")
    oldest = open_room_fixture(user, "Zulu")
    _newer = open_room_fixture(user, "alpha")
    Accounts.set_last_room!(user, gone.id, actor: user)
    Chat.destroy_room!(gone, actor: other)

    assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/")
    assert to == ~p"/rooms/#{oldest.id}"
  end

  test "goes to the last visited room", %{conn: conn, user: user} do
    _a = open_room_fixture(user, "Alpha")
    b = open_room_fixture(user, "Beta")
    Accounts.set_last_room!(user, b.id, actor: user)

    assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/")
    assert to == ~p"/rooms/#{b.id}"
  end

  test "redirects guests to the login page" do
    assert {:error, {:redirect, %{to: "/session/new"}}} = live(build_conn(), ~p"/")
  end
end
