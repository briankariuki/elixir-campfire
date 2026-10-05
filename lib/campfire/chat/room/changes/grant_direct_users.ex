defmodule Campfire.Chat.Room.Changes.GrantDirectUsers do
  @moduledoc "Direct rooms: grants the room to the `user_ids` argument."

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Campfire.Chat.Membership

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.after_action(changeset, fn changeset, room ->
      Membership.grant(room, Changeset.get_argument(changeset, :user_ids))
      {:ok, room}
    end)
  end
end
