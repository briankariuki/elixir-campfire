defmodule CampfireWeb.UserAuth do
  @moduledoc """
  Cookie-session authentication for controllers and LiveViews.

  The Plug session holds `:session_token` (a `Campfire.Accounts.Session` token) and
  `:live_socket_id` (`"users_socket:<user_id>"`, so logout/ban/deactivate disconnect LiveViews).
  The signed-in user is assigned as `:current_user`.
  """
  use CampfireWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Campfire.Accounts

  ## Plugs

  @doc "Assigns `:current_user` (or nil) from the session token."
  def fetch_current_user(conn, _opts) do
    with token when is_binary(token) <- get_session(conn, :session_token),
         %{user: user} = session <- Accounts.get_session_by_token!(token) do
      Accounts.touch_session(session, client_info(conn), actor: user)
      assign(conn, :current_user, user)
    else
      _ -> assign(conn, :current_user, nil)
    end
  end

  @doc "Redirects to the login page (remembering the URL) unless signed in."
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> maybe_store_return_to()
      |> redirect(to: ~p"/session/new")
      |> halt()
    end
  end

  @doc "Sends signed-in users to `/` (for the login and join pages)."
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn |> redirect(to: ~p"/") |> halt()
    else
      conn
    end
  end

  @doc "Rejects non-GET/HEAD requests from banned IPs with 429."
  def block_banned_ip(%{method: method} = conn, _opts) when method in ["GET", "HEAD"], do: conn

  def block_banned_ip(conn, _opts) do
    if Accounts.banned_ip?(ip_string(conn)) do
      conn |> send_resp(:too_many_requests, "") |> halt()
    else
      conn
    end
  end

  ## Logging in and out

  @doc "Starts a new session for `user` and redirects to the stored return URL (or `/`)."
  def log_in_user(conn, user) do
    {:ok, session} = Accounts.create_session(client_info(conn), actor: user)
    return_to = get_session(conn, :user_return_to)

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> put_session(:session_token, session.token)
    |> put_session(:live_socket_id, Campfire.Broadcast.socket_id(user.id))
    |> redirect(to: return_to || ~p"/")
  end

  @doc "Destroys the current session (disconnecting LiveViews) and redirects to `/`."
  def log_out_user(conn) do
    with token when is_binary(token) <- get_session(conn, :session_token),
         %{user: user} = session <- Accounts.get_session_by_token!(token) do
      Accounts.destroy_session(session, actor: user)
    end

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> redirect(to: ~p"/")
  end

  ## LiveView on_mount hooks
  #
  #   live_session :authenticated, on_mount: [{CampfireWeb.UserAuth, :ensure_authenticated}]
  #   live_session :admin, on_mount: [{CampfireWeb.UserAuth, :ensure_admin}]

  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user && not banned_peer?(socket) do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/session/new")}
    end
  end

  def on_mount(:ensure_admin, params, session, socket) do
    case on_mount(:ensure_authenticated, params, session, socket) do
      {:cont, %{assigns: %{current_user: %{role: :administrator}}} = socket} ->
        {:cont, socket}

      {:cont, socket} ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(:error, "You must be an administrator.")
         |> Phoenix.LiveView.redirect(to: ~p"/")}

      halt ->
        halt
    end
  end

  defp mount_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      with token when is_binary(token) <- session["session_token"],
           %{user: user} <- Accounts.get_session_by_token!(token) do
        user
      else
        _ -> nil
      end
    end)
  end

  ## Helpers

  # Banned IPs can't act over the LiveView socket (the HTTP side is `block_banned_ip`)
  defp banned_peer?(socket) do
    Phoenix.LiveView.connected?(socket) and
      case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
        %{address: address} -> Accounts.banned_ip?(address |> :inet.ntoa() |> to_string())
        _ -> false
      end
  end

  defp maybe_store_return_to(%{method: "GET"} = conn),
    do: put_session(conn, :user_return_to, current_path(conn))

  defp maybe_store_return_to(conn), do: conn

  defp client_info(conn) do
    %{ip_address: ip_string(conn), user_agent: List.first(get_req_header(conn, "user-agent"))}
  end

  defp ip_string(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
