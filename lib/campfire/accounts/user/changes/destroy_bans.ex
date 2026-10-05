defmodule Campfire.Accounts.User.Changes.DestroyBans do
  @moduledoc "After the user is unbanned, deletes the IP bans recorded for them."

  use Ash.Resource.Change

  alias Campfire.Accounts.Ban

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, user ->
      user_id = user.id

      # System work inside an administrator action (bans have no destroy policy).
      Ban
      |> Ash.Query.filter(user_id == ^user_id)
      |> Ash.bulk_destroy!(:destroy, %{}, authorize?: false, return_errors?: true)

      {:ok, user}
    end)
  end
end
