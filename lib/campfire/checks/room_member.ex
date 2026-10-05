defmodule Campfire.Checks.RoomMember do
  @moduledoc """
  For creates: the actor is a member of the room being written to. The room is taken from the
  changeset's `room_id` attribute (messages) or from its `message_id`'s room (boosts).
  """

  use Ash.Policy.SimpleCheck

  import Ecto.Query

  alias Campfire.Chat.{Membership, Message}
  alias Campfire.Repo

  @impl true
  def describe(_opts), do: "actor is a member of the room"

  @impl true
  def match?(%{id: user_id}, %{subject: %Ash.Changeset{} = changeset}, _opts) do
    case room_id(changeset) do
      nil ->
        false

      room_id ->
        Repo.exists?(from m in Membership, where: m.room_id == ^room_id and m.user_id == ^user_id)
    end
  end

  def match?(_actor, _context, _opts), do: false

  defp room_id(%{resource: Message} = changeset) do
    Ash.Changeset.get_attribute(changeset, :room_id)
  end

  defp room_id(%{resource: Campfire.Chat.Boost} = changeset) do
    case Ash.Changeset.get_attribute(changeset, :message_id) do
      nil -> nil
      message_id -> Repo.one(from m in Message, where: m.id == ^message_id, select: m.room_id)
    end
  end
end
