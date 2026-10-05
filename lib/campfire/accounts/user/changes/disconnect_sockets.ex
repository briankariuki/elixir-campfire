defmodule Campfire.Accounts.User.Changes.DisconnectSockets do
  @moduledoc """
  Disconnects the user's LiveView sockets once the transaction has committed, so a reconnect
  can't find a half-updated user. (`Session.destroy` also disconnects, but from inside the
  outer transaction.)
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_transaction(changeset, fn
      _changeset, {:ok, user} ->
        Campfire.Broadcast.disconnect_user(user.id)
        {:ok, user}

      _changeset, error ->
        error
    end)
  end
end
