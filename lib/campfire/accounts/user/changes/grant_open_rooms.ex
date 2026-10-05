defmodule Campfire.Accounts.User.Changes.GrantOpenRooms do
  @moduledoc "After the user is created, grants them every open room."

  use Ash.Resource.Change

  alias Campfire.Chat.Membership

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, user ->
      Membership.grant_open_rooms(user.id)
      {:ok, user}
    end)
  end
end
