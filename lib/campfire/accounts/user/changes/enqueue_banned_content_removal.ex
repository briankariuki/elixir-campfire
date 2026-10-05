defmodule Campfire.Accounts.User.Changes.EnqueueBannedContentRemoval do
  @moduledoc """
  After the ban has committed, enqueues the `:remove_banned_content` Oban job that deletes the
  user's messages.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_transaction(changeset, fn
      _changeset, {:ok, user} ->
        AshOban.run_trigger(user, :remove_banned_content)
        {:ok, user}

      _changeset, error ->
        error
    end)
  end

  # Everything is in hooks, so the same changeset works for atomic actions.
  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
