defmodule Campfire.Accounts.User.Changes.RemoveBannedContent do
  @moduledoc "After the ban has committed, removes all of the user's messages (asynchronously)."

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_transaction(changeset, fn
      _changeset, {:ok, user} ->
        Campfire.Async.run(fn -> Campfire.Chat.Message.remove_all_by_creator(user.id) end)
        {:ok, user}

      _changeset, error ->
        error
    end)
  end
end
