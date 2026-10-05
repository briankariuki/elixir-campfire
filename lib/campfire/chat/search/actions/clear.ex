defmodule Campfire.Chat.Search.Actions.Clear do
  @moduledoc "Deletes all of the actor's searches."

  use Ash.Resource.Actions.Implementation

  alias Campfire.Chat.Search

  @impl true
  def run(_input, _opts, context) do
    Search.clear_for(context.actor.id)
    :ok
  end
end
