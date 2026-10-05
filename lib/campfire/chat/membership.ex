defmodule Campfire.Chat.Membership do
  @moduledoc """
  Links a user to a room, with an involvement level and an `unread_at` mark.

  Grants are idempotent bulk inserts (`ON CONFLICT DO NOTHING`), see `grant/3`.
  """

  use Ash.Resource,
    otp_app: :campfire,
    domain: Campfire.Chat,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  import Ecto.Query

  alias Campfire.{Broadcast, Repo}
  alias Campfire.Chat.Room

  postgres do
    table "memberships"
    repo Campfire.Repo

    references do
      reference :room, on_delete: :delete
      reference :user, on_delete: :delete
    end

    custom_indexes do
      index [:user_id]
    end
  end

  actions do
    defaults [:read]

    read :mine do
      description "The actor's memberships, with their rooms loaded."
      filter expr(user_id == ^actor(:id))
      prepare build(load: [:room])
    end

    read :for_room do
      description "The actor's membership in a room."
      get? true
      argument :room_id, :integer, allow_nil?: false
      filter expr(user_id == ^actor(:id) and room_id == ^arg(:room_id))
    end

    update :set_involvement do
      require_atomic? false
      accept [:involvement]

      change after_transaction(fn
               _changeset, {:ok, membership}, _context ->
                 Broadcast.user(membership.user_id, :sidebar_changed)
                 {:ok, membership}

               _changeset, error, _context ->
                 error
             end)
    end

    update :mark_read do
      require_atomic? false
      accept []
      change set_attribute(:unread_at, nil)

      change after_transaction(fn
               _changeset, {:ok, membership}, _context ->
                 Broadcast.user(membership.user_id, {:room_read, membership.room_id})
                 {:ok, membership}

               _changeset, error, _context ->
                 error
             end)
    end

    destroy :revoke do
      description "Removes a user from a room (admin or room creator)."
      require_atomic? false

      change after_transaction(fn
               _changeset, {:ok, membership}, _context ->
                 Broadcast.user(membership.user_id, {:room_removed, membership.room_id})
                 Broadcast.user(membership.user_id, :sidebar_changed)
                 {:ok, membership}

               _changeset, error, _context ->
                 error
             end)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(user_id == ^actor(:id))
      authorize_if expr(exists(room.memberships, user_id == ^actor(:id)))
    end

    policy action([:set_involvement, :mark_read]) do
      authorize_if expr(user_id == ^actor(:id))
    end

    policy action(:revoke) do
      authorize_if actor_attribute_equals(:role, :administrator)
      authorize_if expr(room.creator_id == ^actor(:id))
    end
  end

  attributes do
    integer_primary_key :id

    attribute :involvement, :atom do
      allow_nil? false
      default :mentions
      constraints one_of: [:invisible, :nothing, :mentions, :everything]
      public? true
    end

    attribute :unread_at, :utc_datetime_usec, public?: true

    timestamps()
  end

  relationships do
    belongs_to :room, Campfire.Chat.Room do
      allow_nil? false
      attribute_type :integer
      public? true
    end

    belongs_to :user, Campfire.Accounts.User do
      allow_nil? false
      attribute_type :integer
      public? true
    end
  end

  identities do
    identity :unique_room_user, [:room_id, :user_id]
  end

  ## Internal helpers (no authorization; used by room and user actions)

  @doc """
  Grants `room` to `user_ids` with the room's default involvement. Idempotent.
  Returns the ids of the users that were newly granted.
  """
  def grant(%{id: _, kind: _} = room, user_ids, involvement \\ nil) do
    involvement = to_string(involvement || Room.default_involvement(room))
    now = NaiveDateTime.utc_now()

    rows =
      for user_id <- Enum.uniq(user_ids) do
        %{
          room_id: room.id,
          user_id: user_id,
          involvement: involvement,
          inserted_at: now,
          updated_at: now
        }
      end

    {_count, inserted} =
      Repo.insert_all("memberships", rows,
        on_conflict: :nothing,
        conflict_target: [:room_id, :user_id],
        returning: [:user_id]
      )

    Enum.map(inserted, & &1.user_id)
  end

  @doc "Grants every open room to the user (on registration and bot creation)."
  def grant_open_rooms(user_id) do
    from(r in "rooms", where: r.kind == "open", select: r.id)
    |> Repo.all()
    |> Enum.each(&grant(%{id: &1, kind: :open}, [user_id]))
  end

  @doc "Deletes the memberships of `user_ids` in the room. Returns the revoked user ids."
  def revoke(room_id, user_ids) do
    {_count, deleted} =
      from(m in __MODULE__,
        where: m.room_id == ^room_id and m.user_id in ^user_ids,
        select: m.user_id
      )
      |> Repo.delete_all()

    deleted
  end

  @doc "Deletes the user's memberships in open and closed rooms (deactivation)."
  def revoke_all_except_direct(user_id) do
    direct_room_ids = from(r in "rooms", where: r.kind == "direct", select: r.id)

    from(m in __MODULE__,
      where: m.user_id == ^user_id and m.room_id not in subquery(direct_room_ids)
    )
    |> Repo.delete_all()
  end

  @doc "The ids of the room's members."
  def member_ids(room_id) do
    Repo.all(from m in __MODULE__, where: m.room_id == ^room_id, select: m.user_id)
  end
end
