defmodule CampfireWeb.DirectPickerLiveTest do
  use CampfireWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Campfire.Fixtures

  alias Campfire.Chat

  setup :register_and_log_in_user

  test "picks people and starts a Ping with them", %{conn: conn, user: user} do
    ann = user_fixture(name: "Ann Example")
    bob = user_fixture(name: "Bob Example")
    _carl = user_fixture(name: "Carl Other")

    {:ok, view, _html} = live(conn, ~p"/directs/new")

    html = view |> form("#direct-picker", %{query: "exam"}) |> render_change()
    assert html =~ "Ann Example"
    assert html =~ "Bob Example"
    refute html =~ "Carl Other"

    view |> element(".autocomplete__list button[phx-value-id='#{ann.id}']") |> render_click()
    view |> form("#direct-picker", %{query: "bob"}) |> render_change()
    view |> element(".autocomplete__list button[phx-value-id='#{bob.id}']") |> render_click()

    assert has_element?(view, ".autocomplete__pill", "Ann Example")
    assert has_element?(view, ".autocomplete__pill", "Bob Example")

    view |> form("#direct-picker") |> render_submit()

    room = Chat.find_or_create_direct_room!([ann.id, bob.id], actor: user)
    assert_redirect(view, ~p"/rooms/#{room.id}")
  end

  test "removes a picked person", %{conn: conn} do
    ann = user_fixture(name: "Ann Example")
    {:ok, view, _html} = live(conn, ~p"/directs/new")

    view |> form("#direct-picker", %{query: "ann"}) |> render_change()
    view |> element(".autocomplete__list button[phx-value-id='#{ann.id}']") |> render_click()
    view |> element(".autocomplete__pill button") |> render_click()

    refute has_element?(view, ".autocomplete__pill")
  end
end
