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

  # Everything is in hooks and arguments, so the same changeset works for atomic actions.
  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
