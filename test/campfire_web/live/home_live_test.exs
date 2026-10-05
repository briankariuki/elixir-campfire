defmodule CampfireWeb.HomeLiveTest do
  use CampfireWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Campfire.Fixtures

  alias Campfire.Accounts

  setup :register_and_log_in_user

  test "shows an empty state without rooms", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "messages-empty.svg"
  end

  test "goes to the first room by name", %{conn: conn, user: user} do
    _b = open_room_fixture(user, "Beta")
    a = open_room_fixture(user, "alpha")

    assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/")
    assert to == ~p"/rooms/#{a.id}"
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
