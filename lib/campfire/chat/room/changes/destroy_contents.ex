defmodule Campfire.Chat.Room.Changes.DestroyContents do
  @moduledoc """
  Deleting a room: remembers its members and attachment keys before the rows cascade away, then
  after commit deletes the files and tells the members the room is gone.

  Not atomic: it reads the room's contents first.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Campfire.{Broadcast, Uploads}
  alias Campfire.Chat.{Membership, Message}

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Changeset.before_action(fn changeset ->
      room_id = changeset.data.id

      Changeset.put_context(changeset, :room_contents, %{
        member_ids: Membership.member_ids(room_id),
        attachment_keys: attachment_keys(room_id)
      })
    end)
    |> Changeset.after_transaction(fn
      changeset, {:ok, room} ->
        %{member_ids: member_ids, attachment_keys: keys} = changeset.context.room_contents
        Enum.each(keys, &Uploads.delete/1)
        Broadcast.users(member_ids, {:room_removed, room.id})
        Broadcast.users(member_ids, :sidebar_changed)
        {:ok, room}

      _changeset, error ->
        error
    end)
  end

  # Internal read of the room's own contents; the destroy action has already been authorized.
  defp attachment_keys(room_id) do
    Message
    |> Ash.Query.filter(room_id == ^room_id and not is_nil(attachment_key))
    |> Ash.Query.select([:attachment_key])
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.attachment_key)
  end
end
