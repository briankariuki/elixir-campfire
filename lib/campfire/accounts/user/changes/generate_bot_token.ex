defmodule Campfire.Accounts.User.Changes.GenerateBotToken do
  @moduledoc "Sets `bot_token` to a fresh 12-character alphanumeric token."

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.force_change_attribute(changeset, :bot_token, Campfire.Random.alphanumeric(12))
  end
end
