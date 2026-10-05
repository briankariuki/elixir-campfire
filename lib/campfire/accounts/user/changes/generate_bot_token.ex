defmodule Campfire.Accounts.User.Changes.GenerateBotToken do
  @moduledoc "Sets `bot_token` to a fresh 12-character alphanumeric token."

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.force_change_attribute(changeset, :bot_token, Campfire.Random.alphanumeric(12))
  end

  # Everything is in hooks and arguments, so the same changeset works for atomic actions.
  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
