defmodule Campfire.Chat.Boost.Changes.SetMessage do
  @moduledoc "Sets `message_id` and `room_id` from the `:message` argument."

  use Ash.Resource.Change

  alias Ash.Changeset

  @impl true
  def change(changeset, _opts, _context) do
    case Changeset.get_argument(changeset, :message) do
      %{id: id, room_id: room_id} ->
        changeset
        |> Changeset.force_change_attribute(:message_id, id)
        |> Changeset.force_change_attribute(:room_id, room_id)

      _ ->
        changeset
    end
  end
end
