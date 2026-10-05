defmodule Campfire.Accounts.Account.Actions.ValidJoinCode do
  @moduledoc "Whether the `:code` argument is the account's join code (constant-time compare)."

  use Ash.Resource.Actions.Implementation

  alias Campfire.Accounts.Account

  @impl true
  def run(input, _opts, _context) do
    valid? =
      case {Campfire.Accounts.get_account!(), input.arguments[:code]} do
        {%Account{join_code: join_code}, code} when is_binary(code) ->
          Plug.Crypto.secure_compare(join_code, code)

        _ ->
          false
      end

    {:ok, valid?}
  end
end
