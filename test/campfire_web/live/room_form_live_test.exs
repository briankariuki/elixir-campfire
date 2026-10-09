defmodule CampfireWeb.RoomFormLiveTest do
  use CampfireWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Campfire.Fixtures

  alias Campfire.Chat

  setup :register_and_log_in_user

  setup do
    %{other: user_fixture(name: "Other Person")}
  end

  defp room_members(room, user) do
    Chat.get_room!(room.id, actor: user, load: [:users]).users |> Enum.map(& &1.id) |> Enum.sort()
  end

  describe "new" do
    test "creates an open room", %{conn: conn, user: user, other: other} do
      {:ok, view, html} = live(conn, ~p"/rooms/new/open")
      assert html =~ ~s(value="New room")

      view |> form("#room-form", room: %{name: "Watercooler"}) |> render_submit()

      [room] = Enum.filter(Chat.list_rooms!(actor: user), &(&1.name == "Watercooler"))
      assert room.kind == :open
      assert_redirect(view, ~p"/rooms/#{room.id}")
      assert other.id in room_members(room, user)
    end

    test "the Everyone switch links to the closed form, keeping the name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/rooms/new/open")

      view |> form("#room-form", room: %{name: "Secret plans"}) |> render_change()
      view |> element("#everyone-switch") |> render_click()

      assert_patch(view, ~p"/rooms/new/closed")
      assert has_element?(view, ~s(#room_name[value="Secret plans"]))
    end

    test "shows the name error from the domain and creates nothing", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/rooms/new/open")

      html = view |> form("#room-form", room: %{name: ""}) |> render_change()
      assert html =~ "can&#39;t be blank"
      assert has_element?(view, "#room-form p.input-error")

      view |> form("#room-form", room: %{name: "   "}) |> render_submit()
      assert has_element?(view, "#room-form p.input-error", "can't be blank")
      refute_redirected(view)
      assert Enum.all?(Chat.list_rooms!(actor: user), &(&1.name != nil and &1.name != ""))

      view |> form("#room-form", room: %{name: "Fixed"}) |> render_submit()
      assert Enum.any?(Chat.list_rooms!(actor: user), &(&1.name == "Fixed"))
    end

    test "creates a closed room with the chosen members", %{
      conn: conn,
      user: user,
      other: other
    } do
      third = user_fixture()
      {:ok, view, _html} = live(conn, ~p"/rooms/new/closed")

      assert has_element?(
               view,
               ~s(input[type=hidden][name="room[user_ids][]"][value="#{user.id}"])
             )

      assert has_element?(view, "#user_#{other.id}")

      view
      |> form("#room-form",
        room: %{name: "Secret", user_ids: [to_string(user.id), to_string(other.id)]}
      )
      |> render_submit()

      [room] = Enum.filter(Chat.list_rooms!(actor: user), &(&1.name == "Secret"))
      assert room.kind == :closed
      assert room_members(room, user) == Enum.sort([user.id, other.id])
      refute third.id in room_members(room, user)
    end
  end

  describe "edit" do
    test "renames and converts an open room to closed", %{conn: conn, user: user, other: other} do
      room = open_room_fixture(user, "Open")
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}/edit")

      view |> element("#everyone-switch input") |> render_click()
      assert has_element?(view, "#user_#{other.id}")

      view
      |> form("#room-form", room: %{name: "Closed now", user_ids: [to_string(user.id)]})
      |> render_submit()

      assert_redirect(view, ~p"/rooms/#{room.id}")
      room = reload(room)
      assert room.kind == :closed
      assert room.name == "Closed now"
      assert room_members(room, user) == [user.id]
    end

    test "converts a closed room to open", %{conn: conn, user: user, other: other} do
      room = closed_room_fixture(user, [user], "Closed")
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}/edit")

      view |> element("#everyone-switch input") |> render_click()
      view |> form("#room-form") |> render_submit()

      assert reload(room).kind == :open
      assert other.id in room_members(room, user)
    end

    test "keeps bots in a closed room", %{conn: conn, user: user} do
      bot = bot_fixture(name: "Deploy Bot")
      room = closed_room_fixture(user, [user, bot], "With bot")
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}/edit")

      assert has_element?(view, "#user_#{bot.id}[checked]")
      view |> form("#room-form", room: %{name: "Still with bot"}) |> render_submit()

      assert room_members(room, user) == Enum.sort([user.id, bot.id])
    end

    test "keeps banned members in a closed room", %{conn: conn, user: user, other: other} do
      room = closed_room_fixture(user, [user, other], "With banned")
      Campfire.Accounts.ban_user!(other, authorize?: false)
      bystander_banned = user_fixture(name: "Banned Bystander")
      Campfire.Accounts.ban_user!(bystander_banned, authorize?: false)

      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}/edit")

      assert has_element?(view, "#user_#{other.id}[checked]")
      refute has_element?(view, "#user_#{bystander_banned.id}")

      view |> form("#room-form", room: %{name: "Renamed"}) |> render_submit()

      assert reload(room).name == "Renamed"
      assert room_members(room, user) == Enum.sort([user.id, other.id])
    end

    test "doesn't offer banned people for a new closed room", %{conn: conn, other: other} do
      Campfire.Accounts.ban_user!(other, authorize?: false)
      {:ok, view, _html} = live(conn, ~p"/rooms/new/closed")

      refute has_element?(view, "#user_#{other.id}")
    end

    test "lists bots when converting an open room to closed", %{conn: conn, user: user} do
      bot = bot_fixture(name: "Deploy Bot")
      room = open_room_fixture(user, "Open")
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}/edit")

      view |> element("#everyone-switch input") |> render_click()
      assert has_element?(view, "#user_#{bot.id}[checked]")
    end

    test "is read-only for members who can't administer the room", %{
      conn: conn,
      user: user,
      other: other
    } do
      room = open_room_fixture(other, "Theirs")
      {:ok, view, html} = live(conn, ~p"/rooms/#{room.id}/edit")

      assert html =~ "Theirs"
      refute has_element?(view, "#room_name")
      refute has_element?(view, "#room-form button[type=submit]")
      refute has_element?(view, "button[phx-click=delete]")

      # A crafted submit is refused by the room's policy
      assert render_submit(view, "save", %{"room" => %{"name" => "Mine now"}}) =~
               "You can&#39;t do that."

      assert reload(room).name == "Theirs"
      assert room_members(room, user) != []
    end

    test "deletes a room", %{conn: conn, user: user} do
      room = open_room_fixture(user, "Doomed")
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}/edit")

      view |> element("button[phx-click=delete]") |> render_click()

      assert_redirect(view, ~p"/")
      assert {:error, _} = Chat.get_room(room.id, actor: user)
    end

    test "shows the participants of a Ping and deletes it", %{
      conn: conn,
      user: user,
      other: other
    } do
      room = direct_room_fixture(user, [other])
      {:ok, view, html} = live(conn, ~p"/rooms/#{room.id}/edit")

      assert html =~ "Other Person"

      # Crafted form events are ignored
      render_change(view, "validate", %{"room" => %{"name" => "Renamed"}})
      render_submit(view, "save", %{"room" => %{"name" => "Renamed"}})
      render_click(view, "toggle_kind", %{})
      assert render(view) =~ "Other Person"

      view |> element("button[aria-label='Delete Ping']") |> render_click()

      assert_redirect(view, ~p"/")
      assert {:error, _} = Chat.get_room(room.id, actor: user)
    end

    test "redirects non-members", %{conn: conn, other: other} do
      room = closed_room_fixture(other, [other])
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/rooms/#{room.id}/edit")
    end
  end

  describe "member filter" do
    test "is shown only when there are more than 20 people", %{conn: conn, user: user} do
      # The signed-in user and "Other Person" make 2; 18 more makes exactly 20
      for _ <- 1..18, do: user_fixture()
      {:ok, view, _html} = live(conn, ~p"/rooms/new/closed")
      refute has_element?(view, "#member-filter")
      assert has_element?(view, "#room-members[phx-hook=Filter]")

      user_fixture(name: "Twenty First")
      {:ok, view, _html} = live(conn, ~p"/rooms/new/closed")
      assert has_element?(view, "input#member-filter[type=search][placeholder='Filter…']")

      assert Enum.count(Campfire.Accounts.list_users!(actor: user)) == 21
    end

    test "rows carry the lowercased name to match and every checkbox stays in the form", %{
      conn: conn,
      user: user,
      other: other
    } do
      for i <- 1..20, do: user_fixture(name: "Member #{i}")
      {:ok, view, _html} = live(conn, ~p"/rooms/new/closed")

      assert has_element?(view, "[data-filter-list] li[data-value='other person']")

      # Everyone else has a switch (the creator is a locked hidden field), none removed by the filter
      users = Campfire.Accounts.list_users!(actor: user)
      assert length(users) == 22

      for member <- users, member.id != user.id do
        assert has_element?(view, "#user_#{member.id}[name='room[user_ids][]']")
      end

      assert has_element?(
               view,
               ~s(input[type=hidden][name="room[user_ids][]"][value="#{user.id}"])
             )

      # Saving still submits the checked members, whichever rows a filter would hide
      third = Campfire.Accounts.list_users!(actor: user) |> Enum.find(&(&1.name == "Member 7"))

      view
      |> form("#room-form",
        room: %{
          name: "Filtered",
          user_ids: Enum.map([user, other, third], &to_string(&1.id))
        }
      )
      |> render_submit()

      [room] = Enum.filter(Chat.list_rooms!(actor: user), &(&1.name == "Filtered"))
      assert room_members(room, user) == Enum.sort([user.id, other.id, third.id])
    end

    test "also filters the member list when editing a closed room", %{
      conn: conn,
      user: user,
      other: other
    } do
      others = for i <- 1..20, do: user_fixture(name: "Member #{i}")
      room = closed_room_fixture(user, [user, other | Enum.take(others, 3)], "Secret")

      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}/edit")
      assert has_element?(view, "#member-filter")

      for member <- others ++ [other] do
        assert has_element?(view, "#user_#{member.id}")
      end
    end
  end
end
