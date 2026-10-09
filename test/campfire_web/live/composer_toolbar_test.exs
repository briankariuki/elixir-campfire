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
            ~w(bold italic strike highlight code codeblock heading quote bullet number link) do
        assert has_element?(
                 view,
                 ~s(#composer-toolbar button.composer__format-btn[type=button][data-format="#{format}"][aria-label][title])
               )
      end
    end

    test "the buttons show a plain SVG icon, which the dark mode inverts, and no text glyph", %{
      conn: conn,
      room: room
    } do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      for {format, icon} <- [
            {"bold", "format-bold.svg"},
            {"italic", "format-italic.svg"},
            {"strike", "format-strike.svg"},
            {"highlight", "format-highlight.svg"},
            {"code", "format-code.svg"},
            {"codeblock", "format-code-block.svg"},
            {"heading", "format-heading.svg"},
            {"quote", "format-quote.svg"},
            {"bullet", "format-bullets.svg"},
            {"number", "format-numbers.svg"},
            {"link", "link.svg"}
          ] do
        # `.btn img:not([class])` is what inverts the icon in dark mode
        assert has_element?(
                 view,
                 ~s|#composer-toolbar button[data-format="#{format}"] img:not([class])[src*="/images/#{icon}"][aria-hidden=true]|
               )

        refute has_element?(view, ~s(#composer-toolbar button[data-format="#{format}"] span))

        assert File.exists?(Path.join("priv/static/images", icon))
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

    test "links and nested lists are rendered", %{conn: conn, user: user, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

      body =
        "See [the **docs**](https://elixir-lang.org/docs?a=1&b=2) and [bad](javascript:alert(1))\n" <>
          "- one\n  - two\n    1. three\n- four"

      view |> form("#composer", %{body: body}) |> render_submit()

      assert has_element?(
               view,
               ~s(.lexxy-content a[href="https://elixir-lang.org/docs?a=1&b=2"][target=_blank][rel=noopener] strong),
               "docs"
             )

      refute has_element?(view, ~s(.lexxy-content a[href^="javascript"]))
      assert has_element?(view, ".lexxy-content", "[bad](javascript:alert(1))")
      assert has_element?(view, ".lexxy-content ul > li > ul > li > ol > li", "three")
      assert has_element?(view, ".lexxy-content ul > li", "four")

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
