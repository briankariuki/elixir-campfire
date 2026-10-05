defmodule Campfire.Accounts.User.Actions.AuthenticateBot do
  @moduledoc "Finds the active bot for a `<id>-<token>` bot key (constant-time token check)."

  use Ash.Resource.Actions.Implementation

  alias Campfire.Accounts.User

  require Ash.Query

  @impl true
  def run(input, _opts, _context) do
    {:ok, find_bot_by_key(input.arguments.bot_key)}
  end

  defp find_bot_by_key(bot_key) when is_binary(bot_key) do
    with [id_part, token] when token != "" <- String.split(bot_key, "-", parts: 2),
         {id, ""} <- Integer.parse(id_part),
         {:ok, %User{bot_token: bot_token} = bot} when is_binary(bot_token) <-
           User
           |> Ash.Query.filter(id == ^id and role == :bot and status == :active)
           # The key itself is the credential, so there is no actor to authorize.
           |> Ash.read_one(authorize?: false),
         true <- Plug.Crypto.secure_compare(bot_token, token) do
      bot
    else
      _ -> nil
    end
  end

  defp find_bot_by_key(_), do: nil
end
