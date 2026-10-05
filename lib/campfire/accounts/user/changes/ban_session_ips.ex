defmodule Campfire.Accounts.User.Changes.BanSessionIps do
  @moduledoc """
  After the user is banned, records a `Ban` for each distinct public IP address of their
  sessions. Must run before `DestroySessions`.
  """

  use Ash.Resource.Change

  alias Campfire.Accounts.{Ban, Session}

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, user ->
      user_id = user.id

      # System work: neither sessions nor bans are readable/creatable through the acting
      # administrator's policies.
      inputs =
        Session
        |> Ash.Query.filter(user_id == ^user_id and not is_nil(ip_address))
        |> Ash.Query.select([:ip_address])
        |> Ash.read!(authorize?: false)
        |> Enum.map(& &1.ip_address)
        |> Enum.uniq()
        |> Enum.filter(&Ban.public_ip?/1)
        |> Enum.map(&%{user_id: user_id, ip_address: &1})

      Ash.bulk_create!(inputs, Ban, :create, authorize?: false, return_errors?: true)
      {:ok, user}
    end)
  end

  # Everything is in hooks and arguments, so the same changeset works for atomic actions.
  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
