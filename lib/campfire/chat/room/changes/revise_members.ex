defmodule Campfire.Chat.Room.Changes.ReviseMembers do
  @moduledoc """
  Closed rooms: grants the `user_ids` argument and revokes everyone else. Revoked users are
  notified by `Membership`'s `:revoke` action.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Campfire.Chat.{Membership, Room}

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.after_action(changeset, fn changeset, room ->
      wanted = Room.existing_user_ids(Changeset.get_argument(changeset, :user_ids) || [])
      Membership.revoke(room.id, Membership.member_ids(room.id) -- wanted)
      Membership.grant(room, wanted)
      {:ok, room}
    end)
  end
end
