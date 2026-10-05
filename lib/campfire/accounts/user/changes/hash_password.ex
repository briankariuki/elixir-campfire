defmodule Campfire.Accounts.User.Changes.HashPassword do
  @moduledoc "Bcrypt-hashes the `:password` argument into `password_hash` (blank or missing: no change)."

  use Ash.Resource.Change

  alias Ash.Changeset

  @impl true
  def change(changeset, _opts, _context) do
    case Changeset.get_argument(changeset, :password) do
      password when is_binary(password) and password != "" ->
        Changeset.force_change_attribute(
          changeset,
          :password_hash,
          Bcrypt.hash_pwd_salt(password)
        )

      _ ->
        changeset
    end
  end
end
