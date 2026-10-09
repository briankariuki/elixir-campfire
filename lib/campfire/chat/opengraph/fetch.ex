defmodule Campfire.Chat.Opengraph.Fetch do
  @moduledoc """
  Fetches the HTML of a page for a link preview, safely (the server makes the request on behalf of
  a chat user, so it must not reach internal services; see the original Campfire's
  `Opengraph::Fetch` and `RestrictedHTTP::PrivateNetworkGuard`).

  Safeguards:

    * only `http` and `https` URLs, without credentials;
    * the host is resolved here and every address must be public (`Campfire.Chat.Opengraph.Address`);
      the request then connects to that very address (`Campfire.Chat.Opengraph.Transport`), so a
      second DNS answer can't redirect it;
    * redirects are followed manually, at most 3, and each hop goes through the same checks;
    * connect timeout 3s, 5s per read, 10s for the whole response;
    * only a `200` response with `text/html`, read as a stream and aborted past 1 MB (also when
      `Content-Length` announces more); no compression is requested, so there is no decompression
      to blow up.

  The Req options are `config :campfire, :opengraph_req_options` (tests plug in `Req.Test` there),
  the resolver `config :campfire, :opengraph_resolver, {module, function}` (`resolve/1` by default;
  it returns `{:ok, [ip]} | {:error, reason}`).
  """

  alias Campfire.Chat.Opengraph.{Address, Transport}

  @max_redirects 3
  @max_body 1_048_576
  @connect_timeout 3_000
  @receive_timeout 5_000
  @total_timeout 10_000
  @redirect_statuses [301, 302, 303, 307, 308]
  @user_agent "Mozilla/5.0 (compatible; CampfireLinkPreview/1.0)"

  @type page :: %{uri: URI.t(), body: binary(), content_type: String.t()}

  @doc "Fetches `url`; `uri` in the result is the final URL after redirects."
  @spec get(String.t()) :: {:ok, page()} | {:error, term()}
  def get(url) when is_binary(url) do
    deadline = System.monotonic_time(:millisecond) + @total_timeout
    follow(url, @max_redirects, deadline)
  end

  @doc "The maximum number of response body bytes read."
  def max_body, do: @max_body

  @doc "Resolves `host` to its IPv4 and IPv6 addresses (the default resolver)."
  @spec resolve(String.t()) :: {:ok, [:inet.ip_address()]} | {:error, term()}
  def resolve(host) do
    name = String.to_charlist(host)

    case Enum.flat_map([:inet, :inet6], &lookup(name, &1)) do
      [] -> {:error, :nxdomain}
      ips -> {:ok, ips}
    end
  end

  defp lookup(name, family) do
    case :inet.getaddrs(name, family, @connect_timeout) do
      {:ok, ips} -> ips
      {:error, _} -> []
    end
  end

  defp follow(url, redirects_left, deadline) do
    with {:ok, uri} <- parse(url),
         {:ok, ip} <- resolve_public(uri.host),
         {:ok, response} <- request(uri, ip, deadline) do
      handle(response, uri, redirects_left, deadline)
    end
  end

  @doc false
  def parse(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host, userinfo: nil} = uri}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        {:ok, uri}

      _ ->
        {:error, :invalid_url}
    end
  end

  defp resolve_public(host) do
    with {:ok, ips} <- addresses(host) do
      if Enum.all?(ips, &Address.public?/1), do: {:ok, hd(ips)}, else: {:error, :private_address}
    end
  end

  defp addresses(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip} ->
        {:ok, [ip]}

      {:error, _} ->
        {module, function} =
          Application.get_env(:campfire, :opengraph_resolver, {__MODULE__, :resolve})

        apply(module, function, [host])
    end
  end

  defp request(uri, ip, deadline) do
    options =
      Keyword.merge(
        [
          method: :get,
          url: uri,
          adapter: Transport,
          headers: [
            {"user-agent", @user_agent},
            {"accept", "text/html,application/xhtml+xml;q=0.9"}
          ],
          into: &collect(&1, &2, deadline),
          redirect: false,
          retry: false,
          decode_body: false,
          compressed: false
        ],
        Application.get_env(:campfire, :opengraph_req_options, [])
      )

    options
    |> Req.new()
    |> Req.Request.put_private(:opengraph, %{
      ip: ip,
      connect_timeout: @connect_timeout,
      receive_timeout: @receive_timeout,
      deadline: deadline
    })
    |> Req.request()
  end

  # Redirects: the next hop is fully re-checked.
  defp handle(%Req.Response{status: status} = response, uri, redirects_left, deadline)
       when status in @redirect_statuses do
    with [location | _] <- Req.Response.get_header(response, "location"),
         true <- redirects_left > 0 || {:error, :too_many_redirects},
         {:ok, target} <- redirect_target(uri, location) do
      follow(target, redirects_left - 1, deadline)
    else
      {:error, _} = error -> error
      _ -> {:error, :bad_redirect}
    end
  end

  defp handle(%Req.Response{status: 200} = response, uri, _redirects_left, _deadline) do
    content_type = content_type(response)

    case Req.Response.get_private(response, :opengraph, %{}) do
      %{abort: reason} when not is_nil(reason) ->
        {:error, reason}

      _state when content_type != "text/html" ->
        {:error, :not_html}

      state ->
        body = state |> Map.get(:chunks, []) |> Enum.reverse() |> IO.iodata_to_binary()
        {:ok, %{uri: uri, body: body, content_type: content_type}}
    end
  end

  defp handle(%Req.Response{status: status}, _uri, _redirects_left, _deadline),
    do: {:error, {:status, status}}

  defp redirect_target(uri, location) do
    {:ok, uri |> URI.merge(String.trim(location)) |> URI.to_string()}
  rescue
    _ -> {:error, :bad_redirect}
  end

  # `into:` function: collects the body, aborting on anything that isn't a small HTML page. The
  # state lives in the response's private map.
  defp collect({:data, data}, {request, response}, deadline) do
    state = Req.Response.get_private(response, :opengraph, %{size: 0, chunks: [], abort: nil})
    size = state.size + byte_size(data)

    abort =
      cond do
        response.status != 200 -> :skip
        not html?(response) -> :not_html
        declared_length(response) > @max_body -> :too_large
        size > @max_body -> :too_large
        System.monotonic_time(:millisecond) > deadline -> :timeout
        true -> nil
      end

    state = %{state | size: size, chunks: [data | state.chunks], abort: abort}
    response = Req.Response.put_private(response, :opengraph, state)

    if abort, do: {:halt, {request, response}}, else: {:cont, {request, response}}
  end

  # A redirect or error response's body is never needed.
  defp content_type(response) do
    response
    |> Req.Response.get_header("content-type")
    |> List.first("")
    |> String.split(";")
    |> hd()
    |> String.trim()
    |> String.downcase()
  end

  defp html?(response), do: content_type(response) == "text/html"

  defp declared_length(response) do
    with [value | _] <- Req.Response.get_header(response, "content-length"),
         {length, ""} <- Integer.parse(value) do
      length
    else
      _ -> 0
    end
  end
end
