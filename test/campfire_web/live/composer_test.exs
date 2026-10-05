defmodule CampfireWeb.ComposerTest do
  @moduledoc """
  The server side of the composer: what the Composer hook relies on (data attributes, the mention
  menu), the stop-typing event and the `@` mention lookup. The hook itself (drafts, offline
  disabling, keyboard handling) only runs in a browser.
  """
  use CampfireWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Campfire.Fixtures

  setup :register_and_log_in_user

  describe "markup" do
    test "has what the Composer hook relies on", %{conn: conn, user: user} do
      room = open_room_fixture(user, "Watercooler")
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      assert has_element?(
               view,
               ~s(#composer textarea#composer-body[phx-hook="Composer"][data-room-id="#{room.id}"][data-mention-menu="composer-mentions"])
             )

      # The menu is filled by the hook, so LiveView must leave it alone
      assert has_element?(
               view,
               ~s(#composer-mentions[role="listbox"][phx-update="ignore"][hidden])
             )

      assert has_element?(view, "#composer button[type=submit]")
      assert has_element?(view, "#composer input[type=file]")
    end
  end

  describe "stop_typing" do
    setup %{user: user} do
      other = user_fixture(name: "Other Person")
      %{other: other, room: open_room_fixture(user, "Watercooler")}
    end

    test "clears the typing indicator for the others", %{conn: conn, other: other, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")
      {:ok, other_view, _html} = live(log_in_user(build_conn(), other), ~p"/rooms/#{room.id}")

      render_hook(other_view, "typing", %{})
      assert has_element?(view, ".typing-indicator--active", "Other Person")

      render_hook(other_view, "stop_typing", %{})
      refute has_element?(view, ".typing-indicator--active")
    end

    test "is harmless when nobody is typing", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      render_hook(view, "stop_typing", %{})
      refute has_element?(view, ".typing-indicator--active")
    end
  end

  describe "mention_search" do
    setup %{user: user} do
      ann = user_fixture(name: "Ann Smith")
      annette = user_fixture(name: "Annette Jones")
      bob = user_fixture(name: "Bob Ann")
      carl = user_fixture(name: "Carl Weaver")
      outsider = user_fixture(name: "Annabel Outsider")

      room = closed_room_fixture(user, [user, ann, annette, bob, carl], "Staff")
      %{room: room, ann: ann, annette: annette, bob: bob, carl: carl, outsider: outsider}
    end

    defp search(view, query) do
      render_hook(view, "mention_search", %{"query" => query})
      assert_reply view, %{users: users}
      users
    end

    test "matches the start of the name or of any word, case-insensitively", ctx do
      %{conn: conn, room: room, ann: ann, annette: annette, bob: bob} = ctx
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      assert Enum.map(search(view, "ann"), & &1.name) == ["Ann Smith", "Annette Jones", "Bob Ann"]
      assert Enum.map(search(view, "ANNE"), & &1.name) == ["Annette Jones"]
      assert Enum.map(search(view, "smi"), & &1.name) == ["Ann Smith"]
      assert Enum.map(search(view, "ann s"), & &1.name) == ["Ann Smith"]

      assert [%{id: id, name: "Ann Smith", avatar: "/users/" <> _}] = search(view, "ann sm")
      assert id == ann.id
      assert Enum.map(search(view, "an"), & &1.id) == [ann.id, annette.id, bob.id]
    end

    test "only offers members of the room", %{conn: conn, room: room, outsider: outsider} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      names = view |> search("") |> Enum.map(& &1.name)
      assert names == Enum.sort_by(names, &String.downcase/1)
      assert ["Ann Smith", "Annette Jones", "Bob Ann", "Carl Weaver"] -- names == []
      refute outsider.name in names

      assert search(view, "annab") == []
      assert search(view, "zzz") == []
    end

    test "works in an open room", %{conn: conn, user: user} do
      zed = user_fixture(name: "Zed Zebra")
      room = open_room_fixture(user, "Everyone")
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      assert [%{id: id, name: "Zed Zebra"}] = search(view, "zed")
      assert id == zed.id
    end

    test "gives at most 8 members", %{conn: conn, user: user} do
      members =
        for i <- 1..12, do: user_fixture(name: "Member #{String.pad_leading("#{i}", 2, "0")}")

      room = closed_room_fixture(user, [user | members], "Crowd")
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      names = view |> search("mem") |> Enum.map(& &1.name)
      assert length(names) == 8
      assert names == Enum.sort(names)
    end

    test "requires a room you can open", %{conn: conn, outsider: outsider, room: room} do
      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(log_in_user(conn, outsider), ~p"/rooms/#{room.id}")
    end
  end
end
