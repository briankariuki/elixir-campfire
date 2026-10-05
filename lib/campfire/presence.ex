defmodule Campfire.Presence do
  @moduledoc """
  Tracks who is looking at a room. `RoomLive` tracks `self()` on
  `"presence:room:<room_id>"` with key `to_string(user_id)` while the tab is visible.
  Members present in a room are not marked unread for new messages there.
  """

  use Phoenix.Presence, otp_app: :campfire, pubsub_server: Campfire.PubSub

  alias Campfire.Broadcast

  @doc "Tracks `pid` as `user_id` in the room."
  def track_user(pid, room_id, user_id, meta \\ %{}) do
    track(pid, Broadcast.presence_topic(room_id), to_string(user_id), meta)
  end

  @doc "Stops tracking `pid` as `user_id` in the room."
  def untrack_user(pid, room_id, user_id) do
    untrack(pid, Broadcast.presence_topic(room_id), to_string(user_id))
  end

  @doc "Ids of the users currently present in the room."
  def present_user_ids(room_id) do
    room_id
    |> Broadcast.presence_topic()
    |> list()
    |> Map.keys()
    |> Enum.flat_map(fn key ->
      case Integer.parse(key) do
        {id, ""} -> [id]
        _ -> []
      end
    end)
  end
end
