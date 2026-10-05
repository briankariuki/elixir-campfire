defmodule Campfire.Accounts.Account.Actions.SetUp do
  @moduledoc "Whether first run has happened (an account exists)."

  use Ash.Resource.Actions.Implementation

  @impl true
  def run(_input, _opts, _context) do
    {:ok, Campfire.Accounts.get_account!() != nil}
  end
end
