defmodule Campfire.Chat.RoomChanges do
  @moduledoc false
  # The changes behind the Room actions: membership grants, direct rooms and deletion.

  import Ecto.Query

  require Ash.Query

  alias Ash.Changeset
  alias Campfire.{Broadcast, Repo, Uploads}
  alias Campfire.Chat.{Membership, Message, Room}

  @doc "Open rooms: every active user (bots included) is a member."
  def grant_active_users(_changeset, room, _context) do
    user_ids = Repo.all(from u in "users", where: u.status == "active", select: u.id)
    Membership.grant(room, user_ids)
    {:ok, room}
  end

  @doc "Closed rooms: grant the `user_ids` argument and revoke everyone else."
  def revise_members(changeset, room, _context) do
    wanted = existing_user_ids(Changeset.get_argument(changeset, :user_ids) || [])
    revoked = Membership.revoke(room.id, Membership.member_ids(room.id) -- wanted)
    Membership.grant(room, wanted)
    {:ok, Ash.Resource.put_metadata(room, :revoked_user_ids, revoked)}
  end

  @doc "Broadcasts sidebar changes to the members (and removal to revoked users) after commit."
  def notify_members(_changeset, {:ok, room}, _context) do
    Broadcast.users(Membership.member_ids(room.id), :sidebar_changed)

    revoked = Map.get(room.__metadata__, :revoked_user_ids, [])
    Broadcast.users(revoked, {:room_removed, room.id})
    Broadcast.users(revoked, :sidebar_changed)

    {:ok, room}
  end

  def notify_members(_changeset, error, _context), do: error

  def validate_not_direct(changeset, _context) do
    if changeset.data.kind == :direct do
      {:error, field: :kind, message: "can't be changed for a direct room"}
    else
      :ok
    end
  end

  ## Direct rooms

  def set_direct_key(changeset, _context) do
    user_ids = Changeset.get_argument(changeset, :user_ids) || []
    Changeset.force_change_attribute(changeset, :direct_key, Room.direct_key(user_ids))
  end

  def grant_direct_users(changeset, room, _context) do
    Membership.grant(room, Changeset.get_argument(changeset, :user_ids))
    {:ok, room}
  end

  def find_or_create_direct(input, context) do
    actor = context.actor
    user_ids = existing_user_ids([actor.id | input.arguments.user_ids])
    key = Room.direct_key(user_ids)

    case find_direct(key) do
      %Room{} = room ->
        {:ok, room}

      nil ->
        Room
        |> Changeset.for_create(:create_direct, %{user_ids: user_ids}, actor: actor)
        |> Ash.create(authorize?: false)
        |> case do
          {:ok, room} ->
            {:ok, room}

          # Lost a race with another request creating the same room.
          {:error, error} ->
            case find_direct(key) do
              %Room{} = room -> {:ok, room}
              nil -> {:error, error}
            end
        end
    end
  end

  defp find_direct(key) do
    Room
    |> Ash.Query.filter(direct_key == ^key)
    |> Ash.read_one!(authorize?: false)
  end

  ## Deletion

  def destroy_contents(changeset, _context) do
    changeset
    |> Changeset.before_action(fn changeset ->
      room_id = changeset.data.id

      attachment_keys =
        Repo.all(
          from m in Message,
            where: m.room_id == ^room_id and not is_nil(m.attachment_key),
            select: m.attachment_key
        )

      Changeset.put_context(changeset, :room_contents, %{
        member_ids: Membership.member_ids(room_id),
        attachment_keys: attachment_keys
      })
    end)
    |> Changeset.after_transaction(fn
      changeset, {:ok, room} ->
        %{member_ids: member_ids, attachment_keys: keys} = changeset.context.room_contents
        Enum.each(keys, &Uploads.delete/1)
        Broadcast.users(member_ids, {:room_removed, room.id})
        Broadcast.users(member_ids, :sidebar_changed)
        {:ok, room}

      _changeset, error ->
        error
    end)
  end

  defp existing_user_ids(user_ids) do
    user_ids = Enum.uniq(user_ids)
    Repo.all(from u in "users", where: u.id in ^user_ids, select: u.id)
  end
end
