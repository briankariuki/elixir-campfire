defmodule CampfireWeb.RoomWelcomeTest do
  use CampfireWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Campfire.Fixtures

  alias Campfire.Chat.Message

  setup :register_and_log_in_user

  setup %{user: user} do
    # The first room created is the account's original room (what first run calls "All Talk")
    original = open_room_fixture(user, "All Talk")
    other = open_room_fixture(user, "Watercooler")
    %{original: original, other: other}
  end

  describe "system welcome" do
    test "shows in the original room with the join link", %{conn: conn, original: original} do
      account = account_fixture()
      {:ok, view, _html} = live(conn, ~p"/rooms/#{original.id}")

      assert has_element?(view, "#system_welcome.message.message--formatted")
      assert has_element?(view, "#system_welcome figure.account-logo.avatar")

      assert has_element?(
               view,
               "#system_welcome #invite_url[readonly][value$='/join/#{account.join_code}']"
             )

      assert has_element?(
               view,
               "#system_welcome #copy-invite-url[data-copy$='/join/#{account.join_code}']"
             )

      # Regenerating the join link stays on the account page
      refute has_element?(view, "#regenerate-join-code")
    end

    test "is the same for members and administrators", %{conn: conn, original: original} do
      admin = admin_fixture()
      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/rooms/#{original.id}")

      assert has_element?(view, "#system_welcome #invite_url")
    end

    test "does not show in other rooms", %{conn: conn, other: other} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{other.id}")

      refute has_element?(view, "#system_welcome")
    end

    test "does not show in a closed or direct room", %{conn: conn, user: user} do
      friend = user_fixture()
      closed = closed_room_fixture(user, [user, friend])
      direct = direct_room_fixture(user, [friend])

      for room <- [closed, direct] do
        {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")
        refute has_element?(view, "#system_welcome")
      end
    end

    test "keeps showing with a few messages and goes away once a page is full", %{
      conn: conn,
      user: user,
      original: original
    } do
      for i <- 1..3, do: message_fixture(original, user, %{body: "Hi #{i}"})
      {:ok, view, _html} = live(conn, ~p"/rooms/#{original.id}")
      assert has_element?(view, "#system_welcome")

      # New messages arriving live keep it until a page of messages has accumulated
      for i <- 4..(Message.page_size() - 1),
          do: message_fixture(original, user, %{body: "Hi #{i}"})

      render(view)
      assert has_element?(view, "#system_welcome")

      message_fixture(original, user, %{body: "One more"})
      render(view)
      refute has_element?(view, "#system_welcome")
    end

    test "does not show in a room with more than a page of messages", %{
      conn: conn,
      user: user,
      original: original
    } do
      for i <- 1..(Message.page_size() + 1),
          do: message_fixture(original, user, %{body: "Hi #{i}"})

      {:ok, view, _html} = live(conn, ~p"/rooms/#{original.id}")

      refute has_element?(view, "#system_welcome")
    end
  end

  describe "account logo in the nav" do
    test "is not shown without a logo", %{conn: conn, other: other} do
      account_fixture(%{logo_key: nil})
      {:ok, view, _html} = live(conn, ~p"/rooms/#{other.id}")

      refute has_element?(view, "#nav figure.account-logo")
    end

    test "is shown before the room name when the account has one", %{conn: conn, other: other} do
      account_fixture(%{logo_key: "logo-key"})
      {:ok, view, html} = live(conn, ~p"/rooms/#{other.id}")

      assert has_element?(view, "#nav figure.account-logo.avatar img[src^='/account/logo']")
      assert has_element?(view, "#nav figure.account-logo + span.room--current")

      # The original CSS keys off a body class, synced on live navigation from the :body_class assign
      assert html =~ ~s(<body class="sidebar account-has-logo")
    end

    test "the body class is plain without a logo", %{conn: conn, other: other} do
      account_fixture(%{logo_key: nil})
      html = conn |> get(~p"/rooms/#{other.id}") |> html_response(200)

      assert html =~ ~s(<body class="sidebar")
    end
  end
end
