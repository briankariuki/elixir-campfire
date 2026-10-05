defmodule Campfire.Accounts.User.Preparations.VerifyPassword do
  @moduledoc """
  Keeps the single user found by the query only if the `:password` argument matches their
  hash. Runs a dummy bcrypt check otherwise, so response time doesn't reveal which emails exist.
  """

  use Ash.Resource.Preparation

  alias Campfire.Accounts.User

  @impl true
  def prepare(query, _opts, _context) do
    Ash.Query.after_action(query, fn query, users ->
      password = Ash.Query.get_argument(query, :password)

      case users do
        [%User{password_hash: hash} = user] when is_binary(hash) ->
          if Bcrypt.verify_pass(password, hash), do: {:ok, [user]}, else: {:ok, []}

        _ ->
          Bcrypt.no_user_verify()
          {:ok, []}
      end
    end)
  end
end
