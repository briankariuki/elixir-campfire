defmodule Campfire.Chat.Message.Changes.EnsureClientMessageId do
  @moduledoc "Generates a `client_message_id` (a UUID) when the caller didn't send one."

  use Ash.Resource.Change

  alias Ash.Changeset

  @impl true
  def change(changeset, _opts, _context) do
    case Changeset.get_attribute(changeset, :client_message_id) do
      id when is_binary(id) and id != "" -> changeset
      _ -> Changeset.force_change_attribute(changeset, :client_message_id, Ecto.UUID.generate())
    end
  end
end
