defmodule CampfireWeb.BlockedController do
  @moduledoc """
  The page a signed-in user lands on when their LiveView socket comes from a banned IP.

  Banned IPs may still make GET requests (`CampfireWeb.UserAuth.block_banned_ip/2`), but every
  LiveView interaction goes over the socket, so `UserAuth.on_mount(:ensure_authenticated, ...)`
  refuses the socket and redirects here. The page is neither guests-only nor signed-in-only and
  never redirects (even when the HTTP `remote_ip` isn't banned but the socket peer is), so it
  always terminates the redirect chain. It answers 429, like the original's banned-IP response.
  """
  use CampfireWeb, :controller

  def show(conn, _params) do
    conn
    |> put_status(:too_many_requests)
    |> put_view(html: CampfireWeb.BlockedHTML)
    |> render(:show, page_title: "Blocked")
  end
end
