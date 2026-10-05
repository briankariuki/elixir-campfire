defmodule CampfireWeb.SearchLiveTest do
  use CampfireWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Campfire.Fixtures

  alias Campfire.Chat

  setup :register_and_log_in_user

  test "searches messages in your rooms and records recent searches", %{conn: conn, user: user} do
    other = user_fixture()
    room = open_room_fixture(user, "Watercooler")
    hidden = closed_room_fixture(other, [other])
    message = message_fixture(room, user, %{body: "Bananas are great"})
    message_fixture(hidden, other, %{body: "Secret bananas"})
    message_fixture(room, user, %{body: "Apples"})

    {:ok, view, _html} = live(conn, ~p"/searches")

    view |> form("#search-form", %{q: "bananas"}) |> render_submit()
    assert_patch(view, ~p"/searches?q=bananas")

    html = render(view)
    assert has_element?(view, "#search-results #messages-#{message.id}")
    assert html =~ "Bananas are great"
    assert html =~ "Watercooler"
    refute html =~ "Secret bananas"
    refute html =~ "Apples"
    refute has_element?(view, "#search-results .message__actions")

    assert [%{query: "bananas"}] = Chat.recent_searches!(actor: user)
    assert has_element?(view, "#sidebar a.room", "“bananas”")
  end

  test "clears recent searches", %{conn: conn, user: user} do
    Chat.record_search!("old", actor: user)
    {:ok, view, _html} = live(conn, ~p"/searches?q=old")

    assert has_element?(view, "#sidebar a.room", "“old”")
    view |> element("#sidebar .searches__btn") |> render_click()

    refute has_element?(view, "#sidebar a.room")
    assert Chat.recent_searches!(actor: user) == []
  end
end
