defmodule CampfireWeb.ClientIP do
  @moduledoc """
  The client's IP address, for sessions, the sign-in rate limit and IP bans.

  Behind a reverse proxy every connection comes from the proxy, so with
  `config :campfire, :trust_proxy_headers, true` (`TRUST_PROXY_HEADERS=true` in production) the
  address is taken from the first `X-Forwarded-For` entry instead. Only enable it when the app is
  reachable solely through a proxy that overwrites that header (Caddy does by default, see
  `docker-compose.yml`); otherwise clients can pick their own address.

  As a plug (in `CampfireWeb.Endpoint`) it rewrites `conn.remote_ip`, so everything reading it
  (`CampfireWeb.UserAuth.ip_string/1`) gets the client's address. LiveView sockets get the same
  treatment in `from_socket/1`, which needs `:x_headers` in the socket's `connect_info`.
  """

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @doc "Sets `conn.remote_ip` from `X-Forwarded-For` when proxy headers are trusted."
  @impl true
  def call(conn, _opts) do
    if trust_proxy_headers?(), do: Plug.RewriteOn.call(conn, [:x_forwarded_for]), else: conn
  end

  @doc "The client IP of a connected LiveView socket as a string, or nil when unknown."
  def from_socket(socket) do
    forwarded =
      trust_proxy_headers?() &&
        socket |> Phoenix.LiveView.get_connect_info(:x_headers) |> forwarded_for()

    forwarded ||
      case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
        %{address: address} -> to_string(:inet.ntoa(address))
        _ -> nil
      end
  end

  defp forwarded_for(headers) when is_list(headers) do
    with {_, value} <- List.keyfind(headers, "x-forwarded-for", 0),
         [client | _] <- String.split(value, ","),
         {:ok, address} <-
           client |> String.trim() |> String.to_charlist() |> :inet.parse_address() do
      to_string(:inet.ntoa(address))
    else
      _ -> nil
    end
  end

  defp forwarded_for(_headers), do: nil

  defp trust_proxy_headers?, do: Application.get_env(:campfire, :trust_proxy_headers, false)
end
