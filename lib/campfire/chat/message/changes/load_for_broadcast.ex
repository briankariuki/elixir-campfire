defmodule Campfire.Chat.Message.Changes.LoadForBroadcast do
  @moduledoc """
  After a message is saved: reloads it with the associations that broadcasts carry
  (`Campfire.Chat.Message.loads/0`), without touching the room (unlike `TouchRoomAndLoad`).
  """

  use Ash.Resource.Change

  alias Campfire.Chat.Message

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, message ->
      {:ok, Ash.load!(message, Message.loads(), authorize?: false, reuse_values?: false)}
    end)
  end

  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
