defmodule Campfire.Checks.CanCreateRooms do
  @moduledoc """
  Open and closed rooms can be created by any active person (not bots), unless the account
  restricts room creation to administrators.
  """

  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "actor can create rooms"

  @impl true
  def match?(%{status: :active, role: :administrator}, _context, _opts), do: true

  def match?(%{status: :active, role: :member}, _context, _opts) do
    case Campfire.Accounts.get_account!(authorize?: false) do
      %{restrict_room_creation_to_administrators: true} -> false
      _ -> true
    end
  end

  def match?(_actor, _context, _opts), do: false
end
