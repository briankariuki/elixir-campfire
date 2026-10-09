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
      assert has_element?(view, "#room_#{room.id}_message_pager[data-load-older]")
      refute has_element?(view, message_dom_id(hd(messages)))
      assert has_element?(view, message_dom_id(List.last(messages)), "Message number 45")
      assert has_element?(view, message_dom_id(Enum.at(messages, 5)), "Message number 6")

      html = render_hook(view, "load_older", %{})
      assert html =~ "Message number 1<"
      refute has_element?(view, "#room_#{room.id}_message_pager[data-load-older]")
    end

    # LiveView's phx-viewport-* hook on the stream sends two load_older events per scroll and locks
    # the stream while they're in flight; overlapping replies then merge in the wrong order in the
    # browser (not reproducible in LiveViewTest). Paging is done by the MessagePager hook, on an
    # element beside the stream, one request at a time.
    test "pages from a pager beside the stream, not from the stream", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      assert has_element?(view, "#room_#{room.id}_messages > #room_#{room.id}_message_pager")
      refute has_element?(view, "#room_#{room.id}_message_stream[phx-hook]")
      refute has_element?(view, "#room_#{room.id}_message_stream[phx-viewport-top]")
      refute has_element?(view, "#room_#{room.id}_message_stream[phx-viewport-bottom]")
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
      refute has_element?(view, "#room_#{room.id}_message_pager[data-load-newer]")
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
      |> Ash.Changeset.for_create(:create, %{user_id: other.id, ip_address: "9.9.9.9"})
      |> Ash.create!(authorize?: false)

      # LiveViewTest hands the conn to get_connect_info/2, which reads the test adapter's peer data
      conn = Plug.Test.put_peer_data(conn, %{address: {9, 9, 9, 9}, port: 1234, ssl_cert: nil})

      assert {:error, {:redirect, %{to: "/blocked"}}} = live(conn, ~p"/rooms/#{room.id}")
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
      expected = "> line one\n> line two\n— Other Person /rooms/#{room.id}/@#{message.id}\n\n"
      assert_push_event(view, "composer:insert", %{text: ^expected})
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

    test "only one edit form is open at a time", %{conn: conn, user: user, room: room} do
      first = message_fixture(room, user, %{body: "First"})
      second = message_fixture(room, user, %{body: "Second"})
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      view |> element(message_dom_id(first) <> " .message__edit-btn") |> render_click()
      view |> element(message_dom_id(second) <> " .message__edit-btn") |> render_click()

      assert has_element?(view, "#edit-form-#{second.client_message_id}")
      refute has_element?(view, "#edit-form-#{first.client_message_id}")
      assert has_element?(view, message_dom_id(first), "First")

      render_keydown(view, "cancel_edit", %{"key" => "Escape", "id" => second.id})
      refute has_element?(view, "form[id^=edit-form-]")
    end
  end

  describe "trimming the DOM to 300 messages" do
    @cap 300

    defp create_messages(room, user, count) do
      for i <- 1..count, do: message_fixture(room, user, %{body: "Message number #{i}"})
    end

    defp message_count(view, room) do
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#room_#{room.id}_message_stream > .message")
      |> Enum.count()
    end

    defp load_older_times(view, times),
      do: for(_ <- 1..times, do: render_hook(view, "load_older", %{}))

    # Opens the room and pages back until the DOM is full with the 300 oldest of `messages`
    # (350 messages: the last page, then 7 older pages, the last one trimming the newest 20)
    defp scrolled_back(conn, room, messages) do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")
      load_older_times(view, 7)
      assert length(messages) == 350
      view
    end

    test "scrolling back keeps the oldest 300 and load_newer brings the dropped ones back", %{
      conn: conn,
      user: user,
      room: room
    } do
      messages = create_messages(room, user, 350)
      pager = "#room_#{room.id}_message_pager"
      view = scrolled_back(conn, room, messages)

      assert message_count(view, room) == @cap
      assert has_element?(view, message_dom_id(Enum.at(messages, 30)))
      assert has_element?(view, message_dom_id(Enum.at(messages, 329)))
      refute has_element?(view, message_dom_id(Enum.at(messages, 330)))
      refute has_element?(view, message_dom_id(List.last(messages)))
      assert has_element?(view, "#{pager}[data-load-older]")
      assert has_element?(view, "#{pager}[data-load-newer]")

      # The dropped messages come back from the bottom, trimming the top in turn
      render_hook(view, "load_newer", %{})
      assert message_count(view, room) == @cap
      assert has_element?(view, message_dom_id(List.last(messages)))
      assert has_element?(view, message_dom_id(Enum.at(messages, 330)))
      refute has_element?(view, message_dom_id(Enum.at(messages, 49)))
      assert has_element?(view, message_dom_id(Enum.at(messages, 50)))
      assert has_element?(view, "#{pager}[data-load-older]")
      refute has_element?(view, "#{pager}[data-load-newer]")

      # And the trimmed top is reachable again
      render_hook(view, "load_older", %{})
      assert message_count(view, room) == @cap
      assert has_element?(view, message_dom_id(Enum.at(messages, 10)))
      refute has_element?(view, message_dom_id(List.last(messages)))
      assert has_element?(view, "#{pager}[data-load-newer]")
    end

    test "live messages at the live end trim the oldest and load_older restores them", %{
      conn: conn,
      user: user,
      room: room
    } do
      messages = create_messages(room, user, @cap)
      pager = "#room_#{room.id}_message_pager"
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")
      load_older_times(view, 7)

      assert message_count(view, room) == @cap
      assert has_element?(view, message_dom_id(hd(messages)))
      refute has_element?(view, "#{pager}[data-load-older]")

      newest = message_fixture(room, user, %{body: "Newest of all"})

      assert message_count(view, room) == @cap
      assert has_element?(view, message_dom_id(newest), "Newest of all")
      refute has_element?(view, message_dom_id(hd(messages)))
      assert has_element?(view, message_dom_id(Enum.at(messages, 1)))
      assert has_element?(view, "#{pager}[data-load-older]")
      refute has_element?(view, "#{pager}[data-load-newer]")

      render_hook(view, "load_older", %{})
      assert has_element?(view, message_dom_id(hd(messages)))
      refute has_element?(view, message_dom_id(newest))
      assert message_count(view, room) == @cap
      assert has_element?(view, "#{pager}[data-load-newer]")
      refute has_element?(view, "#{pager}[data-load-older]")
    end

    test "live messages are left out while scrolled back, then load_newer fetches them", %{
      conn: conn,
      user: user,
      room: room
    } do
      messages = create_messages(room, user, 350)
      view = scrolled_back(conn, room, messages)

      newest = message_fixture(room, user, %{body: "Arrived while away"})
      assert message_count(view, room) == @cap
      refute has_element?(view, message_dom_id(newest))

      render_hook(view, "load_newer", %{})
      assert has_element?(view, message_dom_id(newest), "Arrived while away")
      assert message_count(view, room) == @cap
      refute has_element?(view, "#room_#{room.id}_message_pager[data-load-newer]")
    end

    test "re-rendering a message (edit, boost) doesn't change the window", %{
      conn: conn,
      user: user,
      other: other,
      room: room
    } do
      messages = create_messages(room, user, 350)
      view = scrolled_back(conn, room, messages)
      loaded = Enum.at(messages, 100)
      trimmed_top = Enum.at(messages, 5)
      trimmed_bottom = List.last(messages)

      Chat.update_message!(loaded, %{body: "Edited in the window"}, actor: user)
      Chat.update_message!(trimmed_top, %{body: "Edited out of the window"}, actor: user)
      Chat.update_message!(trimmed_bottom, %{body: "Edited out of the window"}, actor: user)
      Chat.create_boost!(loaded, "👍", actor: other)
      Chat.create_boost!(trimmed_bottom, "👍", actor: other)

      assert has_element?(view, message_dom_id(loaded), "Edited in the window")
      assert has_element?(view, message_dom_id(loaded) <> " .boosts")
      refute has_element?(view, message_dom_id(trimmed_top))
      refute has_element?(view, message_dom_id(trimmed_bottom))
      assert message_count(view, room) == @cap

      # The window didn't move: the next page still starts right after its newest message
      render_hook(view, "load_newer", %{})
      assert has_element?(view, message_dom_id(Enum.at(messages, 330)))
      assert has_element?(view, message_dom_id(trimmed_bottom), "Edited out of the window")
      assert message_count(view, room) == @cap
    end

    test "deleting a message frees a slot instead of trimming another one", %{
      conn: conn,
      user: user,
      room: room
    } do
      messages = create_messages(room, user, @cap)
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")
      load_older_times(view, 7)
      assert message_count(view, room) == @cap

      Chat.destroy_message!(Enum.at(messages, 150), actor: user)
      assert message_count(view, room) == @cap - 1

      newest = message_fixture(room, user, %{body: "Fills the slot"})
      assert message_count(view, room) == @cap
      assert has_element?(view, message_dom_id(hd(messages)))
      assert has_element?(view, message_dom_id(newest))

      message_fixture(room, user, %{body: "Now one has to go"})
      assert message_count(view, room) == @cap
      refute has_element?(view, message_dom_id(hd(messages)))
    end

    test "edit_last works from a scrolled-back window", %{conn: conn, user: user, room: room} do
      messages = create_messages(room, user, 350)
      view = scrolled_back(conn, room, messages)

      render_hook(view, "edit_last", %{})

      last = List.last(messages)
      assert has_element?(view, "#edit-form-#{last.client_message_id}")
      assert has_element?(view, message_dom_id(last))
      assert message_count(view, room) <= @cap
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

    test "only one custom boost form is open at a time", %{conn: conn, other: other, room: room} do
      first = message_fixture(room, other, %{body: "First"})
      second = message_fixture(room, other, %{body: "Second"})
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      view |> element(message_dom_id(first) <> " .message__boost-btn") |> render_click()
      view |> element(message_dom_id(second) <> " .message__boost-btn") |> render_click()

      assert has_element?(view, "#boost-form-#{second.client_message_id}")
      refute has_element?(view, "#boost-form-#{first.client_message_id}")

      render_keydown(view, "cancel_boost", %{"key" => "Escape", "id" => second.id})
      refute has_element?(view, "form[id^=boost-form-]")
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
