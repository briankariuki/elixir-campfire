defmodule Campfire.Accounts.Ban.Actions.BannedIp do
  @moduledoc "Whether a ban exists for the `:ip_address` argument."

  use Ash.Resource.Actions.Implementation

  alias Campfire.Accounts.Ban

  require Ash.Query

  @impl true
  def run(input, _opts, _context) do
    case input.arguments[:ip_address] do
      ip when is_binary(ip) ->
        # Checked on every request by anonymous visitors, who can't read the ban list; the
        # action's own policy is what exposes this single yes/no answer.
        {:ok,
         Ban
         |> Ash.Query.filter(ip_address == ^ip)
         |> Ash.exists?(authorize?: false)}

      _ ->
        {:ok, false}
    end
  end
end
