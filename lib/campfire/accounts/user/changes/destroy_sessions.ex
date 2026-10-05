defmodule Campfire.Accounts.User.Changes.DestroySessions do
  @moduledoc """
  After the user action, destroys all of the user's sessions through `Session`'s `:destroy`
  action (so its own side effects run for each).
  """

  use Ash.Resource.Change

  alias Campfire.Accounts.Session

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, user ->
      user_id = user.id

      # System work on behalf of an administrator action. `:destroy` is atomic, so this is one
      # DELETE; its hooks still run, and `:stream` is the fallback.
      Session
      |> Ash.Query.filter(user_id == ^user_id)
      |> Ash.bulk_destroy!(:destroy, %{},
        authorize?: false,
        return_errors?: true,
        notify?: true,
        strategy: [:atomic, :stream]
      )

      {:ok, user}
    end)
  end

  # Everything is in hooks and arguments, so the same changeset works for atomic actions.
  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
