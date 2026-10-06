defmodule CampfireWeb.RoomLiveLoadTest do
  @moduledoc """
  What a connected room page costs: boosts are re-rendered from the broadcast's message instead of a
  read per viewer, and the page keeps only the members' id, name and avatar.
  """

  use CampfireWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Campfire.Fixtures

  alias Campfire.Broadcast
  alias Campfire.Chat

  setup :register_and_log_in_user

  setup %{user: user} do
    other = user_fixture(name: "Other Person")
    room = open_room_fixture(user, "Watercooler")
    %{other: other, room: room}
  end

  defp message_dom_id(message), do: "#messages-#{message.client_message_id}"

  # Sends `{:query, pid}` to the test for every Repo query, from the process that ran it
  defp trace_queries do
    test = self()
    id = {__MODULE__, make_ref()}

    :telemetry.attach(
      id,
      [:campfire, :repo, :query],
      fn _event, _measurements, _meta, _config -> send(test, {:query, self()}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)
  end

  defp queries_by(pid) do
    receive do
      {:query, ^pid} -> 1 + queries_by(pid)
      {:query, _other} -> queries_by(pid)
    after
      0 -> 0
    end
  end

  describe "boost broadcasts" do
    test "carry the message with its boosts and their boosters, loaded once", ctx do
      %{room: room, user: user, other: other} = ctx
      message = message_fixture(room, user, %{body: "Boost me"})
      Broadcast.subscribe_room(room.id)

      boost = Chat.create_boost!(message, "🎉", actor: other)

      assert_receive {:boost_created, %{message: broadcast}}
      assert broadcast.id == message.id
      assert %{id: creator_id} = broadcast.creator
      assert creator_id == user.id
      assert [%{id: boost_id, content: "🎉", booster: %{id: booster_id}}] = broadcast.boosts
      assert boost_id == boost.id
      assert booster_id == other.id

      Chat.destroy_boost!(boost, actor: other)

      assert_receive {:boost_deleted, %{message: broadcast}}
      assert broadcast.id == message.id
      assert broadcast.boosts == []
    end
  end

  describe "a boost in a room" do
    test "updates every viewer without re-reading the message", ctx do
      %{conn: conn, room: room, user: user, other: other} = ctx
      message = message_fixture(room, other, %{body: "Boost me"})
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      # Control: a read the page does make is seen by the tracer
      trace_queries()
      view |> element(message_dom_id(message) <> " .message__boost-btn") |> render_click()
      assert queries_by(view.pid) > 0

      boost = Chat.create_boost!(message, "🎉", actor: user)
      assert has_element?(view, "#boost-#{boost.id}", "🎉")
      assert queries_by(view.pid) == 0

      Chat.destroy_boost!(boost, actor: user)
      refute has_element?(view, "#boost-#{boost.id}")
      assert queries_by(view.pid) == 0
    end

    test "keeps the viewer's open custom boost form", ctx do
      %{conn: conn, room: room, user: user, other: other} = ctx
      message = message_fixture(room, other, %{body: "Boost me"})
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      view |> element(message_dom_id(message) <> " .message__boost-btn") |> render_click()
      Chat.create_boost!(message, "👍", actor: other)

      assert has_element?(view, message_dom_id(message) <> " .boost", "👍")
      assert has_element?(view, "#boost-form-#{message.client_message_id}")
      refute has_element?(view, "#boost-form-#{message.client_message_id}", "👍")
      assert user.id
    end

    test "ignores a boost on a message outside the window", ctx do
      %{conn: conn, room: room, user: user, other: other} = ctx
      messages = for i <- 1..45, do: message_fixture(room, user, %{body: "Message #{i}"})
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")
      old = hd(messages)
      refute has_element?(view, message_dom_id(old))

      Chat.create_boost!(old, "👍", actor: other)

      refute has_element?(view, message_dom_id(old))
    end
  end

  describe "members held by the page" do
    test "carry only id, name and avatar_key", %{conn: conn, room: room, other: other} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      %{users: users, room: page_room} = :sys.get_state(view.pid).socket.assigns

      assert %{name: "Other Person", id: id} = users[other.id]
      assert id == other.id
      assert map_size(users) == 2

      for user <- Map.values(users) do
        assert is_binary(user.name)
        assert %Ash.NotLoaded{} = user.email_address
        assert %Ash.NotLoaded{} = user.password_hash
        assert %Ash.NotLoaded{} = user.bio
        assert %Ash.NotLoaded{} = user.bot_token
        assert %Ash.NotLoaded{} = user.role
        assert %Ash.NotLoaded{} = user.last_room_id
      end

      assert Enum.sort(Enum.map(page_room.users, & &1.id)) == Enum.sort(Map.keys(users))
    end

    test "still resolve mentions, with avatars, and the @ menu", ctx do
      %{conn: conn, room: room, user: user, other: other} = ctx
      message_fixture(room, user, %{body: "Hello @Other Person"})
      {:ok, view, html} = live(conn, ~p"/rooms/#{room.id}")

      assert html =~ ~s(<span class="mention">)
      assert has_element?(view, ".mention a[href='/users/#{other.id}']")
      assert has_element?(view, ".mention img[src^='/users/#{other.id}/avatar?v=']")

      render_hook(view, "mention_search", %{"query" => "oth"})
      assert_reply view, %{users: [%{id: id, name: "Other Person", avatar: "/users/" <> _}]}
      assert id == other.id
    end
  end
end
