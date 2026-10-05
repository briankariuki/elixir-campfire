defmodule Campfire.Chat.Message.Changes.NotifyCreated do
  @moduledoc """
  After a message is created and committed: tells the room, flags unread rooms to every
  member, and delivers bot webhooks (unless `deliver_webhooks?` is false).
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Campfire.Broadcast
  alias Campfire.Chat.Membership

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.after_transaction(changeset, fn
      changeset, {:ok, message} ->
        Broadcast.room(message.room_id, {:message_created, message})
        Broadcast.users(Membership.member_ids(message.room_id), {:room_unread, message.room_id})

        if Changeset.get_argument(changeset, :deliver_webhooks?) != false do
          Campfire.Webhooks.deliver_for_message(message, Changeset.get_argument(changeset, :room))
        end

        {:ok, message}

      _changeset, error ->
        error
    end)
  end
end
