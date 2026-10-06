defmodule CampfireWeb.ComposerToolbarTest do
  @moduledoc """
  The server side of the composer formatting toolbar: the markup the Composer hook relies on, and
  that a message written with the toolbar's syntax is stored as typed and shown formatted. The
  buttons themselves (selection wrapping, Enter vs Cmd+Enter) only run in a browser.
  """
  use CampfireWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Campfire.Fixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    %{room: open_room_fixture(user, "Watercooler")}
  end

  describe "markup" do
    test "the textarea points at the toolbar and its toggle", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      assert has_element?(
               view,
               ~s(#composer-body[phx-hook="Composer"][data-toolbar="composer-toolbar"][data-toolbar-toggle="composer-toolbar-toggle"])
             )
    end

    test "the toolbar starts closed and is left alone by LiveView patches", %{
      conn: conn,
      room: room
    } do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      assert has_element?(
               view,
               ~s(#composer #composer-toolbar.composer__toolbar[role="toolbar"][phx-update="ignore"][hidden]),
               ""
             )
    end

    test "the toggle is the original's rich text button", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      assert has_element?(
               view,
               ~s(#composer button#composer-toolbar-toggle.composer__rich-text-btn[type=button][aria-controls="composer-toolbar"][aria-expanded="false"][phx-update="ignore"]),
               "Rich text"
             )

      assert has_element?(view, ~s(#composer-toolbar-toggle img[src*="text-options"]))
    end

    test "has a button per format", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      for format <-
            ~w(bold italic strike highlight code codeblock heading quote bullet number) do
        assert has_element?(
                 view,
                 ~s(#composer-toolbar button.composer__format-btn[type=button][data-format="#{format}"][aria-label])
               )
      end
    end

    test "the toolbar buttons never submit the form", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      refute has_element?(view, "#composer-toolbar button:not([type=button])")
      assert has_element?(view, "#composer button[type=submit]", "Send Message")
    end
  end

  describe "sending formatted text" do
    test "is stored as typed and rendered as formatted HTML", %{
      conn: conn,
      user: user,
      room: room
    } do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      body =
        "# Plan\n**bold** _it_ ~~gone~~ ==key== `x < y`\n- one\n- two\n1. a\n2. b\n```\nputs \"<b>\" **raw**\n```"

      view |> form("#composer", %{body: body}) |> render_submit()

      assert has_element?(view, ".message .lexxy-content h1", "Plan")
      assert has_element?(view, ".lexxy-content strong", "bold")
      assert has_element?(view, ".lexxy-content em", "it")
      assert has_element?(view, ".lexxy-content s", "gone")
      assert has_element?(view, ".lexxy-content mark", "key")
      assert has_element?(view, ".lexxy-content code", "x < y")
      assert has_element?(view, ".lexxy-content ul li", "two")
      assert has_element?(view, ".lexxy-content ol li", "b")
      assert has_element?(view, ".lexxy-content pre code", ~s(puts "<b>" **raw**))
      refute has_element?(view, ".lexxy-content pre strong")
      refute has_element?(view, ".lexxy-content pre b")

      assert [%{body: ^body}] = Campfire.Chat.page_messages!(room.id, actor: user)
    end

    test "no raw HTML gets through", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      view
      |> form("#composer", %{body: "**<img src=x onerror=alert(1)>** <script>x</script>"})
      |> render_submit()

      assert has_element?(view, ".lexxy-content strong")
      refute has_element?(view, ".lexxy-content img")
      refute has_element?(view, ".lexxy-content script")
    end

    test "mentions still resolve around formatting, but not in code", %{conn: conn, room: room} do
      other = user_fixture(name: "Other Person")
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      view
      |> form("#composer", %{body: "**hi @Other Person** and `@Other Person`"})
      |> render_submit()

      assert has_element?(view, ~s(.lexxy-content strong .mention a[href="/users/#{other.id}"]))
      refute has_element?(view, ".lexxy-content code .mention")
      assert has_element?(view, ".lexxy-content code", "@Other Person")
    end
  end
end
