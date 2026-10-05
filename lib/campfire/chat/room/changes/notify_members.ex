defmodule Campfire.Chat.Room.Changes.NotifyMembers do
  @moduledoc """
  After commit: tells the room's members to refresh their sidebar, and tells users removed by
  `ReviseMembers` (see `:revoked_user_ids` metadata) that the room is gone for them.
  """

  use Ash.Resource.Change

  alias Campfire.Broadcast
  alias Campfire.Chat.Membership

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_transaction(changeset, fn
      _changeset, {:ok, room} ->
        Broadcast.users(Membership.member_ids(room.id), :sidebar_changed)

        revoked = Ash.Resource.get_metadata(room, :revoked_user_ids) || []
        Broadcast.users(revoked, {:room_removed, room.id})
        Broadcast.users(revoked, :sidebar_changed)
        {:ok, room}

      _changeset, error ->
        error
    end)
  end

  # Everything is in hooks and arguments, so the same changeset works for atomic actions.
  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
