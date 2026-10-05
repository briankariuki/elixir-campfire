defmodule Campfire.Chat.Message.Changes.DeleteAttachment do
  @moduledoc "After a message is destroyed and committed: deletes its attachment file."

  use Ash.Resource.Change

  alias Campfire.Uploads

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_transaction(changeset, fn
      _changeset, {:ok, message} ->
        Uploads.delete(message.attachment_key)
        {:ok, message}

      _changeset, error ->
        error
    end)
  end
end
