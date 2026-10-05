defmodule Campfire.Chat.Message.Changes.TouchRoomAndLoad do
  @moduledoc """
  After a message is saved: bumps the room's `updated_at` and reloads the message with the
  associations that broadcasts and pages carry (`Campfire.Chat.Message.loads/0`).
  """

  use Ash.Resource.Change

  alias Campfire.Chat.{Message, Room}

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, message ->
      touch_room(message.room_id)
      {:ok, Ash.load!(message, Message.loads(), authorize?: false, reuse_values?: false)}
    end)
  end

  # System bookkeeping on the message's room: the author may not be allowed to update rooms.
  defp touch_room(room_id) do
    Room
    |> Ash.Query.filter(id == ^room_id)
    |> Ash.bulk_update!(:touch, %{}, authorize?: false, strategy: :atomic)
  end
end
