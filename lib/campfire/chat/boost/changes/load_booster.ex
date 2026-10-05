defmodule Campfire.Chat.Boost.Changes.LoadBooster do
  @moduledoc "Loads the booster on the saved boost, as broadcasts and pages show who boosted."

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, boost ->
      # Internal load of the actor's own user for the broadcast; no policy check needed.
      {:ok, Ash.load!(boost, [:booster], authorize?: false)}
    end)
  end
end
