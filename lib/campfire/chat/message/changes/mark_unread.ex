defmodule Campfire.Chat.Message.Changes.MarkUnread do
  @moduledoc """
  After a message is created: sets `unread_at` on the room's members who aren't the author,
  aren't invisible and don't currently have the room open.
  """

  use Ash.Resource.Change

  alias Campfire.Chat.Membership
  alias Campfire.Presence

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, message ->
      mark_unread(message)
      {:ok, message}
    end)
  end

  # One atomic UPDATE over every member to mark. System work (the author can't write other
  # people's memberships), hence `authorize?: false`.
  defp mark_unread(message) do
    %{room_id: room_id, creator_id: creator_id} = message
    present_ids = Presence.present_user_ids(room_id)

    Membership
    |> Ash.Query.filter(
      room_id == ^room_id and user_id != ^creator_id and involvement != :invisible and
        user_id not in ^present_ids
    )
    |> Ash.bulk_update!(:mark_unread, %{unread_at: message.inserted_at},
      authorize?: false,
      strategy: :atomic
    )
  end
end
