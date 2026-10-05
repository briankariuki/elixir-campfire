defmodule Campfire.Accounts.Account.Actions.FirstRun do
  @moduledoc """
  Creates the account, the first administrator and the open room "All Talk". The action is
  declared `transaction? true`, so an error from any step rolls everything back.
  """

  use Ash.Resource.Actions.Implementation

  alias Campfire.Accounts.{Account, User}
  alias Campfire.Accounts.Errors.AlreadySetUp

  @user_fields [:name, :email_address, :password, :avatar_key]

  @impl true
  def run(input, _opts, _context) do
    if Campfire.Accounts.get_account!() do
      {:error, AlreadySetUp.exception([])}
    else
      attrs = Map.take(input.arguments, @user_fields)

      # No administrator exists yet, so every step here is system work without an actor.
      with {:ok, account} <-
             Account
             |> Ash.Changeset.for_create(:create, %{})
             |> Ash.create(authorize?: false),
           {:ok, user} <-
             User
             |> Ash.Changeset.for_create(:register_administrator, attrs)
             |> Ash.create(authorize?: false),
           {:ok, room} <-
             Campfire.Chat.create_open_room("All Talk",
               actor: user,
               authorize?: false,
               context: %{warn_on_transaction_hooks?: false}
             ) do
        {:ok, %{account: account, user: user, room: room}}
      end
    end
  end
end
