defmodule Campfire.Broadcast do
  @moduledoc """
  PubSub topics and messages emitted by the domain layer (see docs/PORTING.md §4).

  The messages are sent by `Ash.Notifier.PubSub` (via `Campfire.PubSubBroadcaster`) and
  `Campfire.Notifiers.Fanout`; this module holds the topic names and helpers. The web layer
  subscribes with `subscribe_room/1`, `subscribe_user/1`, etc. and handles:

    * `"room:<id>"`: `{:message_created, message}`, `{:message_updated, message}`,
      `{:message_deleted, message}`, `{:boost_created, boost}`, `{:boost_deleted, boost}`
    * `"user:<id>"`: `{:room_unread, room_id}`, `{:room_read, room_id}`, `:sidebar_changed`,
      `{:room_removed, room_id}`
  """

  @pubsub Campfire.PubSub

  def room_topic(room_id), do: "room:#{room_id}"
  def typing_topic(room_id), do: "room:#{room_id}:typing"
  def user_topic(user_id), do: "user:#{user_id}"
  def presence_topic(room_id), do: "presence:room:#{room_id}"
  def socket_id(user_id), do: "users_socket:#{user_id}"

  def subscribe_room(room_id), do: Phoenix.PubSub.subscribe(@pubsub, room_topic(room_id))
  def subscribe_user(user_id), do: Phoenix.PubSub.subscribe(@pubsub, user_topic(user_id))
  def subscribe_typing(room_id), do: Phoenix.PubSub.subscribe(@pubsub, typing_topic(room_id))

  @doc "Broadcasts `message` to `\"user:<user_id>\"`."
  def user(user_id, message), do: Phoenix.PubSub.broadcast(@pubsub, user_topic(user_id), message)

  @doc "Broadcasts `message` to `\"user:<id>\"` for every id in `user_ids`."
  def users(user_ids, message) do
    user_ids |> Enum.uniq() |> Enum.each(&user(&1, message))
  end

  @doc """
  Disconnects every LiveView socket of the user. Same as
  `CampfireWeb.Endpoint.broadcast("users_socket:<id>", "disconnect", %{})`, without
  depending on the web layer.
  """
  def disconnect_user(user_id) do
    topic = socket_id(user_id)

    Phoenix.PubSub.broadcast(@pubsub, topic, %Phoenix.Socket.Broadcast{
      topic: topic,
      event: "disconnect",
      payload: %{}
    })
  end
end
