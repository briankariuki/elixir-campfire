defmodule Campfire.Chat.Room.Changes.ReviseMembers do
  @moduledoc """
  Closed rooms: grants the `user_ids` argument and revokes everyone else.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Campfire.Chat.{Membership, Room}

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.after_action(changeset, fn changeset, room ->
      wanted = Room.existing_user_ids(Changeset.get_argument(changeset, :user_ids) || [])
      revoked = Membership.revoke(room.id, Membership.member_ids(room.id) -- wanted)
      Membership.grant(room, wanted)
      # Revoked users are also told after the outer commit (NotifyMembers): the :revoke action's
      # own broadcast runs inside this transaction, so a sidebar reload could still see the room.
      {:ok, Ash.Resource.put_metadata(room, :revoked_user_ids, revoked)}
    end)
  end

  # Everything is in hooks and arguments, so the same changeset works for atomic actions.
  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
