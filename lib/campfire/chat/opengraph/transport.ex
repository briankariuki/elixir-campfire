defmodule Campfire.Chat.Opengraph.Transport do
  @moduledoc """
  The `Req` adapter link previews use instead of the default Finch one.

  `Campfire.Chat.Opengraph.Fetch` resolves the host and checks the address; this adapter then
  connects to *that address* (`request.private.opengraph.ip`) and sends the original host name for
  the `Host` header, SNI and certificate verification (`Mint.HTTP.connect/4`'s `:hostname`). So
  the connection can't be redirected to another address by a second DNS answer (DNS rebinding),
  and no Finch pool is started per host (Req starts and keeps one per distinct `:hostname`).

  One connection per request, HTTP/1 only, closed when the response is done or the `into:`
  function halts. `request.private.opengraph` carries `:ip`, `:connect_timeout`,
  `:receive_timeout` (per read) and `:deadline` (monotonic ms for the whole response).
  """

  @doc "The adapter function: `{request, response | exception}`."
  def run(%Req.Request{url: uri, into: into} = request) when is_function(into, 2) do
    settings = request.private.opengraph
    scheme = if uri.scheme == "https", do: :https, else: :http

    options = [
      mode: :passive,
      protocols: [:http1],
      hostname: uri.host,
      transport_opts: [timeout: settings.connect_timeout]
    ]

    with {:ok, conn} <- Mint.HTTP.connect(scheme, settings.ip, uri.port, options) do
      send_request(conn, request, settings)
    else
      {:error, error} -> {request, exception(error)}
    end
  end

  defp send_request(conn, request, settings) do
    uri = request.url
    path = (uri.path || "/") <> if(uri.query, do: "?" <> uri.query, else: "")
    headers = Req.Fields.get_list(request.headers)

    case Mint.HTTP.request(conn, "GET", path, headers, nil) do
      {:ok, conn, ref} ->
        receive_response(conn, ref, {request, Req.Response.new()}, settings)

      {:error, conn, error} ->
        Mint.HTTP.close(conn)
        {request, exception(error)}
    end
  end

  defp receive_response(conn, ref, {request, _response} = acc, settings) do
    remaining = settings.deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      Mint.HTTP.close(conn)
      {request, %Req.TransportError{reason: :timeout}}
    else
      case Mint.HTTP.recv(conn, 0, min(remaining, settings.receive_timeout)) do
        {:ok, conn, responses} ->
          handle_responses(responses, conn, ref, acc, settings)

        {:error, conn, error, _responses} ->
          Mint.HTTP.close(conn)
          {request, exception(error)}
      end
    end
  end

  defp handle_responses([], conn, ref, acc, settings),
    do: receive_response(conn, ref, acc, settings)

  defp handle_responses([response | rest], conn, ref, {request, resp} = acc, settings) do
    case response do
      {:status, ^ref, status} ->
        handle_responses(rest, conn, ref, {request, %{resp | status: status}}, settings)

      {:headers, ^ref, headers} ->
        resp = Req.Response.new(status: resp.status, headers: headers)
        handle_responses(rest, conn, ref, {request, resp}, settings)

      {:data, ^ref, data} ->
        case request.into.({:data, data}, acc) do
          {:cont, acc} ->
            handle_responses(rest, conn, ref, acc, settings)

          {:halt, acc} ->
            Mint.HTTP.close(conn)
            acc
        end

      {:done, ^ref} ->
        Mint.HTTP.close(conn)
        acc

      {:error, ^ref, error} ->
        Mint.HTTP.close(conn)
        {request, exception(error)}

      # trailers, pushes
      _ ->
        handle_responses(rest, conn, ref, acc, settings)
    end
  end

  defp exception(%Mint.TransportError{reason: reason}), do: %Req.TransportError{reason: reason}

  defp exception(%Mint.HTTPError{reason: reason}),
    do: %Req.HTTPError{protocol: :http1, reason: reason}

  defp exception(other) when is_exception(other), do: other
  defp exception(reason), do: %Req.TransportError{reason: reason}
end
