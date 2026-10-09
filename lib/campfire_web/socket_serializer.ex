defmodule CampfireWeb.SocketSerializer do
  @moduledoc """
  The websocket serializer of the `/live` socket: Phoenix's own V2 JSON serializer, except that a
  LiveView diff is JSON-encoded once for everybody who receives the same one.

  A message posted to a room is rendered by every connected `CampfireWeb.RoomLive`, and almost all
  of them produce the very same diff (the same stream insert; only the viewers that are the author,
  are mentioned or may edit the message differ). `Phoenix.LiveView.Channel` encodes the diff in the
  channel process, so N viewers cost N identical `encode_to_iodata!` calls and N copies of the
  resulting iodata sent to the transport process. Here the encoded payload is kept in
  `CampfireWeb.FrameCache`, keyed by the payload term itself (so a hit can only ever be the same
  payload, never "similar"), and is a single binary: the frame around it (`join_ref`, `ref`, topic,
  event) is built per call, which is all that differs between channels.

  Only diffs that carry templates (`:p`: a keyed comprehension got new entries, i.e. a stream
  insert) are kept; everything else, and everything that is not a diff, is the stock serializer's.
  `decode!/2` and `fastlane!/1` are the stock ones.
  """

  @behaviour Phoenix.Socket.Serializer

  alias Phoenix.Socket.Message
  alias Phoenix.Socket.V2.JSONSerializer

  @impl true
  defdelegate fastlane!(broadcast), to: JSONSerializer

  @impl true
  defdelegate decode!(raw_message, opts), to: JSONSerializer

  @impl true
  def encode!(%Message{event: "diff", payload: %{p: _} = payload} = message) do
    json = Phoenix.json_library()

    body =
      CampfireWeb.MessageBody.Cache.fetch(
        payload,
        fn -> payload |> json.encode_to_iodata!() |> IO.iodata_to_binary() end,
        CampfireWeb.FrameCache
      )

    # `["join_ref","ref","topic","diff"` + `,` + payload + `]`
    head =
      [message.join_ref, message.ref, message.topic, message.event]
      |> json.encode_to_iodata!()
      |> IO.iodata_to_binary()

    {:socket_push, :text, [binary_part(head, 0, byte_size(head) - 1), ",", body, "]"]}
  end

  def encode!(message), do: JSONSerializer.encode!(message)
end
