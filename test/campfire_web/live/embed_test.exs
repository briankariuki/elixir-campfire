defmodule CampfireWeb.EmbedTest do
  use CampfireWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Campfire.Fixtures

  alias Campfire.Chat

  setup :register_and_log_in_user

  setup %{user: user} do
    %{room: open_room_fixture(user, "Watercooler")}
  end

  @embed %{
    "url" => "https://example.com/post",
    "title" => "A <b>post</b>",
    "description" => "About the post",
    "image_url" => "https://example.com/cover.png",
    "site_name" => "Example"
  }

  defp message_selector(message), do: "#messages-#{message.client_message_id}"

  defp with_embed(message, embed) do
    message
    |> Ash.Changeset.for_update(:set_embed, %{embed: embed}, authorize?: false)
    |> Ash.update!()
  end

  test "renders the embed under the message with the original markup", %{
    conn: conn,
    user: user,
    room: room
  } do
    message =
      room |> message_fixture(user, body: "see https://example.com/post") |> with_embed(@embed)

    {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

    embed = message_selector(message) <> " figure.attachment--og .og-embed"

    assert has_element?(view, embed <> " .og-embed__title a[href='https://example.com/post']")

    assert has_element?(
             view,
             embed <> " .og-embed__title a[target=_blank][rel~=noopener]",
             "A <b>post</b>"
           )

    assert has_element?(view, embed <> " .og-embed__description", "About the post")
    assert has_element?(view, embed <> " .og-embed__site-name", "Example")

    assert has_element?(
             view,
             embed <>
               " .og-embed__image img[src='https://example.com/cover.png'][loading=lazy][referrerpolicy=no-referrer]"
           )

    # the markup is escaped, not interpreted
    refute has_element?(view, embed <> " .og-embed__title b")
  end

  test "renders nothing for messages without an embed, and only links http(s)", %{
    conn: conn,
    user: user,
    room: room
  } do
    plain = message_fixture(room, user, body: "just text")

    unsafe =
      room
      |> message_fixture(user, body: "see https://example.com/post")
      |> with_embed(%{
        "url" => "javascript:alert(1)",
        "title" => "Unsafe",
        "image_url" => "javascript:alert(2)"
      })

    {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

    refute has_element?(view, message_selector(plain) <> " .og-embed")
    assert has_element?(view, message_selector(unsafe) <> " .og-embed__title", "Unsafe")
    refute has_element?(view, message_selector(unsafe) <> " .og-embed__title a")
    refute has_element?(view, message_selector(unsafe) <> " .og-embed__image")
  end

  test "an open room shows the preview as soon as the job stores it", %{
    conn: conn,
    user: user,
    room: room
  } do
    {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

    message = message_fixture(room, user, body: "no preview yet")
    assert has_element?(view, message_selector(message))
    refute has_element?(view, message_selector(message) <> " .og-embed")

    with_embed(message, @embed)

    assert has_element?(view, message_selector(message) <> " .og-embed__title a")
  end

  test "a new message with a link is unfurled live", %{conn: conn, user: user, room: room} do
    Req.Test.stub(Campfire.Chat.Opengraph, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(200, ~s(<meta property="og:title" content="Fetched title">))
    end)

    {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")

    message = Chat.create_message!(room, %{body: "look https://example.com/live"}, actor: user)

    assert has_element?(view, message_selector(message) <> " .og-embed__title a", "Fetched title")
  end
end
