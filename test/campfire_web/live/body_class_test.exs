defmodule CampfireWeb.BodyClassTest do
  @moduledoc """
  The root layout renders `<body class>` once per HTTP request, so live navigation inside a
  `live_session` would otherwise keep the previous page's class: a chat page's "sidebar" stuck
  on `/profile` bottom-justifies `#main-content` and makes the top of the panel unreachable.
  """
  use CampfireWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Campfire.Fixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    %{room: open_room_fixture(user, "Watercooler")}
  end

  test "chat pages push the sidebar body class", %{conn: conn, room: room} do
    {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")
    assert_push_event(view, "body-class", %{class: "sidebar"})

    {:ok, view, _html} = live(conn, ~p"/searches")
    assert_push_event(view, "body-class", %{class: "sidebar searches"})
  end

  test "panel pages push an empty body class", %{conn: conn, user: user} do
    for path <- [~p"/profile", ~p"/users/#{user.id}", ~p"/account"] do
      {:ok, view, _html} = live(conn, path)
      assert_push_event(view, "body-class", %{class: ""})
    end
  end

  test "the class is pushed again after navigating from a room to a panel page",
       %{conn: conn, room: room} do
    {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")
    assert_push_event(view, "body-class", %{class: "sidebar"})

    {:ok, view, _html} =
      view
      |> element("#sidebar a[href='/profile']")
      |> render_click()
      |> follow_redirect(conn, ~p"/profile")

    assert_push_event(view, "body-class", %{class: ""})
  end
end
