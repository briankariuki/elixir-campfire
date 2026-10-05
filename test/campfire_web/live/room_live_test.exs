defmodule CampfireWeb.RoomLiveTest do
  use CampfireWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Campfire.Fixtures

  alias Campfire.Chat

  setup :register_and_log_in_user

  setup %{user: user} do
    other = user_fixture(name: "Other Person")
    room = open_room_fixture(user, "Watercooler")
    %{other: other, room: room}
  end

  defp message_dom_id(message), do: "#messages-#{message.client_message_id}"

  describe "mount" do
    test "renders the last page of messages", %{conn: conn, user: user, room: room} do
      messages = for i <- 1..45, do: message_fixture(room, user, %{body: "Message number #{i}"})

      {:ok, view, html} = live(conn, ~p"/rooms/#{room.id}")

      assert html =~ "Watercooler"
      assert has_element?(view, "#room_#{room.id}_message_stream[phx-viewport-top]")
      refute has_element?(view, message_dom_id(hd(messages)))
      assert has_element?(view, message_dom_id(List.last(messages)), "Message number 45")
      assert has_element?(view, message_dom_id(Enum.at(messages, 5)), "Message number 6")

      html = render_hook(view, "load_older", %{})
      assert html =~ "Message number 1<"
      refute has_element?(view, "#room_#{room.id}_message_stream[phx-viewport-top]")
    end

    test "opens the page around a message and highlights it", %{
      conn: conn,
      user: user,
      room: room
    } do
      messages = for i <- 1..100, do: message_fixture(room, user, %{body: "Message number #{i}"})
      target = Enum.at(messages, 20)

      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}/@#{target.id}")

      assert has_element?(view, message_dom_id(target) <> ".search-highlight")
      refute has_element?(view, message_dom_id(List.last(messages)))

      render_hook(view, "load_newer", %{})
      render_hook(view, "load_newer", %{})
      assert has_element?(view, message_dom_id(List.last(messages)))
      refute has_element?(view, "#room_#{room.id}_message_stream[phx-viewport-bottom]")
    end

    test "redirects non-members home", %{conn: conn, other: other} do
      closed = closed_room_fixture(other, [other])

      assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => _}}}} =
               live(conn, ~p"/rooms/#{closed.id}")

      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/rooms/nope")
    end

    test "remembers the last room and marks it read", %{conn: conn, user: user, room: room} do
      {:ok, _view, _html} = live(conn, ~p"/rooms/#{room.id}")

      assert reload(user).last_room_id == room.id
      assert Campfire.Presence.present_user_ids(room.id) == [user.id]
    end

    test "doesn't touch the user when the last room is unchanged", %{
      conn: conn,
      user: user,
      room: room
    } do
      {:ok, _view, _html} = live(conn, ~p"/rooms/#{room.id}")
      updated_at = reload(user).updated_at

      {:ok, _view, _html} = live(conn, ~p"/rooms/#{room.id}")
      assert reload(user).updated_at == updated_at
    end

    test "a banned IP can't connect", %{conn: conn, other: other, room: room} do
      Campfire.Accounts.Ban
      |> Ash.Changeset.for_create(:create, %{user_id: other.id, ip_address: "127.0.0.1"})
      |> Ash.create!(authorize?: false)

      assert {:error, {:redirect, %{to: "/session/new"}}} = live(conn, ~p"/rooms/#{room.id}")
    end
  end

  describe "messages" do
    test "a posted message appears for another member in realtime", %{
      conn: conn,
      other: other,
      room: room
    } do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")
      {:ok, other_view, _html} = live(log_in_user(build_conn(), other), ~p"/rooms/#{room.id}")

      view |> form("#composer", %{body: "Hello @Other Person"}) |> render_submit()
      assert_push_event(view, "composer:reset", %{})

      assert render(view) =~ "Hello"
      html = render(other_view)
      assert html =~ "message--mentioned"
      assert html =~ ~s(<span class="mention">)
    end

    test "/play renders a sound and plays it", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      view |> form("#composer", %{body: "/play trombone"}) |> render_submit()

      assert render(view) =~ "plays a sad trombone"
      assert_push_event(view, "play_sound", %{url: "/sounds/trombone.mp3"})
    end

    test "edits and deletes your own message", %{conn: conn, user: user, room: room} do
      message = message_fixture(room, user, %{body: "Typo here"})
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      view |> element(message_dom_id(message) <> " .message__edit-btn") |> render_click()
      assert has_element?(view, "#edit-form-#{message.client_message_id}")

      view
      |> form("#edit-form-#{message.client_message_id}", %{body: "Fixed it"})
      |> render_submit()

      assert has_element?(view, message_dom_id(message), "Fixed it")
      refute has_element?(view, "#edit-form-#{message.client_message_id}")

      view |> element(message_dom_id(message) <> " .message__edit-btn") |> render_click()
      view |> element(message_dom_id(message) <> " .btn--negative") |> render_click()
      refute has_element?(view, message_dom_id(message))
      assert {:error, _} = Chat.get_message(message.id, actor: user)
    end

    test "can't edit or delete others' messages", %{
      conn: conn,
      user: user,
      other: other,
      room: room
    } do
      message = message_fixture(room, other, %{body: "Not yours"})
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      refute has_element?(view, message_dom_id(message) <> " .message__edit-btn")

      render_click(view, "edit", %{"id" => message.id})
      refute has_element?(view, "#edit-form-#{message.client_message_id}")

      render_submit(view, "update_message", %{"message_id" => message.id, "body" => "Hacked"})
      render_click(view, "delete_message", %{"id" => message.id})

      assert {:ok, %{body: "Not yours"}} = Chat.get_message(message.id, actor: user)
    end

    test "edit_last edits your last message", %{conn: conn, user: user, room: room} do
      message = message_fixture(room, user, %{body: "Mine"})
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      render_hook(view, "edit_last", %{})
      assert has_element?(view, "#edit-form-#{message.client_message_id}")
    end

    test "reply prefills the composer with a quote", %{conn: conn, other: other, room: room} do
      message = message_fixture(room, other, %{body: "line one\nline two"})
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      view |> element(message_dom_id(message) <> " [aria-label=Reply]") |> render_click()
      assert_push_event(view, "composer:insert", %{text: "> line one\n> line two\n"})
    end

    test "shows messages edited and deleted elsewhere", %{
      conn: conn,
      other: other,
      room: room
    } do
      message = message_fixture(room, other, %{body: "Original"})
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      Chat.update_message!(message, %{body: "Changed"}, actor: other)
      assert has_element?(view, message_dom_id(message), "Changed")

      Chat.destroy_message!(message, actor: other)
      refute has_element?(view, message_dom_id(message))
    end

    test "an open edit form survives boosts and edits elsewhere", %{
      conn: conn,
      user: user,
      other: other,
      room: room
    } do
      message = message_fixture(room, user, %{body: "Mine"})
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      view |> element(message_dom_id(message) <> " .message__edit-btn") |> render_click()
      boost = Chat.create_boost!(message, "👍", actor: other)
      assert has_element?(view, "#edit-form-#{message.client_message_id}")

      Chat.destroy_boost!(boost, actor: other)
      assert has_element?(view, "#edit-form-#{message.client_message_id}")
    end
  end

  describe "boosts" do
    test "adds and removes a boost", %{conn: conn, user: user, other: other, room: room} do
      message = message_fixture(room, other, %{body: "Boost me"})
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      view
      |> element(message_dom_id(message) <> " .quick-boosts button[phx-value-content=🎉]")
      |> render_click()

      assert [boost] = Chat.get_message!(message.id, actor: user, load: [:boosts]).boosts
      assert has_element?(view, "#boost-#{boost.id}", "🎉")

      view |> element("#boost-#{boost.id} .boost__delete") |> render_click()
      refute has_element?(view, "#boost-#{boost.id}")
    end

    test "adds a custom boost", %{conn: conn, other: other, room: room} do
      message = message_fixture(room, other, %{body: "Boost me"})
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      view |> element(message_dom_id(message) <> " .message__boost-btn") |> render_click()

      view
      |> form("#boost-form-#{message.client_message_id}", %{content: "nice!"})
      |> render_submit()

      assert has_element?(view, message_dom_id(message) <> " .boost", "nice!")
      refute has_element?(view, "#boost-form-#{message.client_message_id}")
    end

    test "an open custom boost form survives updates elsewhere", %{
      conn: conn,
      user: user,
      other: other,
      room: room
    } do
      message = message_fixture(room, other, %{body: "Boost me"})
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      view |> element(message_dom_id(message) <> " .message__boost-btn") |> render_click()
      Chat.update_message!(message, %{body: "Boost me please"}, actor: other)
      Chat.create_boost!(message, "👍", actor: user)

      assert has_element?(view, message_dom_id(message), "Boost me please")
      assert has_element?(view, "#boost-form-#{message.client_message_id}")
    end

    test "can't delete someone else's boost", %{conn: conn, user: user, other: other, room: room} do
      message = message_fixture(room, user)
      boost = Chat.create_boost!(message, "👍", actor: other)
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      assert has_element?(view, "#boost-#{boost.id}")
      refute has_element?(view, "#boost-#{boost.id} .boost__delete")

      render_click(view, "delete_boost", %{"id" => boost.id})
      assert {:ok, _} = Chat.get_boost(boost.id, actor: user)
    end
  end

  describe "attachments" do
    test "uploads files as attachment messages", %{conn: conn, user: user, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      input =
        file_input(view, "#composer", :attachments, [
          %{name: "photo.png", content: "fake png", type: "Image/PNG"},
          %{name: "notes.txt", content: "some notes", type: "text/plain"}
        ])

      render_upload(input, "photo.png")
      render_upload(input, "notes.txt")
      view |> form("#composer", %{body: "Two files"}) |> render_submit()

      messages = Chat.page_messages!(room.id, %{}, actor: user)
      assert [photo, notes, text] = messages
      assert photo.attachment_filename == "photo.png"
      assert photo.attachment_content_type == "image/png"
      assert notes.attachment_filename == "notes.txt"
      assert text.body == "Two files"

      assert has_element?(view, ~s(img.message__attachment[src="/attachments/#{photo.id}"]))
      assert has_element?(view, message_dom_id(notes), "notes.txt")
      assert has_element?(view, ~s(a[href="/attachments/#{notes.id}?download=1"]))
    end

    test "renders SVG attachments as downloads, not images", %{conn: conn, user: user, room: room} do
      message =
        message_fixture(room, user, %{
          body: "",
          attachment_key: "x.svg",
          attachment_filename: "logo.svg",
          attachment_content_type: "image/svg+xml"
        })

      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      refute has_element?(view, ~s(img[src="/attachments/#{message.id}"]))
      assert has_element?(view, ~s(a[href="/attachments/#{message.id}?download=1"]))
    end
  end

  describe "typing" do
    test "shows who is typing", %{conn: conn, other: other, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")
      {:ok, other_view, _html} = live(log_in_user(build_conn(), other), ~p"/rooms/#{room.id}")

      render_hook(other_view, "typing", %{})
      assert has_element?(view, ".typing-indicator--active", "Other Person")
      refute has_element?(other_view, ".typing-indicator--active")

      other_view |> form("#composer", %{body: "Done"}) |> render_submit()
      refute has_element?(view, ".typing-indicator--active")
    end
  end

  describe "involvement" do
    test "the bell cycles through involvements", %{conn: conn, user: user, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      assert has_element?(view, "#involvement.mentions")
      view |> element("#involvement") |> render_click()
      assert has_element?(view, "#involvement.everything")
      assert Chat.get_membership!(room.id, actor: user).involvement == :everything
    end
  end

  describe "sidebar" do
    test "marks other rooms unread on new messages and clears them on visit", %{
      conn: conn,
      user: user,
      other: other,
      room: room
    } do
      busy = open_room_fixture(other, "Busy room")
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      assert has_element?(view, "#room_#{busy.id}_list")
      refute has_element?(view, "#room_#{busy.id}_list.unread")

      message_fixture(busy, other, %{body: "News"})
      assert has_element?(view, "#room_#{busy.id}_list.unread")

      message_fixture(room, other, %{body: "Here"})
      refute has_element?(view, "#room_#{room.id}_list.unread")

      {:ok, busy_view, _html} = live(conn, ~p"/rooms/#{busy.id}")
      refute has_element?(busy_view, "#room_#{busy.id}_list.unread")
      assert Chat.get_membership!(busy.id, actor: user).unread_at == nil
      refute has_element?(view, "#room_#{busy.id}_list.unread")
    end

    test "lists Pings and starts one from a placeholder", %{
      conn: conn,
      user: user,
      other: other,
      room: room
    } do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      view |> element("button.direct[phx-value-user-id='#{other.id}']") |> render_click()

      direct = Chat.find_or_create_direct_room!([other.id], actor: user)
      assert_redirect(view, ~p"/rooms/#{direct.id}")
    end

    test "leaves when removed from the current room", %{conn: conn, user: user, other: other} do
      closed = closed_room_fixture(other, [user, other], "Secret")
      {:ok, view, _html} = live(conn, ~p"/rooms/#{closed.id}")

      Chat.update_closed_room!(closed, %{user_ids: [other.id]}, actor: other)
      assert_redirect(view, ~p"/")
    end
  end
end
