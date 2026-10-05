defmodule Campfire.Chat.Search.Changes.PruneOld do
  @moduledoc "After a search is recorded: keeps only the user's newest searches."

  use Ash.Resource.Change

  alias Campfire.Chat.Search

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, search ->
      Search.prune(search.user_id)
      {:ok, search}
    end)
  end
end
