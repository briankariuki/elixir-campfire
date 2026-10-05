defmodule Campfire.Chat.Room.Changes.SetDirectKey do
  @moduledoc "Sets the canonical `direct_key` from the `user_ids` argument."

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Campfire.Chat.Room

  @impl true
  def change(changeset, _opts, _context) do
    user_ids = Changeset.get_argument(changeset, :user_ids) || []
    Changeset.force_change_attribute(changeset, :direct_key, Room.direct_key(user_ids))
  end
end
