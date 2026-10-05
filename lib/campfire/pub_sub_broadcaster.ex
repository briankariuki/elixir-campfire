defmodule Campfire.PubSubBroadcaster do
  @moduledoc """
  The `module` of every resource's `Ash.Notifier.PubSub` config (`broadcast_type :notification`).

  `Ash.Notifier.PubSub` calls `broadcast/3` after commit with the topic (`"room:<id>"` or
  `"user:<id>"`, see `Campfire.Broadcast`), the publication's event name and the
  `%Ash.Notifier.Notification{}`. This turns them into the messages the web layer handles
  (docs/PORTING.md §4) and sends them over `Campfire.PubSub`:

    * `message_created|message_updated|message_deleted|boost_created|boost_deleted`:
      `{event, record}`
    * `room_read|room_removed`: `{event, room_id}`
    * `sidebar_changed`: the bare atom `:sidebar_changed`
  """

  @pubsub Campfire.PubSub

  @record_events %{
    "message_created" => :message_created,
    "message_updated" => :message_updated,
    "message_deleted" => :message_deleted,
    "boost_created" => :boost_created,
    "boost_deleted" => :boost_deleted
  }

  @room_id_events %{
    "room_read" => :room_read,
    "room_removed" => :room_removed
  }

  @doc false
  def broadcast(topic, event, %Ash.Notifier.Notification{} = notification) do
    Phoenix.PubSub.broadcast(@pubsub, topic, message(event, notification))
  end

  defp message("sidebar_changed", _notification), do: :sidebar_changed

  defp message(event, %{data: record}) when is_map_key(@record_events, event),
    do: {Map.fetch!(@record_events, event), record}

  defp message(event, %{data: record}) when is_map_key(@room_id_events, event),
    do: {Map.fetch!(@room_id_events, event), record.room_id}
end
