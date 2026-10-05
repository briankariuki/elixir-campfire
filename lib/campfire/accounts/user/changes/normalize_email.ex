defmodule Campfire.Accounts.User.Changes.NormalizeEmail do
  @moduledoc "Trims and downcases the email address."

  use Ash.Resource.Change

  alias Ash.Changeset

  @impl true
  def change(changeset, _opts, _context) do
    case Changeset.get_attribute(changeset, :email_address) do
      email when is_binary(email) ->
        Changeset.force_change_attribute(
          changeset,
          :email_address,
          email |> String.trim() |> String.downcase()
        )

      _ ->
        changeset
    end
  end
end
