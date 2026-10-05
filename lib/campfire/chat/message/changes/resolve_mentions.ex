defmodule Campfire.Chat.Message.Changes.ResolveMentions do
  @moduledoc """
  Fills `mentioned_user_ids` with the room members named (`@Full Name`) in the body.

  Not atomic: it needs the room's member list.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Campfire.Chat.Mentions

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.before_action(changeset, fn changeset ->
      room_id = Changeset.get_attribute(changeset, :room_id)
      body = Changeset.get_attribute(changeset, :body)
      ids = Mentions.mentioned_ids(body, Mentions.room_members(room_id))
      Changeset.force_change_attribute(changeset, :mentioned_user_ids, ids)
    end)
  end
end
