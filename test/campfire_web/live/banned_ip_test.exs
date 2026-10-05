defmodule CampfireWeb.BannedIpTest do
  @moduledoc """
  A signed-in user whose LiveView socket comes from a banned IP is refused by
  `UserAuth.on_mount(:ensure_authenticated, ...)`. HTTP GETs from banned IPs are allowed (only
  non-GETs get 429), so the redirect target must not bounce a signed-in user back into a
  LiveView: `/session/new` is guests-only and sent them to `/`, which looped forever.
  """
  use CampfireWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Campfire.Fixtures

  @banned_ip {9, 9, 9, 9}
  @max_hops 6

  setup :register_and_log_in_user

  setup %{conn: conn, user: user} do
    other = user_fixture()
    room = open_room_fixture(user, "Watercooler")

    Campfire.Accounts.Ban
    |> Ash.Changeset.for_create(:create, %{user_id: other.id, ip_address: "9.9.9.9"})
    |> Ash.create!(authorize?: false)

    # Both the HTTP request and the LiveView socket come from the banned (public) address.
    # LiveViewTest hands the conn to get_connect_info/2, which reads the test adapter's peer data.
    conn =
      %{conn | remote_ip: @banned_ip}
      |> Plug.Test.put_peer_data(%{address: @banned_ip, port: 1234, ssl_cert: nil})

    %{conn: conn, room: room}
  end

  test "the socket is refused with a redirect to /blocked", %{conn: conn, room: room} do
    assert {:error, {:redirect, %{to: "/blocked"}}} = live(conn, ~p"/rooms/#{room.id}")
  end

  test "following the redirects from a room terminates on the blocked page",
       %{conn: conn, room: room} do
    assert {"/blocked", conn} = follow_redirects(conn, ~p"/rooms/#{room.id}")
    assert conn.status == 429
    assert conn.resp_body =~ ~s(id="blocked")
  end

  test "following the redirects from / terminates on the blocked page", %{conn: conn} do
    assert {"/blocked", %{status: 429}} = follow_redirects(conn, ~p"/")
  end

  test "the blocked page doesn't redirect, signed in or not", %{conn: conn} do
    assert conn |> get(~p"/blocked") |> html_response(429) =~ ~s(id="blocked")
    assert build_conn() |> get(~p"/blocked") |> html_response(429) =~ ~s(id="blocked")
  end

  # Visits `path` like a browser: an HTTP GET, then (if the page is a LiveView) the connected
  # mount, following every redirect. Returns the final path and its HTTP response, or fails if
  # the chain doesn't settle within @max_hops (a redirect loop).
  defp follow_redirects(conn, path, visited \\ []) do
    if length(visited) >= @max_hops do
      flunk("redirect loop: #{Enum.join(Enum.reverse([path | visited]), " -> ")}")
    end

    visited = [path | visited]
    resp = get(conn, path)

    cond do
      resp.status in 300..399 ->
        follow_redirects(conn, redirected_to(resp, resp.status), visited)

      resp.status == 200 and resp.resp_body =~ "data-phx-main" ->
        case live(conn, path) do
          {:ok, _view, _html} -> {path, resp}
          {:error, {_kind, %{to: to}}} -> follow_redirects(conn, to, visited)
        end

      true ->
        {path, resp}
    end
  end
end
