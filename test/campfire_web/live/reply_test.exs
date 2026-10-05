defmodule CampfireWeb.ReplyTest do
  use CampfireWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Campfire.Fixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    other = user_fixture(name: "Other Person")
    room = open_room_fixture(user, "Watercooler")
    %{other: other, room: room}
  end

  defp message_dom_id(message), do: "#messages-#{message.client_message_id}"

  defp click_reply(view, message) do
    view |> element(message_dom_id(message) <> " [aria-label=Reply]") |> render_click()
  end

  describe "Reply" do
    test "prefills the quote and the attribution of a text message", %{
      conn: conn,
      other: other,
      room: room
    } do
      message = message_fixture(room, other, %{body: "line one\nline two"})
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      click_reply(view, message)

      expected = "> line one\n> line two\n— Other Person /rooms/#{room.id}/@#{message.id}\n\n"
      assert_push_event(view, "composer:insert", %{text: ^expected})
    end

    test "leaves out nested quotes, an earlier attribution and the @ of mentions", %{
      conn: conn,
      user: user,
      other: other,
      room: room
    } do
      message =
        message_fixture(room, other, %{
          body: "> older\n— Someone /rooms/#{room.id}/@1\n\nthanks @#{user.name}"
        })

      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      click_reply(view, message)

      expected = "> thanks #{user.name}\n— Other Person /rooms/#{room.id}/@#{message.id}\n\n"
      assert_push_event(view, "composer:insert", %{text: ^expected})
    end

    test "quotes the caption of a /play message, not the command", %{
      conn: conn,
      other: other,
      room: room
    } do
      text_sound = message_fixture(room, other, %{body: "/play tada"})
      image_sound = message_fixture(room, other, %{body: "/play nyan"})
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      click_reply(view, text_sound)

      expected = "> plays a fanfare 🎏\n— Other Person /rooms/#{room.id}/@#{text_sound.id}\n\n"
      assert_push_event(view, "composer:insert", %{text: ^expected})

      click_reply(view, image_sound)

      expected = "> 🔊 nyan\n— Other Person /rooms/#{room.id}/@#{image_sound.id}\n\n"
      assert_push_event(view, "composer:insert", %{text: ^expected})
    end

    test "the sent reply shows a blockquote and a cite linking to the quoted message", %{
      conn: conn,
      other: other,
      room: room
    } do
      original = message_fixture(room, other, %{body: "Shipping today"})
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      click_reply(view, original)
      assert_push_event(view, "composer:insert", %{text: prefill})

      view
      |> form("#composer", %{body: prefill <> "Great!"})
      |> render_submit()

      assert has_element?(view, ".message blockquote", "Shipping today")

      assert has_element?(
               view,
               ~s(.message cite a[href="/rooms/#{room.id}/@#{original.id}"][data-phx-link=redirect]),
               "#"
             )

      assert has_element?(view, ".message cite", "Other Person")
    end
  end

  describe "mention links" do
    test "link to the profile and live-navigate", %{
      conn: conn,
      user: user,
      other: other,
      room: room
    } do
      message = message_fixture(room, other, %{body: "hello @#{user.name}"})
      assert message.mentioned_user_ids == [user.id]

      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      selector =
        message_dom_id(message) <>
          ~s( .mention a.btn.avatar[href="/users/#{user.id}"][data-phx-link=redirect][data-phx-link-state=push])

      assert has_element?(view, selector)

      view |> element(selector) |> render_click()
      assert_redirect(view, ~p"/users/#{user.id}")
    end
  end
end
