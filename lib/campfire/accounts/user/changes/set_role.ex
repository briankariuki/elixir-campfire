defmodule Campfire.Accounts.User.Changes.SetRole do
  @moduledoc """
  Sets `role` from the `:role` argument: `:administrator` makes an administrator, anything else
  a member. Bots are rejected by the action's own validation.
  """

  use Ash.Resource.Change

  alias Ash.Changeset

  @impl true
  def change(changeset, _opts, _context) do
    role =
      if Changeset.get_argument(changeset, :role) == :administrator,
        do: :administrator,
        else: :member

    Changeset.change_attribute(changeset, :role, role)
  end

  # Everything is in hooks and arguments, so the same changeset works for atomic actions.
  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
