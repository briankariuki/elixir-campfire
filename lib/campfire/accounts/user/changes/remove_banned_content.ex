defmodule Campfire.Accounts.User.Changes.RemoveBannedContent do
  @moduledoc """
  The body of the `:remove_banned_content` Oban job: deletes all of the user's messages.
  Idempotent, a user without messages is a no-op.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, user ->
      :ok = Campfire.Chat.Message.remove_all_by_creator(user.id)
      {:ok, user}
    end)
  end
end
