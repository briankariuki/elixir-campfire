defmodule Campfire.Chat.Membership do
  @moduledoc """
  Links a user to a room, with an involvement level and an `unread_at` mark.

  Grants are idempotent bulk upserts that keep existing rows, see `grant/3`.
  """

  use Ash.Resource,
    otp_app: :campfire,
    domain: Campfire.Chat,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  alias Campfire.Chat.Changes.BroadcastAfterCommit
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

    create :grant do
      description "Internal: grants a room to a user. Idempotent: an existing membership is kept."
      accept [:room_id, :user_id, :involvement]
      upsert? true
      upsert_identity :unique_room_user
      # Nothing to update on conflict, so an existing row is left untouched.
      upsert_fields []
    end

    update :set_involvement do
      require_atomic? false
      accept [:involvement]
      change {BroadcastAfterCommit, topic: :user, event: :sidebar_changed, payload: :none}
    end

    update :mark_read do
      require_atomic? false
      accept []
      change set_attribute(:unread_at, nil)
      change {BroadcastAfterCommit, topic: :user, event: :room_read, payload: :room_id}
    end

    update :mark_unread do
      description "Internal: marks the room unread for members, in bulk (see Message.Changes.AfterCreate)."
      accept [:unread_at]
    end

    destroy :revoke do
      description "Removes a user from a room (admin or room creator)."
      require_atomic? false
      change {BroadcastAfterCommit, topic: :user, event: :room_removed, payload: :room_id}
      change {BroadcastAfterCommit, topic: :user, event: :sidebar_changed, payload: :none}
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

  ## Internal helpers
  #
  # System work done on behalf of other actions (granting a room to users, cleaning up after a
  # deactivation), not on behalf of an actor, so these run with `authorize?: false`.

  @doc """
  Grants `room` to `user_ids` with the room's default involvement. Idempotent.
  Returns the ids of the users that were newly granted.
  """
  def grant(%{id: _, kind: _} = room, user_ids, involvement \\ nil) do
    involvement = involvement || Room.default_involvement(room)

    rows =
      for user_id <- Enum.uniq(user_ids) do
        %{room_id: room.id, user_id: user_id, involvement: involvement}
      end

    # Existing rows come back too (untouched, since `upsert_fields: []`); the `:upsert_action`
    # metadata tells the inserted ones from the conflicts.
    %Ash.BulkResult{records: records} =
      Ash.bulk_create!(rows, __MODULE__, :grant,
        upsert?: true,
        upsert_identity: :unique_room_user,
        upsert_fields: [],
        return_records?: true,
        authorize?: false
      )

    for record <- records || [],
        Ash.Resource.get_metadata(record, :upsert_action) == :insert,
        do: record.user_id
  end

  @doc "Grants every open room to the user (on registration and bot creation)."
  def grant_open_rooms(user_id) do
    Room
    |> Ash.Query.filter(kind == :open)
    |> Ash.Query.select([:id, :kind])
    |> Ash.read!(authorize?: false)
    |> Enum.each(&grant(&1, [user_id]))
  end

  @doc """
  Deletes the memberships of `user_ids` in the room through the `:revoke` action, which
  notifies each revoked user. Returns the revoked user ids.
  """
  def revoke(_room_id, []), do: []

  def revoke(room_id, user_ids) do
    __MODULE__
    |> Ash.Query.filter(room_id == ^room_id and user_id in ^user_ids)
    |> revoke_all()
    |> Enum.map(& &1.user_id)
  end

  @doc "Deletes the user's memberships in open and closed rooms (deactivation)."
  def revoke_all_except_direct(user_id) do
    __MODULE__
    |> Ash.Query.filter(user_id == ^user_id and room.kind != :direct)
    |> revoke_all()

    :ok
  end

  @doc "The ids of the room's members."
  def member_ids(room_id) do
    __MODULE__
    |> Ash.Query.filter(room_id == ^room_id)
    |> Ash.Query.select([:user_id])
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.user_id)
  end

  defp revoke_all(query) do
    %Ash.BulkResult{records: records} =
      Ash.bulk_destroy!(query, :revoke, %{},
        authorize?: false,
        notify?: true,
        return_records?: true,
        strategy: [:stream]
      )

    records || []
  end
end
