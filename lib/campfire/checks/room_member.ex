defmodule Campfire.Checks.RoomMember do
  @moduledoc """
  For creates: the actor is a member of the room being written to. The room is taken from the
  changeset's `room_id` attribute (messages) or from the `:message` argument (boosts).
  """

  use Ash.Policy.SimpleCheck

  alias Campfire.Chat.{Boost, Membership, Message}

  require Ash.Query

  @impl true
  def describe(_opts), do: "actor is a member of the room"

  @impl true
  def match?(%{id: user_id}, %{subject: %Ash.Changeset{} = changeset}, _opts) do
    case room_id(changeset) do
      nil ->
        false

      room_id ->
        # The check itself is the authorization, so the lookup must not be policy-filtered
        # (a non-member could never see the membership rows).
        Membership
        |> Ash.Query.filter(room_id == ^room_id and user_id == ^user_id)
        |> Ash.exists?(authorize?: false)
    end
  end

  def match?(_actor, _context, _opts), do: false

  defp room_id(%{resource: Message} = changeset) do
    Ash.Changeset.get_attribute(changeset, :room_id)
  end

  defp room_id(%{resource: Boost} = changeset) do
    case Ash.Changeset.get_argument(changeset, :message) do
      %{room_id: room_id} -> room_id
      _ -> nil
    end
  end
end
