defmodule Campfire.Chat.Room.Changes.NotifyMembers do
  @moduledoc """
  After commit: tells the room's members to refresh their sidebar. Users removed from a closed
  room are notified by the `:revoke` action, not here.
  """

  use Ash.Resource.Change

  alias Campfire.Broadcast
  alias Campfire.Chat.Membership

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_transaction(changeset, fn
      _changeset, {:ok, room} ->
        Broadcast.users(Membership.member_ids(room.id), :sidebar_changed)
        {:ok, room}

      _changeset, error ->
        error
    end)
  end
end
