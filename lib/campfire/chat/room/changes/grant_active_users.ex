defmodule Campfire.Chat.Room.Changes.GrantActiveUsers do
  @moduledoc "Open rooms: every active user (bots included) is a member."

  use Ash.Resource.Change

  alias Campfire.Chat.{Membership, Room}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, room ->
      Membership.grant(room, Room.active_user_ids())
      {:ok, room}
    end)
  end
end
