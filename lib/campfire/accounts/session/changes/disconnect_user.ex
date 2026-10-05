defmodule Campfire.Accounts.Session.Changes.DisconnectUser do
  @moduledoc "After the session is destroyed, disconnects its user's LiveView sockets."

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_transaction(changeset, fn
      _changeset, {:ok, session} ->
        Campfire.Broadcast.disconnect_user(session.user_id)
        {:ok, session}

      _changeset, error ->
        error
    end)
  end

  # Everything is in hooks and arguments, so the same changeset works for atomic actions.
  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
