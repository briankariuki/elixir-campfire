defmodule Campfire.Chat.Message.Changes.SetRoom do
  @moduledoc "Sets `room_id` from the `:room` argument."

  use Ash.Resource.Change

  alias Ash.Changeset

  @impl true
  def change(changeset, _opts, _context) do
    case Changeset.get_argument(changeset, :room) do
      %{id: room_id} -> Changeset.force_change_attribute(changeset, :room_id, room_id)
      _ -> changeset
    end
  end
end
