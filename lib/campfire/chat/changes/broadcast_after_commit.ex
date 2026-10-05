defmodule Campfire.Chat.Changes.BroadcastAfterCommit do
  @moduledoc """
  Broadcasts a PubSub message once the action's transaction has committed.

  Options:

    * `:topic` - `:room` (`"room:<room_id>"`) or `:user` (`"user:<user_id>"`, from the record's
      `user_id`)
    * `:event` - the event name, e.g. `:message_updated`
    * `:payload` - what goes with the event: `:record` (`{event, record}`, the default),
      `:room_id` (`{event, record.room_id}`) or `:none` (the bare `event` atom)

  Nothing is sent when the action fails.
  """

  use Ash.Resource.Change

  alias Campfire.Broadcast
  alias Campfire.Chat.Boost

  @topics [:room, :user]
  @payloads [:record, :room_id, :none]

  @impl true
  def init(opts) do
    topic = Keyword.get(opts, :topic)
    event = Keyword.get(opts, :event)
    payload = Keyword.get(opts, :payload, :record)

    cond do
      topic not in @topics -> {:error, "topic must be one of #{inspect(@topics)}"}
      not is_atom(event) or is_nil(event) -> {:error, "event must be an atom"}
      payload not in @payloads -> {:error, "payload must be one of #{inspect(@payloads)}"}
      true -> {:ok, topic: topic, event: event, payload: payload}
    end
  end

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.after_transaction(changeset, fn
      _changeset, {:ok, record} ->
        broadcast(record, opts)
        {:ok, record}

      _changeset, error ->
        error
    end)
  end

  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}

  defp broadcast(record, opts) do
    message = message(record, opts[:event], opts[:payload])

    case opts[:topic] do
      :room -> Broadcast.room(room_id(record), message)
      :user -> Broadcast.user(record.user_id, message)
    end
  end

  defp message(record, event, :record), do: {event, record}
  defp message(record, event, :room_id), do: {event, record.room_id}
  defp message(_record, event, :none), do: event

  # A boost has no room_id of its own: it is the room of its message.
  defp room_id(%Boost{} = boost), do: Boost.room_id(boost)
  defp room_id(record), do: record.room_id
end
