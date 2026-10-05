defmodule Campfire.Accounts.Session.Changes.TouchIfStale do
  @moduledoc """
  Refreshes `last_active_at` (plus the accepted IP and user agent) only when the session is more
  than an hour old; otherwise discards the accepted changes so nothing is written. This
  throttles the write on every request.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Campfire.Accounts.Session

  # Reads `last_active_at` from the record, so the action needs `require_atomic? false`.
  @impl true
  def change(changeset, _opts, _context) do
    if Session.stale?(changeset.data) do
      Changeset.force_change_attribute(changeset, :last_active_at, DateTime.utc_now())
    else
      changeset
      |> Changeset.clear_change(:ip_address)
      |> Changeset.clear_change(:user_agent)
    end
  end
end
