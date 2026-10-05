defmodule CampfireWeb.Dev.StyleguideLiveTest do
  use CampfireWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  # The /dev/styleguide route only exists in dev, so mount the LiveView in isolation.
  test "renders messages, composer and sidebar with the original markup", %{conn: conn} do
    {:ok, view, html} = live_isolated(conn, CampfireWeb.Dev.StyleguideLive)

    assert html =~ ~s(id="messages")
    assert html =~ "message--me"
    assert html =~ "message--emoji"
    assert html =~ "message--mentioned"
    assert html =~ ~s(phx-hook="Composer")
    assert html =~ "direct unread"

    html = view |> form("#composer", message: %{body: "Hello from the test"}) |> render_submit()
    assert html =~ "Hello from the test"
    assert_push_event(view, "composer:reset", %{})
  end

  test "/play pushes a sound", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, CampfireWeb.Dev.StyleguideLive)

    view |> form("#composer", message: %{body: "/play trombone"}) |> render_submit()
    assert_push_event(view, "play_sound", %{url: "/sounds/trombone.mp3"})
  end
end
