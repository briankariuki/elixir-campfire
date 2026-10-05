defmodule Campfire.Chat.Boost.Changes.SetMessage do
  @moduledoc "Sets `message_id` from the `:message` argument."

  use Ash.Resource.Change

  alias Ash.Changeset

  @impl true
  def change(changeset, _opts, _context) do
    case Changeset.get_argument(changeset, :message) do
      %{id: id} -> Changeset.force_change_attribute(changeset, :message_id, id)
      _ -> changeset
    end
  end
end
